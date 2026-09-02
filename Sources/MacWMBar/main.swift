import AppKit
import Foundation
import MacWMCore
import MacWMTransport

private let stateNotification = Notification.Name("com.macwm.stateChanged")

/// The bar window: a blurred strip on one screen edge holding the configured
/// modules, fed by the daemon's state notifications and system readings.
@MainActor
final class BarController: NSObject {
    private let client = UnixSocketClient(path: "/tmp/macwm.sock")
    private let panel: NSPanel
    private var config: Config
    private var configModified: Date?
    private var state = BarState()
    private var modules: [BarModule] = []
    private var metricsTimer: Timer?
    private var previousCPUTicks: [UInt32]?
    private var previousNetworkBytes: (input: UInt64, output: UInt64)?
    private let agentsMonitor = AgentsMonitor()
    private let settings = SettingsWindowController()

    override init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        config = Self.loadConfig()
        configModified = Self.configModificationDate()
        super.init()
        configurePanel()
        buildContent()
        readInitialState()
        refreshMetrics()
        metricsTimer = Timer.scheduledTimer(timeInterval: 2, target: self, selector: #selector(refreshMetrics), userInfo: nil, repeats: true)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(stateChanged(_:)), name: stateNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(screenParametersChanged(_:)), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        repositionPanel()
        panel.orderFrontRegardless()
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
        NotificationCenter.default.removeObserver(self)
    }

    private var position: BarPosition { config.barPosition }

    private var actions: BarActions {
        BarActions(
            switchWorkspace: { [weak self] workspace in self?.send(.workspace(workspace)) },
            cycleFocus: { [weak self] in self?.send(.cycleFocus(forward: true)) },
            openSettings: { [weak self] in self?.openSettings() },
            reloadConfiguration: { [weak self] in self?.send(.reload) },
            restartDaemon: { Self.restartDaemon() }
        )
    }

    private func configurePanel() {
        panel.isFloatingPanel = true
        panel.level = .mainMenu
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.delegate = self
    }

    /// Builds the strip for the current position and options; safe to call again.
    private func buildContent() {
        let isVertical = position.isVertical
        let theme = BarTheme(options: config.bar, isVertical: isVertical)
        let axis: NSLayoutConstraint.Orientation = isVertical ? .vertical : .horizontal

        let content = BarContentView()
        content.material = .hudWindow
        content.blendingMode = .behindWindow
        content.state = .active
        content.onScroll = { [weak self] delta in
            guard let self else { return }
            let target = min(9, max(1, self.state.activeWorkspace + delta))
            if target != self.state.activeWorkspace { self.send(.workspace(target)) }
        }
        let overlay = NSView()
        overlay.wantsLayer = true
        overlay.layer?.backgroundColor = NSColor.black.withAlphaComponent(CGFloat(config.bar.opacity)).cgColor
        overlay.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(overlay)

        modules = []
        func group(_ names: [String]) -> NSStackView {
            let stack = NSStackView()
            stack.orientation = isVertical ? .vertical : .horizontal
            stack.alignment = isVertical ? .centerX : .centerY
            stack.spacing = 8
            for name in names {
                guard let module = makeModule(name, theme: theme) else { continue }
                modules.append(module)
                stack.addArrangedSubview(module.view)
            }
            return stack
        }
        let left = group(config.bar.left)
        let center = group(config.bar.center)
        let right = group(config.bar.right)
        let leadingSpacer = NSView()
        let trailingSpacer = NSView()
        for stack in [left, right] {
            stack.setContentHuggingPriority(.required, for: axis)
            stack.setContentCompressionResistancePriority(.required, for: axis)
        }
        center.setContentHuggingPriority(.required, for: axis)
        center.setContentCompressionResistancePriority(.defaultLow, for: axis)
        for spacer in [leadingSpacer, trailingSpacer] { spacer.setContentHuggingPriority(.defaultLow, for: axis) }

        let root = NSStackView(views: [left, leadingSpacer, center, trailingSpacer, right])
        root.orientation = isVertical ? .vertical : .horizontal
        root.alignment = isVertical ? .centerX : .centerY
        root.distribution = .fill
        root.spacing = 10
        root.edgeInsets = isVertical ? NSEdgeInsets(top: 8, left: 2, bottom: 8, right: 2) : NSEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
        root.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(root)
        NSLayoutConstraint.activate([
            overlay.leadingAnchor.constraint(equalTo: content.leadingAnchor), overlay.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            overlay.topAnchor.constraint(equalTo: content.topAnchor), overlay.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor), root.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            root.topAnchor.constraint(equalTo: content.topAnchor), root.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            isVertical ? leadingSpacer.heightAnchor.constraint(equalTo: trailingSpacer.heightAnchor) : leadingSpacer.widthAnchor.constraint(equalTo: trailingSpacer.widthAnchor)
        ])
        panel.contentView = content
        updateModules()
    }

    private func makeModule(_ name: String, theme: BarTheme) -> BarModule? {
        switch name {
        case "workspaces": return WorkspacesModule(theme: theme, hideEmpty: config.bar.hideEmptyWorkspaces, actions: actions)
        case "layout": return LayoutModule(theme: theme)
        case "window": return WindowModule(theme: theme, actions: actions)
        case "agents": return AgentsModule(theme: theme)
        case "network": return MetricModule(kind: .network, theme: theme)
        case "cpu": return MetricModule(kind: .cpu, theme: theme)
        case "battery": return MetricModule(kind: .battery, theme: theme)
        case "clock": return MetricModule(kind: .clock, theme: theme)
        case "settings": return SettingsModule(theme: theme, actions: actions)
        default: return nil
        }
    }

    private func updateModules() {
        for module in modules { module.update(state) }
    }

    private func repositionPanel() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let thickness = CGFloat(config.barThickness)
        let screenFrame = screen.frame
        let frame: NSRect
        switch position {
        case .top: frame = NSRect(x: screenFrame.minX, y: screenFrame.maxY - thickness, width: screenFrame.width, height: thickness)
        case .bottom: frame = NSRect(x: screenFrame.minX, y: screenFrame.minY, width: screenFrame.width, height: thickness)
        case .left: frame = NSRect(x: screenFrame.minX, y: screenFrame.minY, width: thickness, height: screenFrame.height)
        case .right: frame = NSRect(x: screenFrame.maxX - thickness, y: screenFrame.minY, width: thickness, height: screenFrame.height)
        }
        panel.setFrame(frame, display: true)
    }

    private func readInitialState() {
        guard let response = client.send(.status) else { return }
        state.activeWorkspace = Self.value("workspace", from: response) ?? 1
        state.mode = Self.value("mode", from: response) ?? "default"
        state.layout = Self.value("layout", from: response) ?? "bsp"
        if let focused: String = Self.value("focused", from: response), focused != "none" {
            let parts = focused.components(separatedBy: " - ")
            state.focusedApp = parts.first ?? ""
            state.focusedTitle = parts.dropFirst().joined(separator: " - ")
        }
        updateModules()
    }

    @objc private func stateChanged(_ notification: Notification) {
        guard let info = notification.userInfo, let workspace = info["workspace"] as? Int else { return }
        state.activeWorkspace = workspace
        state.mode = info["mode"] as? String ?? "default"
        state.layout = info["layout"] as? String ?? state.layout
        state.focusedApp = info["focusedApp"] as? String ?? ""
        state.focusedTitle = info["focusedTitle"] as? String ?? ""
        if let counts = info["windows"] as? [String: Int] {
            state.windowCounts = counts.reduce(into: [:]) { result, item in
                if let workspace = Int(item.key) { result[workspace] = item.value }
            }
        }
        var needsRebuild = reloadConfigurationIfChanged()
        if let rawPosition = info["position"] as? String, let position = BarPosition(rawValue: rawPosition), position != config.barPosition {
            config.barPosition = position
            needsRebuild = true
        }
        if needsRebuild {
            buildContent()
            repositionPanel()
        }
        updateModules()
    }

    /// Picks up edits to the bar options from the settings window or an editor.
    private func reloadConfigurationIfChanged() -> Bool {
        let modified = Self.configModificationDate()
        guard modified != configModified else { return false }
        configModified = modified
        config = Self.loadConfig()
        return true
    }

    @objc private func screenParametersChanged(_ notification: Notification) {
        repositionPanel()
    }

    @objc private func refreshMetrics() {
        let cpuTicks = SystemMetrics.cpuTicks()
        if let cpuTicks, let previousCPUTicks { state.cpu = SystemMetrics.cpuUsage(current: cpuTicks, previous: previousCPUTicks) }
        previousCPUTicks = cpuTicks

        let network = SystemMetrics.networkBytes()
        if let previousNetworkBytes, let network {
            state.networkDown = SystemMetrics.rate(network.input >= previousNetworkBytes.input ? network.input - previousNetworkBytes.input : 0)
            state.networkUp = SystemMetrics.rate(network.output >= previousNetworkBytes.output ? network.output - previousNetworkBytes.output : 0)
        }
        previousNetworkBytes = network

        let battery = SystemMetrics.batteryStatus()
        state.batteryPercent = Int(battery.prefix { $0.isNumber })
        state.batteryCharging = battery.hasSuffix("+")
        state.clock = SystemMetrics.currentTime()
        state.agents = agentsMonitor.summaries()
        updateModules()
    }

    private func send(_ command: Command) {
        _ = client.send(command)
    }

    private func openSettings() {
        settings.reset()
        settings.show()
    }

    private static func restartDaemon() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["kickstart", "-k", "gui/\(getuid())/com.macwm.daemon"]
        try? process.run()
    }

    private static func loadConfig() -> Config {
        guard let file = ConfigFile.read(), let config = ConfigFile.parse(file.text, isHyprland: file.isHyprland) else { return Config() }
        return config
    }

    private static func configModificationDate() -> Date? {
        guard let path = ConfigFile.read()?.path else { return nil }
        return (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }

    private static func value(_ key: String, from response: String) -> Int? {
        let text: String? = value(key, from: response)
        return text.flatMap(Int.init)
    }

    private static func value(_ key: String, from response: String) -> String? {
        response.split(separator: "\n")
            .first(where: { $0.hasPrefix("\(key): ") })
            .map { String($0.dropFirst(key.count + 2)) }
    }
}

extension BarController: NSWindowDelegate {
    func windowDidChangeScreen(_ notification: Notification) {
        repositionPanel()
    }
}

let application = NSApplication.shared
application.setActivationPolicy(.accessory)
let controller = BarController()
withExtendedLifetime(controller) {
    application.run()
}

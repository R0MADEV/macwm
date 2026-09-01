import AppKit
import Darwin
import Foundation
import IOKit.ps
import MacWMCore
import MacWMTransport

private let stateNotification = Notification.Name("com.macwm.stateChanged")

@MainActor
final class BarController: NSObject {
    private let client = UnixSocketClient(path: "/tmp/macwm.sock")
    private var position: BarPosition
    private let panel: NSPanel
    private let workspaceStack = NSStackView()
    private let workspaceLabel = NSTextField(labelWithString: "Workspace 1")
    private let statusStack = NSStackView()
    private var statusLabels: [NSTextField] = []
    private var metricsTimer: Timer?
    private var previousCPUTicks: [UInt32]?
    private var previousNetworkBytes: (input: UInt64, output: UInt64)?
    private var activeWorkspace = 1
    private let settings = SettingsWindowController()
    private var mode = "default"
    private var workspaceWindowCounts: [Int: Int] = [:]

    override init() {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.position = Self.loadConfig().barPosition
        self.panel = panel
        super.init()

        configurePanel()
        configureContent()
        readInitialState()
        refreshMetrics()
        metricsTimer = Timer.scheduledTimer(
            timeInterval: 2,
            target: self,
            selector: #selector(refreshMetrics),
            userInfo: nil,
            repeats: true
        )
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(stateChanged(_:)),
            name: stateNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged(_:)),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        repositionPanel()
        panel.orderFrontRegardless()
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
        NotificationCenter.default.removeObserver(self)
    }

    private func configurePanel() {
        panel.isFloatingPanel = true
        panel.level = .mainMenu
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = NSColor.black
        panel.hasShadow = false
        panel.delegate = self
    }

    /// Builds the bar for the current position; safe to call again when it changes.
    private func configureContent() {
        for view in workspaceStack.arrangedSubviews + statusStack.arrangedSubviews {
            view.removeFromSuperview()
        }
        NSLayoutConstraint.deactivate(workspaceStack.constraints.filter { $0.firstItem === workspaceStack && $0.secondItem == nil })
        statusLabels.removeAll()
        let root = NSStackView()
        let isVertical = position.isVertical
        let orientation: NSUserInterfaceLayoutOrientation = isVertical ? .vertical : .horizontal
        root.orientation = orientation
        root.alignment = isVertical ? .centerX : .centerY
        root.distribution = .fill
        root.spacing = 8
        root.edgeInsets = NSEdgeInsets(top: 3, left: 10, bottom: 3, right: 10)
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.black.cgColor
        root.layer?.borderColor = NSColor.clear.cgColor
        root.layer?.borderWidth = 0

        workspaceStack.orientation = orientation
        workspaceStack.alignment = isVertical ? .centerX : .centerY
        workspaceStack.spacing = 2
        let workspaceAxis: NSLayoutConstraint.Orientation = isVertical ? .vertical : .horizontal
        workspaceStack.setContentHuggingPriority(.required, for: workspaceAxis)
        workspaceStack.setContentCompressionResistancePriority(.required, for: workspaceAxis)
        if isVertical {
            workspaceStack.heightAnchor.constraint(equalToConstant: 241).isActive = true
        } else {
            workspaceStack.widthAnchor.constraint(equalToConstant: 214).isActive = true
        }
        for workspace in 1...9 {
            let button = NSButton(title: "\(workspace)", target: self, action: #selector(selectWorkspace(_:)))
            button.tag = workspace
            button.bezelStyle = .regularSquare
            button.setButtonType(.toggle)
            button.isBordered = false
            button.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
            button.contentTintColor = NSColor(calibratedWhite: 0.72, alpha: 1)
            button.wantsLayer = true
            button.layer?.cornerRadius = 3
            button.translatesAutoresizingMaskIntoConstraints = false
            if isVertical {
                button.widthAnchor.constraint(equalToConstant: 25).isActive = true
                button.heightAnchor.constraint(equalToConstant: 22).isActive = true
            } else {
                button.widthAnchor.constraint(equalToConstant: 22).isActive = true
                button.heightAnchor.constraint(equalToConstant: 25).isActive = true
            }
            workspaceStack.addArrangedSubview(button)
        }

        let leftSpacer = NSView()
        let rightSpacer = NSView()
        statusStack.orientation = orientation
        statusStack.alignment = isVertical ? .centerX : .centerY
        statusStack.spacing = 8
        for symbolName in MacWMBarIcons.metricSymbols {
            let metricStack = NSStackView()
            metricStack.orientation = orientation
            metricStack.alignment = isVertical ? .centerX : .centerY
            metricStack.spacing = 3

            let imageView = NSImageView()
            imageView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
            imageView.contentTintColor = NSColor(calibratedWhite: 0.62, alpha: 1)
            imageView.imageScaling = .scaleProportionallyUpOrDown
            imageView.widthAnchor.constraint(equalToConstant: 12).isActive = true
            imageView.heightAnchor.constraint(equalToConstant: 12).isActive = true

            let label = NSTextField(labelWithString: "--")
            label.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
            label.textColor = NSColor(calibratedWhite: 0.62, alpha: 1)
            metricStack.addArrangedSubview(imageView)
            metricStack.addArrangedSubview(label)
            statusStack.addArrangedSubview(metricStack)
            statusLabels.append(label)
        }
        let clockStack = NSStackView()
        clockStack.orientation = orientation
        clockStack.alignment = isVertical ? .centerX : .centerY
        clockStack.spacing = 3
        let clockImageView = NSImageView()
        clockImageView.image = NSImage(
            systemSymbolName: MacWMBarIcons.clock,
            accessibilityDescription: nil
        )
        clockImageView.contentTintColor = NSColor(calibratedWhite: 0.62, alpha: 1)
        clockImageView.imageScaling = .scaleProportionallyUpOrDown
        clockImageView.widthAnchor.constraint(equalToConstant: 12).isActive = true
        clockImageView.heightAnchor.constraint(equalToConstant: 12).isActive = true
        let clockLabel = NSTextField(labelWithString: "--:--")
        clockLabel.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        clockLabel.textColor = NSColor(calibratedWhite: 0.62, alpha: 1)
        clockStack.addArrangedSubview(clockImageView)
        clockStack.addArrangedSubview(clockLabel)
        statusStack.addArrangedSubview(clockStack)
        statusLabels.append(clockLabel)

        let settingsButton = NSButton(image: NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Settings") ?? NSImage(), target: self, action: #selector(openSettings))
        settingsButton.isBordered = false
        settingsButton.contentTintColor = NSColor(calibratedWhite: 0.62, alpha: 1)
        settingsButton.toolTip = "macwm settings"
        settingsButton.widthAnchor.constraint(equalToConstant: 16).isActive = true
        settingsButton.heightAnchor.constraint(equalToConstant: 16).isActive = true
        statusStack.addArrangedSubview(settingsButton)
        statusStack.setContentHuggingPriority(.required, for: workspaceAxis)
        statusStack.setContentCompressionResistancePriority(.required, for: workspaceAxis)
        leftSpacer.setContentHuggingPriority(.defaultLow, for: workspaceAxis)
        rightSpacer.setContentHuggingPriority(.defaultLow, for: workspaceAxis)

        workspaceLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        workspaceLabel.textColor = NSColor(calibratedWhite: 0.58, alpha: 1)
        root.addArrangedSubview(workspaceStack)
        root.addArrangedSubview(leftSpacer)
        root.addArrangedSubview(workspaceLabel)
        root.addArrangedSubview(rightSpacer)
        root.addArrangedSubview(statusStack)
        panel.contentView = root
    }

    private func readInitialState() {
        guard let response = client.send(.status) else {
            updateContent()
            return
        }
        activeWorkspace = Self.value("workspace", from: response) ?? 1
        mode = Self.value("mode", from: response) ?? "default"
        updateContent()
    }

    @objc private func openSettings() {
        MainActor.assumeIsolated {
            settings.reset()
            settings.show()
        }
    }

    @objc private func selectWorkspace(_ sender: NSButton) {
        guard let command = Command.parse(["workspace", String(sender.tag)]) else { return }
        _ = client.send(command)
        guard let response = client.send(.status), let workspace: Int = Self.value("workspace", from: response) else { return }
        activeWorkspace = workspace
        updateContent()
    }

    @objc private func stateChanged(_ notification: Notification) {
        guard let workspace = notification.userInfo?["workspace"] as? Int else { return }
        activeWorkspace = workspace
        mode = notification.userInfo?["mode"] as? String ?? "default"
        if let rawPosition = notification.userInfo?["position"] as? String, let position = BarPosition(rawValue: rawPosition), position != self.position {
            self.position = position
            configureContent()
            repositionPanel()
        }
        if let counts = notification.userInfo?["windows"] as? [String: Int] {
            workspaceWindowCounts = counts.reduce(into: [:]) { result, item in
                if let workspace = Int(item.key) { result[workspace] = item.value }
            }
        }
        updateContent()
    }

    @objc private func screenParametersChanged(_ notification: Notification) {
        repositionPanel()
    }

    @objc private func refreshMetrics() {
        let cpuTicks = Self.cpuTicks()
        let cpu = if let cpuTicks, let previousCPUTicks {
            Self.cpuUsage(current: cpuTicks, previous: previousCPUTicks)
        } else {
            "--"
        }
        previousCPUTicks = cpuTicks

        let network = Self.networkBytes()
        let networkRate: String
        if let previousNetworkBytes, let network {
            let input = network.input >= previousNetworkBytes.input
                ? network.input - previousNetworkBytes.input
                : 0
            let output = network.output >= previousNetworkBytes.output
                ? network.output - previousNetworkBytes.output
                : 0
            networkRate = "↓\(Self.rate(input)) ↑\(Self.rate(output))"
        } else {
            networkRate = "--"
        }
        previousNetworkBytes = network

        let values = [
            cpu,
            networkRate,
            Self.batteryStatus(),
            Self.currentTime()
        ]
        for (label, value) in zip(statusLabels, values) {
            label.stringValue = value
        }
    }

    private func updateContent() {
        let isInMode = mode != "default"
        workspaceLabel.stringValue = isInMode ? "WS \(activeWorkspace) · \(mode.uppercased())" : "WS \(activeWorkspace)"
        for case let button as NSButton in workspaceStack.arrangedSubviews {
            let isActive = button.tag == activeWorkspace
            let count = workspaceWindowCounts[button.tag] ?? 0
            button.title = count == 0 ? "\(button.tag)" : "\(button.tag) (\(count))"
            button.state = isActive ? .on : .off
            button.contentTintColor = isActive
                ? NSColor(calibratedWhite: 0.98, alpha: 1)
                : NSColor(calibratedWhite: 0.68, alpha: 1)
            button.layer?.backgroundColor = isActive
                ? NSColor(calibratedRed: 0.18, green: 0.34, blue: 0.56, alpha: 0.9).cgColor
                : NSColor.clear.cgColor
        }
    }

    private func repositionPanel() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let thickness = CGFloat(position.thickness)
        let screenFrame = screen.frame
        let frame: NSRect
        switch position {
        case .top:
            frame = NSRect(x: screenFrame.minX, y: screenFrame.maxY - thickness, width: screenFrame.width, height: thickness)
        case .bottom:
            frame = NSRect(x: screenFrame.minX, y: screenFrame.minY, width: screenFrame.width, height: thickness)
        case .left:
            frame = NSRect(x: screenFrame.minX, y: screenFrame.minY, width: thickness, height: screenFrame.height)
        case .right:
            frame = NSRect(x: screenFrame.maxX - thickness, y: screenFrame.minY, width: thickness, height: screenFrame.height)
        }
        panel.setFrame(
            frame,
            display: true
        )
    }

    private static func loadConfig() -> Config {
        guard let file = ConfigFile.read(), let config = ConfigFile.parse(file.text, isHyprland: file.isHyprland) else {
            return Config()
        }
        return config
    }

    private static func value(_ key: String, from response: String) -> Int? {
        response.split(separator: "\n")
            .first(where: { $0.hasPrefix("\(key): ") })
            .flatMap { Int($0.dropFirst(key.count + 2)) }
    }

    private static func value(_ key: String, from response: String) -> String? {
        response.split(separator: "\n")
            .first(where: { $0.hasPrefix("\(key): ") })
            .map { String($0.dropFirst(key.count + 2)) }
    }

    private static func currentTime() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: Date())
    }

    private static func cpuTicks() -> [UInt32]? {
        var load = host_cpu_load_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &load) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        return withUnsafePointer(to: &load.cpu_ticks) { pointer in
            pointer.withMemoryRebound(to: UInt32.self, capacity: 4) {
                Array(UnsafeBufferPointer(start: $0, count: 4))
            }
        }
    }

    private static func cpuUsage(current: [UInt32], previous: [UInt32]) -> String {
        guard current.count == previous.count, current.count > Int(CPU_STATE_IDLE) else { return "--" }
        let ticks = zip(current, previous).map { UInt64($0) >= UInt64($1) ? UInt64($0) - UInt64($1) : 0 }
        let total = ticks.reduce(UInt64(0)) { $0 + UInt64($1) }
        guard total > 0 else { return "--" }
        let idle = ticks[Int(CPU_STATE_IDLE)]
        return "\(Int((100 * (total - idle)) / total))%"
    }

    private static func networkBytes() -> (input: UInt64, output: UInt64)? {
        var address: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&address) == 0 else { return nil }
        defer { freeifaddrs(address) }

        var input: UInt64 = 0
        var output: UInt64 = 0
        var current = address
        while let interface = current?.pointee {
            if interface.ifa_addr?.pointee.sa_family == UInt8(AF_LINK),
               let data = interface.ifa_data?.assumingMemoryBound(to: if_data.self).pointee {
                let name = String(cString: interface.ifa_name)
                if name != "lo0" {
                    input += UInt64(data.ifi_ibytes)
                    output += UInt64(data.ifi_obytes)
                }
            }
            current = interface.ifa_next
        }
        return input == 0 && output == 0 ? nil : (input, output)
    }

    private static func rate(_ bytes: UInt64) -> String {
        let kilobytes = Double(bytes) / 1024
        if kilobytes < 1024 { return "\(Int(kilobytes))K/s" }
        return String(format: "%.1fM/s", kilobytes / 1024)
    }

    private static func batteryStatus() -> String {
        let blob = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(blob).takeRetainedValue()
        let count = CFArrayGetCount(sources)
        guard count > 0 else { return "--" }
        for index in 0..<count {
            guard let source = CFArrayGetValueAtIndex(sources, index) else { continue }
            let powerSource = Unmanaged<CFTypeRef>.fromOpaque(source).takeUnretainedValue()
            guard let description = IOPSGetPowerSourceDescription(blob, powerSource)?.takeUnretainedValue()
                    as? [String: Any],
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = description[kIOPSMaxCapacityKey] as? Int,
                  maximum > 0 else { continue }
            let fraction = Double(current) / Double(maximum)
            let percentage = Int((fraction * 100).rounded())
            let charging = (description[kIOPSIsChargingKey] as? Bool) == true
            return "\(percentage)%\(charging ? "+" : "")"
        }
        return "--"
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

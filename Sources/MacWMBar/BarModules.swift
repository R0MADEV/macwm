import AppKit
import MacWMCore

/// Everything a module may show, refreshed from the daemon and the system.
struct BarState {
    var activeWorkspace = 1
    var windowCounts: [Int: Int] = [:]
    var layout = "bsp"
    var mode = "default"
    var focusedApp = ""
    var focusedTitle = ""
    var cpu = "--"
    var networkDown = "--"
    var networkUp = "--"
    var batteryPercent: Int?
    var batteryCharging = false
    var clock = "--:--"
    var agents: [AgentsMonitor.Summary] = []
}

/// Colors and metrics shared by every module, derived from the configuration.
struct BarTheme {
    let accent: NSColor
    let fontSize: CGFloat
    let isVertical: Bool
    let primary = NSColor(calibratedWhite: 0.92, alpha: 1)
    let secondary = NSColor(calibratedWhite: 0.62, alpha: 1)
    let pill = NSColor(calibratedWhite: 1, alpha: 0.08)
    let warning = NSColor(calibratedRed: 0.95, green: 0.75, blue: 0.3, alpha: 1)
    let danger = NSColor(calibratedRed: 0.95, green: 0.4, blue: 0.35, alpha: 1)

    init(options: BarOptions, isVertical: Bool) {
        let rgba = BorderOptions.rgba(options.accent) ?? (0.37, 0.51, 0.67, 1)
        accent = NSColor(red: rgba.red, green: rgba.green, blue: rgba.blue, alpha: rgba.alpha)
        fontSize = CGFloat(options.fontSize)
        self.isVertical = isVertical
    }

    var font: NSFont { .monospacedSystemFont(ofSize: fontSize, weight: .regular) }
    var boldFont: NSFont { .monospacedSystemFont(ofSize: fontSize, weight: .semibold) }
}

/// Actions modules can ask of the controller, which talks to the daemon.
struct BarActions {
    let switchWorkspace: (Int) -> Void
    let cycleFocus: () -> Void
    let openSettings: () -> Void
    let reloadConfiguration: () -> Void
    let restartDaemon: () -> Void
}

@MainActor
protocol BarModule: AnyObject {
    var view: NSView { get }
    func update(_ state: BarState)
}

/// A rounded capsule with a label, the building block of the bar.
final class PillView: NSView {
    let label = NSTextField(labelWithString: "")
    var onClick: (() -> Void)?

    init(theme: BarTheme, text: String = "") {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.backgroundColor = theme.pill.cgColor
        label.font = theme.font
        label.textColor = theme.primary
        label.stringValue = text
        label.lineBreakMode = .byTruncatingTail
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 7),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -7),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: max(18, theme.fontSize + 9))
        ])
    }

    required init?(coder: NSCoder) { nil }

    override func mouseDown(with event: NSEvent) { onClick?() }

    func setFill(_ color: NSColor) { layer?.backgroundColor = color.cgColor }
}

// MARK: - Modules

@MainActor
final class WorkspacesModule: BarModule {
    let view: NSView
    private let stack = NSStackView()
    private var pills: [Int: PillView] = [:]
    private let theme: BarTheme
    private let hideEmpty: Bool

    init(theme: BarTheme, hideEmpty: Bool, actions: BarActions) {
        self.theme = theme
        self.hideEmpty = hideEmpty
        stack.orientation = theme.isVertical ? .vertical : .horizontal
        stack.spacing = 3
        for workspace in 1...9 {
            let pill = PillView(theme: theme, text: "\(workspace)")
            pill.onClick = { actions.switchWorkspace(workspace) }
            pill.widthAnchor.constraint(greaterThanOrEqualToConstant: max(24, theme.fontSize * 2.2)).isActive = true
            pills[workspace] = pill
            stack.addArrangedSubview(pill)
        }
        view = stack
    }

    func update(_ state: BarState) {
        for (workspace, pill) in pills {
            let isActive = workspace == state.activeWorkspace
            let count = state.windowCounts[workspace] ?? 0
            pill.isHidden = hideEmpty && count == 0 && !isActive
            pill.setFill(isActive ? theme.accent : (count > 0 ? theme.pill : .clear))
            pill.label.textColor = isActive ? .white : (count > 0 ? theme.primary : theme.secondary)
            pill.label.font = isActive ? theme.boldFont : theme.font
            pill.label.stringValue = count > 0 && !isActive ? "\(workspace)·" : "\(workspace)"
            pill.toolTip = count == 1 ? "1 window" : "\(count) windows"
        }
    }
}

@MainActor
final class LayoutModule: BarModule {
    let view: NSView
    private let pill: PillView
    private let theme: BarTheme

    init(theme: BarTheme) {
        self.theme = theme
        pill = PillView(theme: theme, text: "bsp")
        pill.label.textColor = theme.secondary
        view = pill
    }

    func update(_ state: BarState) {
        let inMode = state.mode != "default"
        pill.label.stringValue = inMode ? state.mode.uppercased() : state.layout
        pill.setFill(inMode ? theme.accent : theme.pill)
        pill.label.textColor = inMode ? .white : theme.secondary
        pill.label.font = inMode ? theme.boldFont : theme.font
    }
}

@MainActor
final class WindowModule: BarModule {
    let view: NSView
    private let label = NSTextField(labelWithString: "")
    private let theme: BarTheme

    init(theme: BarTheme, actions: BarActions) {
        self.theme = theme
        let pill = PillView(theme: theme)
        pill.setFill(.clear)
        pill.onClick = { actions.cycleFocus() }
        pill.label.textColor = theme.primary
        pill.label.maximumNumberOfLines = theme.isVertical ? 3 : 1
        pill.widthAnchor.constraint(lessThanOrEqualToConstant: theme.isVertical ? 44 : 520).isActive = true
        view = pill
        label.isHidden = true
    }

    func update(_ state: BarState) {
        guard let pill = view as? PillView else { return }
        let title = state.focusedTitle.isEmpty ? state.focusedApp : (state.focusedApp.isEmpty ? state.focusedTitle : "\(state.focusedApp) · \(state.focusedTitle)")
        pill.label.stringValue = theme.isVertical ? state.focusedApp : title
        pill.toolTip = title.isEmpty ? nil : "\(title)\nClick to focus the next window"
        pill.isHidden = title.isEmpty
    }
}

@MainActor
final class AgentsModule: BarModule {
    let view: NSView
    private let stack = NSStackView()
    private let theme: BarTheme
    private var pills: [String: PillView] = [:]
    private var popover: NSPopover?

    init(theme: BarTheme) {
        self.theme = theme
        stack.orientation = theme.isVertical ? .vertical : .horizontal
        stack.spacing = 4
        view = stack
    }

    func update(_ state: BarState) {
        let names = Set(state.agents.map(\.agent))
        for (name, pill) in pills where !names.contains(name) {
            stack.removeArrangedSubview(pill)
            pill.removeFromSuperview()
            pills.removeValue(forKey: name)
        }
        for summary in state.agents {
            let pill = pills[summary.agent] ?? makePill(for: summary)
            let plan = summary.line.components(separatedBy: "plan ").dropFirst().first.flatMap { Int($0.prefix { $0.isNumber }) }
            pill.label.stringValue = (summary.isWorking ? "● " : "○ ") + (theme.isVertical ? summary.agent : summary.line)
            let tint: NSColor = plan.map { $0 >= 90 ? theme.danger : ($0 >= 70 ? theme.warning : theme.primary) } ?? theme.primary
            pill.label.textColor = tint
            pill.setFill(plan.map { $0 >= 90 ? theme.danger.withAlphaComponent(0.25) : ($0 >= 70 ? theme.warning.withAlphaComponent(0.2) : theme.pill) } ?? theme.pill)
            pill.toolTip = summary.details
            pill.onClick = { [weak self, weak pill] in
                guard let self, let pill else { return }
                self.showDetails(summary.details, title: summary.line, relativeTo: pill)
            }
        }
        view.isHidden = state.agents.isEmpty
    }

    private func makePill(for summary: AgentsMonitor.Summary) -> PillView {
        let pill = PillView(theme: theme, text: summary.line)
        pills[summary.agent] = pill
        stack.addArrangedSubview(pill)
        return pill
    }

    private func showDetails(_ details: String, title: String, relativeTo anchor: NSView) {
        popover?.close()
        let popover = NSPopover()
        popover.behavior = .transient
        let controller = NSViewController()
        let text = NSTextField(wrappingLabelWithString: "\(title)\n\n\(details)")
        text.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        text.preferredMaxLayoutWidth = 420
        text.frame = NSRect(x: 12, y: 12, width: 420, height: text.intrinsicContentSize.height)
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 444, height: text.frame.height + 24))
        container.addSubview(text)
        controller.view = container
        popover.contentViewController = controller
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: theme.isVertical ? .maxX : .minY)
        self.popover = popover
    }
}

/// Icon plus value, for network, CPU, battery and the clock.
@MainActor
final class MetricModule: BarModule {
    enum Kind { case network, cpu, battery, clock }

    let view: NSView
    private let kind: Kind
    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "--")
    private let theme: BarTheme

    init(kind: Kind, theme: BarTheme) {
        self.kind = kind
        self.theme = theme
        let stack = NSStackView()
        stack.orientation = theme.isVertical ? .vertical : .horizontal
        stack.spacing = 3
        stack.alignment = theme.isVertical ? .centerX : .centerY
        icon.contentTintColor = theme.secondary
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.widthAnchor.constraint(equalToConstant: theme.fontSize + 2).isActive = true
        icon.heightAnchor.constraint(equalToConstant: theme.fontSize + 2).isActive = true
        label.font = theme.font
        label.textColor = theme.secondary
        label.alignment = .center
        label.maximumNumberOfLines = theme.isVertical ? 2 : 1
        stack.addArrangedSubview(icon)
        stack.addArrangedSubview(label)
        view = stack
    }

    func update(_ state: BarState) {
        switch kind {
        case .network:
            icon.image = NSImage(systemSymbolName: "wifi", accessibilityDescription: nil)
            label.stringValue = theme.isVertical ? "↓\(state.networkDown)\n↑\(state.networkUp)" : "↓\(state.networkDown) ↑\(state.networkUp)"
        case .cpu:
            icon.image = NSImage(systemSymbolName: "cpu", accessibilityDescription: nil)
            label.stringValue = state.cpu
        case .battery:
            let percent = state.batteryPercent ?? 0
            let level = percent > 87 ? 100 : percent > 62 ? 75 : percent > 37 ? 50 : percent > 12 ? 25 : 0
            icon.image = NSImage(systemSymbolName: state.batteryCharging ? "battery.100.bolt" : "battery.\(level)", accessibilityDescription: nil)
            icon.contentTintColor = percent <= 15 && !state.batteryCharging ? theme.danger : theme.secondary
            label.stringValue = state.batteryPercent.map { "\($0)%" } ?? "--"
        case .clock:
            icon.image = NSImage(systemSymbolName: "clock", accessibilityDescription: nil)
            label.stringValue = state.clock
        }
    }
}

@MainActor
final class SettingsModule: BarModule {
    let view: NSView
    private let actions: BarActions

    init(theme: BarTheme, actions: BarActions) {
        self.actions = actions
        let button = MenuButton()
        button.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Settings")
        button.isBordered = false
        button.contentTintColor = theme.secondary
        button.toolTip = "macwm settings. Right click for more."
        button.widthAnchor.constraint(equalToConstant: theme.fontSize + 6).isActive = true
        button.heightAnchor.constraint(equalToConstant: theme.fontSize + 6).isActive = true
        button.onLeftClick = { actions.openSettings() }
        button.onRightClick = { [actions] in
            let menu = NSMenu()
            menu.addItem(withTitle: "Settings…", action: nil, keyEquivalent: "").representedObject = "settings"
            menu.addItem(withTitle: "Reload configuration", action: nil, keyEquivalent: "").representedObject = "reload"
            menu.addItem(withTitle: "Restart daemon", action: nil, keyEquivalent: "").representedObject = "restart"
            for item in menu.items {
                item.target = button
                item.action = #selector(MenuButton.menuItemSelected(_:))
            }
            button.menuHandler = { choice in
                switch choice {
                case "settings": actions.openSettings()
                case "reload": actions.reloadConfiguration()
                case "restart": actions.restartDaemon()
                default: break
                }
            }
            return menu
        }
        view = button
    }

    func update(_ state: BarState) {}
}

final class MenuButton: NSButton {
    var onLeftClick: (() -> Void)?
    var onRightClick: (() -> NSMenu)?
    var menuHandler: ((String) -> Void)?

    override func mouseDown(with event: NSEvent) { onLeftClick?() }

    override func rightMouseDown(with event: NSEvent) {
        guard let menu = onRightClick?() else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc func menuItemSelected(_ sender: NSMenuItem) {
        guard let choice = sender.representedObject as? String else { return }
        menuHandler?(choice)
    }
}

/// The bar's content: a blurred backdrop, a tinted overlay and the module
/// stacks; scrolling anywhere on it switches workspaces.
final class BarContentView: NSVisualEffectView {
    var onScroll: ((Int) -> Void)?
    private var accumulated: CGFloat = 0

    override func scrollWheel(with event: NSEvent) {
        accumulated += event.scrollingDeltaY != 0 ? event.scrollingDeltaY : event.scrollingDeltaX
        guard abs(accumulated) >= 12 else { return }
        onScroll?(accumulated > 0 ? -1 : 1)
        accumulated = 0
    }
}

import Foundation

public struct Config: Equatable, Sendable {
    public var outerGap: Double
    public var innerGap: Double
    public var layout: LayoutKind
    public var barPosition: BarPosition
    public var terminalBundleIdentifier: String
    public var autoTile: Bool
    public var rules: [WindowRule]
    public var hotkeys: [String: String]
    /// Mode name to binding text to command text, from `[binds]` and `[binds.<mode>]`.
    public var binds: [String: [String: String]]

    public init(layout: LayoutKind = .bsp, outerGap: Double = 8, innerGap: Double = 8, autoTile: Bool = true, barPosition: BarPosition = .top, terminalBundleIdentifier: String = "com.googlecode.iterm2", rules: [WindowRule] = [], hotkeys: [String: String] = Config.defaultHotkeys, binds: [String: [String: String]] = [:]) {
        self.layout = layout
        self.barPosition = barPosition
        self.terminalBundleIdentifier = terminalBundleIdentifier
        self.outerGap = outerGap
        self.innerGap = innerGap
        self.autoTile = autoTile
        self.rules = rules
        self.hotkeys = hotkeys
        self.binds = binds
    }

    public static let defaultHotkeys: [String: String] = [
        "focus_left": "alt+h", "focus_down": "alt+j", "focus_up": "alt+k", "focus_right": "alt+l",
        "move_left": "alt+shift+h", "move_down": "alt+shift+j", "move_up": "alt+shift+k", "move_right": "alt+shift+l",
        "resize": "alt+r", "maximize": "alt+m", "toggle_float": "alt+f", "terminal_toggle": "grave", "workspace_1": "alt+1", "workspace_2": "alt+2", "workspace_3": "alt+3",
        "workspace_4": "alt+4", "workspace_5": "alt+5", "workspace_6": "alt+6", "workspace_7": "alt+7",
        "workspace_8": "alt+8", "workspace_9": "alt+9"
    ]

    public static func parse(_ text: String) -> Config? {
        var config = Config()
        var section = ""
        var currentRuleIndex: Int?

        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }

            if line.hasPrefix("[") {
                if line == "[[rules]]" {
                    section = "rules"
                    config.rules.append(WindowRule(bundleIdentifier: "", float: false))
                    currentRuleIndex = config.rules.index(before: config.rules.endIndex)
                    continue
                }
                guard line.hasSuffix("]") else { return nil }
                section = String(line.dropFirst().dropLast())
                currentRuleIndex = nil
                continue
            }

            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return nil }
            let key = parts[0].trimmingCharacters(in: .whitespaces)
            let value = parts[1].trimmingCharacters(in: .whitespaces)

            if section == "keys", key.hasPrefix("workspace_") {
                guard let workspace = Int(key.dropFirst("workspace_".count)), (1...9).contains(workspace), !value.isEmpty else { return nil }
                config.hotkeys[key] = unquoted(value)
                continue
            }

            let isBindsSection = section == "binds" || section.hasPrefix("binds.")
            if isBindsSection {
                let mode = section == "binds" ? KeybindEngine.defaultMode : String(section.dropFirst("binds.".count))
                let bindingText = unquoted(key)
                let commandText = unquoted(value)
                guard !mode.isEmpty, KeyBinding.parse(bindingText) != nil, Command.parse(commandText) != nil else { return nil }
                config.binds[mode, default: [:]][bindingText] = commandText
                continue
            }

            if section == "rules", let currentRuleIndex {
                guard currentRuleIndex < config.rules.count else { return nil }
                let rule = config.rules[currentRuleIndex]
                switch key {
                case "bundle_id":
                    let bundleIdentifier = unquoted(value)
                    guard !bundleIdentifier.isEmpty else { return nil }
                    config.rules[currentRuleIndex] = WindowRule(bundleIdentifier: bundleIdentifier, title: rule.title, subrole: rule.subrole, float: rule.float, workspace: rule.workspace, center: rule.center, width: rule.width, height: rule.height)
                case "title", "subrole":
                    let matcher = unquoted(value)
                    guard !matcher.isEmpty else { return nil }
                    config.rules[currentRuleIndex] = WindowRule(bundleIdentifier: rule.bundleIdentifier, title: key == "title" ? matcher : rule.title, subrole: key == "subrole" ? matcher : rule.subrole, float: rule.float, workspace: rule.workspace, center: rule.center, width: rule.width, height: rule.height)
                case "float":
                    guard let float = Bool(value) else { return nil }
                    config.rules[currentRuleIndex] = WindowRule(bundleIdentifier: rule.bundleIdentifier, title: rule.title, subrole: rule.subrole, float: float, workspace: rule.workspace, center: rule.center, width: rule.width, height: rule.height)
                case "workspace":
                    guard let workspace = Int(value), workspace > 0 else { return nil }
                    config.rules[currentRuleIndex] = WindowRule(bundleIdentifier: rule.bundleIdentifier, title: rule.title, subrole: rule.subrole, float: rule.float, workspace: workspace, center: rule.center, width: rule.width, height: rule.height)
                case "center":
                    guard let center = Bool(value) else { return nil }
                    config.rules[currentRuleIndex] = WindowRule(bundleIdentifier: rule.bundleIdentifier, title: rule.title, subrole: rule.subrole, float: rule.float, workspace: rule.workspace, center: center, width: rule.width, height: rule.height)
                case "width", "height":
                    guard let dimension = nonNegativeDouble(value) else { return nil }
                    config.rules[currentRuleIndex] = WindowRule(bundleIdentifier: rule.bundleIdentifier, title: rule.title, subrole: rule.subrole, float: rule.float, workspace: rule.workspace, center: rule.center, width: key == "width" ? dimension : rule.width, height: key == "height" ? dimension : rule.height)
                default:
                    return nil
                }
                continue
            }

            switch "\(section).\(key)" {
            case "general.layout":
                let layoutValue = unquoted(value) == "master" ? "master-stack" : unquoted(value)
                guard let layout = LayoutKind(rawValue: layoutValue) else { return nil }
                config.layout = layout
            case "bar.position":
                guard let position = BarPosition(rawValue: unquoted(value)) else { return nil }
                config.barPosition = position
            case "terminal.bundle_id":
                let bundleIdentifier = unquoted(value)
                let validBundleIdentifier = !bundleIdentifier.isEmpty && !bundleIdentifier.contains(where: { $0.isWhitespace })
                guard validBundleIdentifier else { return nil }
                config.terminalBundleIdentifier = bundleIdentifier
            case "general.gap":
                guard let gap = nonNegativeDouble(value) else { return nil }
                config.outerGap = gap
                config.innerGap = gap
            case "general.auto_tile":
                guard let autoTile = Bool(value) else { return nil }
                config.autoTile = autoTile
            case "general.focus_follows_mouse":
                guard Bool(value) != nil else { return nil }
            case "keys.focus_left", "keys.focus_down", "keys.focus_up", "keys.focus_right",
                 "keys.move_left", "keys.move_down", "keys.move_up", "keys.move_right",
                 "keys.toggle_float", "keys.maximize", "keys.resize", "keys.terminal_toggle":
                guard !value.isEmpty else { return nil }
                config.hotkeys[key] = unquoted(value)
            case "workspaces.count":
                guard let count = Int(value), count > 0 else { return nil }
            case "display.outer_gap":
                guard let gap = nonNegativeDouble(value) else { return nil }
                config.outerGap = gap
            case "display.inner_gap":
                guard let gap = nonNegativeDouble(value) else { return nil }
                config.innerGap = gap
            default:
                return nil
            }
        }

        guard config.rules.allSatisfy({ !$0.bundleIdentifier.isEmpty }) else { return nil }
        return config
    }
}

private func unquoted(_ value: String) -> String {
    guard value.count >= 2, value.first == "\"", value.last == "\"" else { return value }
    return String(value.dropFirst().dropLast())
}

private func nonNegativeDouble(_ value: String) -> Double? {
    guard let number = Double(value), number >= 0, number.isFinite else { return nil }
    return number
}

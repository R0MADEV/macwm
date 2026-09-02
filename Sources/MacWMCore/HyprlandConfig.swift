import Foundation

/// Reads a Hyprland-style configuration and translates it into `Config`, so
/// dotfiles written for Hyprland work with minimal edits. Sections and keys
/// that have no macOS equivalent, such as `decoration`, are ignored;
/// dispatchers macwm cannot provide are skipped; malformed values reject the
/// whole file, like the TOML parser does.
public enum HyprlandConfig {
    public static func parse(_ text: String) -> Config? {
        var config = Config()
        var variables: [String: String] = [:]
        var sections: [String] = []
        var submap = KeybindEngine.defaultMode
        var autostartCount = 0

        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = stripComment(String(rawLine)).trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            if line.hasSuffix("{") {
                sections.append(line.dropLast().trimmingCharacters(in: .whitespaces))
                continue
            }
            if line == "}" {
                _ = sections.popLast()
                continue
            }
            guard let separator = line.firstIndex(of: "=") else { return nil }
            let key = line[..<separator].trimmingCharacters(in: .whitespaces)
            let value = substitute(line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces), variables: variables)
            if key.hasPrefix("$") {
                variables[key] = value
                continue
            }

            switch (sections.last ?? "", key) {
            case ("", "bind"), ("", "binde"), ("", "bindl"), ("", "bindr"), ("", "bindel"):
                guard let bind = translateBind(value) else { return nil }
                guard let (binding, command) = bind else { continue }
                config.binds[submap, default: [:]][binding] = command
            case ("", "bindm"):
                continue
            case ("", "submap"):
                submap = value == "reset" ? KeybindEngine.defaultMode : value
            case ("", "exec-once"), ("", "exec"):
                guard !value.isEmpty else { return nil }
                autostartCount += 1
                config.autostart[String(format: "%02d", autostartCount)] = value
            case ("", "windowrule"), ("", "windowrulev2"):
                guard let rule = translateRule(value) else { return nil }
                merge(rule, into: &config.rules)
            case ("", "scratchpad"):
                let parts = fields(value)
                guard parts.count == 2, !parts[0].isEmpty, isValidBundleIdentifier(parts[1]) else { return nil }
                config.scratchpads[parts[0]] = parts[1]
            case ("general", "gaps_in"):
                guard let gap = Double(value), gap >= 0 else { return nil }
                config.innerGap = gap
            case ("general", "gaps_out"):
                guard let gap = Double(value), gap >= 0 else { return nil }
                config.outerGap = gap
            case ("general", "layout"):
                guard let layout = translateLayout(value) else { return nil }
                config.layout = layout
            case ("general", "border_size"):
                guard let width = Double(value), width >= 0 else { return nil }
                config.border.width = width
                config.border.enabled = width > 0
            case ("general", "col.active_border"):
                guard let color = translateColor(value) else { return nil }
                config.border.color = color
                config.border.enabled = true
            case ("general", "terminal"):
                guard isValidBundleIdentifier(value) else { return nil }
                config.terminalBundleIdentifier = value
            case ("dwindle", "no_gaps_when_only"):
                config.smartGaps = isTruthy(value)
            case ("master", "orientation"):
                guard let orientation = MasterOptions.Orientation(rawValue: value) else { return nil }
                config.master.orientation = orientation
            case ("master", "mfact"):
                guard let ratio = Double(value), (0.1...0.9).contains(ratio) else { return nil }
                config.master.ratio = ratio
            case ("bar", "position"):
                guard let position = BarPosition(rawValue: value) else { return nil }
                config.barPosition = position
            case ("bar", "height"):
                guard let height = Double(value), height >= 20 else { return nil }
                config.bar.height = height
            case ("bar", "font_size"):
                guard let size = Double(value), size >= 8 else { return nil }
                config.bar.fontSize = size
            case ("bar", "accent"):
                guard let color = translateColor(value) else { return nil }
                config.bar.accent = color
            case ("bar", "opacity"):
                guard let opacity = Double(value), (0...1).contains(opacity) else { return nil }
                config.bar.opacity = opacity
            case ("bar", "hide_empty_workspaces"):
                config.bar.hideEmptyWorkspaces = isTruthy(value)
            case ("bar", "left"), ("bar", "center"), ("bar", "right"):
                let modules = value.split(separator: " ").map(String.init)
                guard BarOptions.isValidModuleList(modules) else { return nil }
                if key == "left" { config.bar.left = modules } else if key == "center" { config.bar.center = modules } else { config.bar.right = modules }
            case ("cursor", "no_warps"):
                config.cursorWarp = !isTruthy(value)
            case ("input", "follow_mouse"):
                config.focusFollowsMouse = isTruthy(value)
            default:
                continue
            }
        }
        return config
    }

    // MARK: - Binds

    /// nil: malformed; .some(nil): a dispatcher macwm does not provide, skipped.
    private static func translateBind(_ value: String) -> (String, String)?? {
        let parts = fields(value)
        guard parts.count >= 3 else { return nil }
        guard let modifiers = translateModifiers(parts[0]), let key = translateKey(parts[1]) else { return nil }
        let binding = (modifiers + [key]).joined(separator: "+")
        guard KeyBinding.isValidSyntax(binding) else { return nil }
        let argument = parts.dropFirst(3).joined(separator: " ")
        guard let command = translateDispatcher(parts[2], argument: argument) else { return .some(nil) }
        return (binding, command)
    }

    private static func translateModifiers(_ text: String) -> [String]? {
        var modifiers: [String] = []
        for token in text.lowercased().split(whereSeparator: { $0 == " " || $0 == "+" }) {
            switch token {
            case "super", "win", "mod4", "cmd", "command": modifiers.append("cmd")
            case "alt", "mod1", "option": modifiers.append("alt")
            case "shift": modifiers.append("shift")
            case "ctrl", "control": modifiers.append("ctrl")
            default: return nil
            }
        }
        return modifiers
    }

    private static func translateKey(_ text: String) -> String? {
        let key = text.lowercased()
        let xkbNames: [String: String] = [
            "bracketleft": "leftbracket", "bracketright": "rightbracket", "apostrophe": "quote",
            "backspace": "delete", "prior": "pageup", "next": "pagedown", "esc": "escape", "kp_enter": "return"
        ]
        return key.isEmpty ? nil : (xkbNames[key] ?? key)
    }

    private static func translateDispatcher(_ dispatcher: String, argument: String) -> String? {
        let directions = ["l": "left", "r": "right", "u": "up", "d": "down", "left": "left", "right": "right", "up": "up", "down": "down"]
        switch dispatcher.lowercased() {
        case "movefocus": return directions[argument].map { "focus \($0)" }
        case "movewindow", "swapwindow": return directions[argument].map { "move \($0)" }
        case "workspace": return Int(argument) != nil || argument == "previous" ? "workspace \(argument)" : nil
        case "movetoworkspace": return Int(argument).map { "move-to-workspace \($0)" }
        case "movetoworkspacesilent": return Int(argument).map { "send-to-workspace \($0)" }
        case "killactive": return "close"
        case "togglegroup": return "group toggle"
        case "moveintogroup": return directions[argument].map { "group add \($0)" }
        case "moveoutofgroup": return "group remove"
        case "changegroupactive": return argument == "b" ? "group prev" : "group next"
        case "togglefloating": return "toggle-float"
        case "fullscreen": return "maximize"
        case "togglesplit": return "toggle-split"
        case "centerwindow": return "center"
        case "cyclenext": return argument.contains("prev") ? "focus prev" : "focus next"
        case "exec": return argument.isEmpty ? nil : "exec \(argument)"
        case "submap": return argument == "reset" ? "mode default" : "mode \(argument)"
        case "togglespecialworkspace": return argument.isEmpty ? nil : "scratchpad \(argument)"
        case "resizeactive", "splitratio":
            let numbers = argument.split(separator: " ").compactMap { Double($0) }
            guard let first = numbers.first(where: { $0 != 0 }) else { return nil }
            return first > 0 ? "resize grow" : "resize shrink"
        case "layoutmsg":
            let parts = argument.split(separator: " ").map(String.init)
            switch parts.first {
            case "preselect":
                guard let side = parts.dropFirst().first else { return nil }
                return ["l", "r"].contains(side) ? "preselect vertical" : "preselect horizontal"
            case "addmaster": return "master add"
            case "removemaster": return "master remove"
            case "orientationleft": return "master orientation left"
            case "orientationright": return "master orientation right"
            case "orientationtop": return "master orientation top"
            case "orientationbottom": return "master orientation bottom"
            case "orientationnext", "orientationcycle": return "master orientation next"
            case "mfact":
                guard let value = parts.dropFirst().first, let delta = Double(value) else { return nil }
                return delta >= 0 ? "master grow" : "master shrink"
            default: return nil
            }
        default: return nil
        }
    }

    // MARK: - Rules

    private static func translateRule(_ value: String) -> WindowRule? {
        let parts = fields(value)
        guard parts.count >= 2 else { return nil }
        var bundleIdentifier: String?
        var title: String?
        for matcher in parts.dropFirst() {
            if matcher.hasPrefix("class:") { bundleIdentifier = literal(matcher.dropFirst("class:".count)) }
            if matcher.hasPrefix("title:") { title = literal(matcher.dropFirst("title:".count)) }
        }
        guard let bundleIdentifier, !bundleIdentifier.isEmpty else { return nil }
        let action = parts[0].split(separator: " ").map(String.init)
        var rule = WindowRule(bundleIdentifier: bundleIdentifier, title: title, float: false)
        switch action.first {
        case "float": rule = WindowRule(bundleIdentifier: bundleIdentifier, title: title, float: true)
        case "tile": break
        case "center": rule = WindowRule(bundleIdentifier: bundleIdentifier, title: title, float: true, center: true)
        case "workspace":
            guard action.count >= 2, let workspace = Int(action[1]), workspace > 0 else { return nil }
            rule = WindowRule(bundleIdentifier: bundleIdentifier, title: title, float: false, workspace: workspace)
        case "size":
            guard action.count == 3, let width = Double(action[1]), let height = Double(action[2]) else { return nil }
            rule = WindowRule(bundleIdentifier: bundleIdentifier, title: title, float: true, width: width, height: height)
        default: return nil
        }
        return rule
    }

    /// Hyprland rules stack one action per line; macwm keeps one rule per window matcher.
    private static func merge(_ rule: WindowRule, into rules: inout [WindowRule]) {
        guard let index = rules.firstIndex(where: { $0.bundleIdentifier == rule.bundleIdentifier && $0.title == rule.title && $0.subrole == rule.subrole }) else {
            rules.append(rule)
            return
        }
        let existing = rules[index]
        rules[index] = WindowRule(
            bundleIdentifier: existing.bundleIdentifier,
            title: existing.title,
            subrole: existing.subrole,
            float: existing.float || rule.float,
            workspace: rule.workspace ?? existing.workspace,
            center: existing.center || rule.center,
            width: rule.width ?? existing.width,
            height: rule.height ?? existing.height
        )
    }

    /// Turns the usual anchored regex, `^(com\\.apple\\.finder)$`, into the literal it names.
    private static func literal<S: StringProtocol>(_ pattern: S) -> String {
        var text = String(pattern)
        if text.hasPrefix("^") { text.removeFirst() }
        if text.hasSuffix("$") { text.removeLast() }
        if text.hasPrefix("("), text.hasSuffix(")") { text = String(text.dropFirst().dropLast()) }
        return text.replacingOccurrences(of: "\\", with: "")
    }

    // MARK: - Helpers

    /// First color of a Hyprland color list: rgb(rrggbb), rgba(rrggbbaa) or 0xaarrggbb.
    private static func translateColor(_ value: String) -> String? {
        guard let token = value.split(separator: " ").first.map(String.init) else { return nil }
        if token.hasPrefix("rgba("), token.hasSuffix(")") {
            let hex = String(token.dropFirst(5).dropLast())
            return BorderOptions.isValidColor("#\(hex)") && hex.count == 8 ? "#\(hex)" : nil
        }
        if token.hasPrefix("rgb("), token.hasSuffix(")") {
            let hex = String(token.dropFirst(4).dropLast())
            return BorderOptions.isValidColor("#\(hex)") && hex.count == 6 ? "#\(hex)" : nil
        }
        if token.hasPrefix("0x"), token.count == 10 {
            let hex = String(token.dropFirst(2))
            return BorderOptions.isValidColor("#\(hex.dropFirst(2))\(hex.prefix(2))") ? "#\(hex.dropFirst(2))\(hex.prefix(2))" : nil
        }
        return nil
    }

    private static func translateLayout(_ value: String) -> LayoutKind? {
        switch value {
        case "dwindle", "bsp": return .bsp
        case "master", "master-stack": return .masterStack
        case "stack", "monocle": return LayoutKind(rawValue: value)
        default: return nil
        }
    }

    private static func fields(_ value: String) -> [String] {
        value.split(separator: ",", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func substitute(_ value: String, variables: [String: String]) -> String {
        var result = value
        for (name, replacement) in variables.sorted(by: { $0.key.count > $1.key.count }) {
            result = result.replacingOccurrences(of: name, with: replacement)
        }
        return result
    }

    private static func stripComment(_ line: String) -> String {
        guard let hash = line.firstIndex(of: "#") else { return line }
        return String(line[..<hash])
    }

    private static func isTruthy(_ value: String) -> Bool {
        ["1", "2", "true", "yes", "on"].contains(value.lowercased())
    }

    private static func isValidBundleIdentifier(_ value: String) -> Bool {
        !value.isEmpty && !value.contains(where: { $0.isWhitespace })
    }
}

/// Where configurations live and which dialect each file uses.
public enum ConfigFile {
    public static let hyprlandPath = NSString(string: "~/.config/macwm/macwm.conf").expandingTildeInPath
    public static let tomlPath = NSString(string: "~/.config/macwm/config.toml").expandingTildeInPath

    /// `macwm.conf` wins when both exist. Nil when no file exists.
    public static func read() -> (path: String, text: String, isHyprland: Bool)? {
        if let text = try? String(contentsOfFile: hyprlandPath, encoding: .utf8) { return (hyprlandPath, text, true) }
        if let text = try? String(contentsOfFile: tomlPath, encoding: .utf8) { return (tomlPath, text, false) }
        return nil
    }

    public static func parse(_ text: String, isHyprland: Bool) -> Config? {
        isHyprland ? HyprlandConfig.parse(text) : Config.parse(text)
    }
}

/// One hotkey as the settings UI sees it: a mode, the key text and the command text.
public struct HotkeyEntry: Equatable, Hashable, Sendable, Comparable, Identifiable {
    public var mode: String
    public var binding: String
    public var command: String

    public init(mode: String = KeybindEngine.defaultMode, binding: String, command: String) {
        self.mode = mode
        self.binding = binding
        self.command = command
    }

    public var id: String { "\(mode)|\(binding)" }

    public static func < (lhs: HotkeyEntry, rhs: HotkeyEntry) -> Bool {
        (lhs.mode, lhs.command, lhs.binding) < (rhs.mode, rhs.command, rhs.binding)
    }
}

/// Legacy `[keys]` names and the command each one stands for.
enum LegacyHotkeys {
    static let simple: [(name: String, command: String)] = [
        ("focus_left", "focus left"), ("focus_down", "focus down"), ("focus_up", "focus up"), ("focus_right", "focus right"),
        ("move_left", "move left"), ("move_down", "move down"), ("move_up", "move up"), ("move_right", "move right"),
        ("maximize", "maximize"), ("toggle_float", "toggle-float"), ("terminal_toggle", "toggle-terminal")
    ]
    /// Names whose binding also implies a shifted companion command.
    static let paired: [(name: String, command: String, shifted: String)] =
        [("resize", "resize grow", "resize shrink")]
        + (1...9).map { ("workspace_\($0)", "workspace \($0)", "send-to-workspace \($0)") }

    static func shifted(_ binding: String) -> String? {
        KeyBinding.parse(binding).map { $0.adding(.shift).text }
    }
}

public extension Config {
    /// Every effective binding: the legacy `[keys]` names expanded into
    /// commands, then `[binds]` layered on top.
    var hotkeyEntries: [HotkeyEntry] {
        var entries: [String: [String: String]] = [:]
        for (name, command) in LegacyHotkeys.simple {
            guard let binding = hotkeys[name] else { continue }
            entries[KeybindEngine.defaultMode, default: [:]][binding] = command
        }
        for (name, command, shifted) in LegacyHotkeys.paired {
            guard let binding = hotkeys[name] else { continue }
            entries[KeybindEngine.defaultMode, default: [:]][binding] = command
            if let shiftedBinding = LegacyHotkeys.shifted(binding) {
                entries[KeybindEngine.defaultMode, default: [:]][shiftedBinding] = shifted
            }
        }
        for (mode, modeBinds) in binds {
            for (binding, command) in modeBinds { entries[mode, default: [:]][binding] = command }
        }
        return entries.flatMap { mode, modeBinds in
            modeBinds.map { HotkeyEntry(mode: mode, binding: $0.key, command: $0.value) }
        }.sorted()
    }

    /// Replaces every binding. Legacy names stay in `[keys]` while their
    /// commands keep the legacy shape; everything else goes to `[binds]`.
    mutating func setHotkeyEntries(_ entries: [HotkeyEntry]) {
        var remaining = entries
        var newHotkeys: [String: String] = [:]
        func take(command: String, binding: String? = nil) -> HotkeyEntry? {
            guard let index = remaining.firstIndex(where: { $0.mode == KeybindEngine.defaultMode && $0.command == command && (binding == nil || $0.binding == binding) }) else { return nil }
            return remaining.remove(at: index)
        }
        for (name, command) in LegacyHotkeys.simple {
            guard let entry = take(command: command) else { continue }
            newHotkeys[name] = entry.binding
        }
        for (name, command, shifted) in LegacyHotkeys.paired {
            guard let index = remaining.firstIndex(where: { $0.mode == KeybindEngine.defaultMode && $0.command == command }) else { continue }
            let entry = remaining[index]
            guard let shiftedBinding = LegacyHotkeys.shifted(entry.binding), take(command: shifted, binding: shiftedBinding) != nil else { continue }
            remaining.remove(at: index)
            newHotkeys[name] = entry.binding
        }
        hotkeys = newHotkeys
        binds = [:]
        for entry in remaining { binds[entry.mode, default: [:]][entry.binding] = entry.command }
    }

    /// The configuration as TOML that `Config.parse` reads back unchanged.
    func toml() -> String {
        var lines: [String] = ["# Written by macwm settings. Comments are not preserved.", "", "[general]"]
        lines.append("layout = \"\(layout.rawValue)\"")
        lines.append("auto_tile = \(autoTile)")
        lines.append("focus_follows_mouse = \(focusFollowsMouse)")
        lines.append("smart_gaps = \(smartGaps)")
        lines.append("cursor_warp = \(cursorWarp)")
        lines.append(contentsOf: ["", "[display]", "outer_gap = \(number(outerGap))", "inner_gap = \(number(innerGap))"])
        lines.append(contentsOf: ["", "[master]", "orientation = \"\(master.orientation.rawValue)\"", "ratio = \(master.ratio)", "count = \(master.count)"])
        lines.append(contentsOf: ["", "[bar]", "position = \"\(barPosition.rawValue)\""])
        lines.append(contentsOf: ["", "[terminal]", "bundle_id = \"\(terminalBundleIdentifier)\""])
        lines.append(contentsOf: ["", "[keys]"])
        for name in (LegacyHotkeys.simple.map(\.name) + LegacyHotkeys.paired.map(\.name)) {
            lines.append("\(name) = \"\(hotkeys[name] ?? "none")\"")
        }
        if !scratchpads.isEmpty {
            lines.append(contentsOf: ["", "[scratchpads]"])
            for (name, bundle) in scratchpads.sorted(by: { $0.key < $1.key }) { lines.append("\(name) = \"\(bundle)\"") }
        }
        if !autostart.isEmpty {
            lines.append(contentsOf: ["", "[autostart]"])
            for (name, command) in autostart.sorted(by: { $0.key < $1.key }) { lines.append("\(name) = \"\(command)\"") }
        }
        for mode in binds.keys.sorted(by: { ($0 == KeybindEngine.defaultMode ? "" : $0) < ($1 == KeybindEngine.defaultMode ? "" : $1) }) {
            guard let modeBinds = binds[mode], !modeBinds.isEmpty else { continue }
            lines.append(contentsOf: ["", mode == KeybindEngine.defaultMode ? "[binds]" : "[binds.\(mode)]"])
            for (binding, command) in modeBinds.sorted(by: { $0.key < $1.key }) { lines.append("\"\(binding)\" = \"\(command)\"") }
        }
        for rule in rules {
            lines.append(contentsOf: ["", "[[rules]]", "bundle_id = \"\(rule.bundleIdentifier)\""])
            if let title = rule.title { lines.append("title = \"\(title)\"") }
            if let subrole = rule.subrole { lines.append("subrole = \"\(subrole)\"") }
            lines.append("float = \(rule.float)")
            if let workspace = rule.workspace { lines.append("workspace = \(workspace)") }
            if rule.center { lines.append("center = true") }
            if let width = rule.width { lines.append("width = \(number(width))") }
            if let height = rule.height { lines.append("height = \(number(height))") }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private func number(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }
}

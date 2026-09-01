public enum Modifier: String, Hashable, Sendable, CaseIterable {
    case shift, ctrl, alt, cmd

    /// Accepts the names Hyprland and macOS users reach for.
    init?(name: String) {
        switch name {
        case "shift": self = .shift
        case "ctrl", "control": self = .ctrl
        case "alt", "option", "opt": self = .alt
        case "cmd", "command", "super", "win": self = .cmd
        default: return nil
        }
    }
}

/// A key press identified by its hardware key code plus the exact modifier set.
public struct KeyBinding: Hashable, Sendable {
    public let keyCode: Int64
    public let modifiers: Set<Modifier>

    public init(keyCode: Int64, modifiers: Set<Modifier>) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// Parses "alt+shift+h", "cmd+return" or a bare key such as "grave".
    public static func parse(_ text: String) -> KeyBinding? {
        let parts = text.lowercased().split(separator: "+", omittingEmptySubsequences: false).map(String.init)
        guard let keyName = parts.last, let keyCode = KeyCodes.code(for: keyName) else { return nil }
        var modifiers: Set<Modifier> = []
        for part in parts.dropLast() {
            guard let modifier = Modifier(name: part) else { return nil }
            modifiers.insert(modifier)
        }
        return KeyBinding(keyCode: keyCode, modifiers: modifiers)
    }

    public func adding(_ modifier: Modifier) -> KeyBinding {
        KeyBinding(keyCode: keyCode, modifiers: modifiers.union([modifier]))
    }
}

/// ANSI (US) virtual key codes, the values CGEvent reports for each physical key.
public enum KeyCodes {
    public static func code(for name: String) -> Int64? { table[name] }

    private static let table: [String: Int64] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12, "w": 13,
        "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "equal": 24,
        "9": 25, "7": 26, "minus": 27, "8": 28, "0": 29, "rightbracket": 30, "o": 31, "u": 32, "leftbracket": 33,
        "i": 34, "p": 35, "return": 36, "enter": 36, "l": 37, "j": 38, "quote": 39, "k": 40, "semicolon": 41,
        "backslash": 42, "comma": 43, "slash": 44, "n": 45, "m": 46, "period": 47, "tab": 48, "space": 49,
        "grave": 50, "delete": 51, "backspace": 51, "escape": 53, "esc": 53,
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97, "f7": 98, "f8": 100, "f9": 101,
        "f10": 109, "f11": 103, "f12": 111, "f13": 105, "f14": 107, "f15": 113,
        "home": 115, "pageup": 116, "forwarddelete": 117, "end": 119, "pagedown": 121,
        "left": 123, "right": 124, "down": 125, "up": 126
    ]
}

/// Resolves key presses to commands through named modes, Hyprland's submaps.
/// A `mode` command switches the active set and consumes the key; keys that
/// are not bound in the active mode pass through to the focused application.
public struct KeybindEngine: Equatable, Sendable {
    public enum Resolution: Equatable, Sendable {
        case unbound
        case consumed
        case command(Command)
    }

    public static let defaultMode = "default"

    private let binds: [String: [KeyBinding: Command]]
    public private(set) var mode: String = KeybindEngine.defaultMode

    public init(binds: [String: [KeyBinding: Command]]) {
        self.binds = binds
    }

    public mutating func handle(_ press: KeyBinding) -> Resolution {
        guard let command = binds[mode]?[press] else { return .unbound }
        guard case let .mode(target) = command else { return .command(command) }
        enter(mode: target)
        return .consumed
    }

    public mutating func enter(mode target: String) {
        guard binds[target] != nil || target == Self.defaultMode else { return }
        mode = target
    }
}

public extension Config {
    /// Explicit `[binds]` entries layered over the legacy `[keys]` names.
    func keybindEngine() -> KeybindEngine {
        var binds: [String: [KeyBinding: Command]] = [KeybindEngine.defaultMode: legacyBindings()]
        for (mode, entries) in self.binds {
            for (bindingText, commandText) in entries {
                guard let binding = KeyBinding.parse(bindingText), let command = Command.parse(commandText) else { continue }
                binds[mode, default: [:]][binding] = command
            }
        }
        return KeybindEngine(binds: binds)
    }

    private func legacyBindings() -> [KeyBinding: Command] {
        var binds: [KeyBinding: Command] = [:]
        let simple: [(String, Command)] = [
            ("focus_left", .focus(.left)), ("focus_down", .focus(.down)), ("focus_up", .focus(.up)), ("focus_right", .focus(.right)),
            ("move_left", .move(.left)), ("move_down", .move(.down)), ("move_up", .move(.up)), ("move_right", .move(.right)),
            ("maximize", .maximize), ("toggle_float", .toggleFloat), ("terminal_toggle", .toggleTerminal)
        ]
        for (name, command) in simple {
            guard let binding = hotkeys[name].flatMap(KeyBinding.parse) else { continue }
            binds[binding] = command
        }
        if let resize = hotkeys["resize"].flatMap(KeyBinding.parse) {
            binds[resize] = .resize(.grow)
            binds[resize.adding(.shift)] = .resize(.shrink)
        }
        for workspace in 1...9 {
            guard let binding = KeyBinding.parse(hotkeys["workspace_\(workspace)"] ?? "alt+\(workspace)") else { continue }
            binds[binding] = .workspace(workspace)
            binds[binding.adding(.shift)] = .sendToWorkspace(workspace)
        }
        return binds
    }
}

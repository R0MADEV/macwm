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
    public static func parse(_ text: String, keyCodes: KeyCodeTable = .ansi) -> KeyBinding? {
        guard let (modifiers, keyName) = components(of: text), let keyCode = keyCodes.code(for: keyName) else { return nil }
        return KeyBinding(keyCode: keyCode, modifiers: modifiers)
    }

    /// True for bindings whose modifiers are valid and whose key is either a
    /// known name or a single character that the active keyboard layout may
    /// resolve later, so configs are not rejected for layout-specific keys.
    public static func isValidSyntax(_ text: String) -> Bool {
        guard let (_, keyName) = components(of: text) else { return false }
        return KeyCodeTable.ansi.code(for: keyName) != nil || keyName.count == 1
    }

    private static func components(of text: String) -> (Set<Modifier>, String)? {
        let parts = text.lowercased().split(separator: "+", omittingEmptySubsequences: false).map(String.init)
        guard let keyName = parts.last, !keyName.isEmpty else { return nil }
        var modifiers: Set<Modifier> = []
        for part in parts.dropLast() {
            guard let modifier = Modifier(name: part) else { return nil }
            modifiers.insert(modifier)
        }
        return (modifiers, keyName)
    }

    /// Text form with modifiers in a fixed order, e.g. "alt+shift+h".
    public var text: String {
        let order: [Modifier] = [.ctrl, .alt, .shift, .cmd]
        let names = order.filter { modifiers.contains($0) }.map(\.rawValue)
        return (names + [KeyCodes.name(for: keyCode) ?? "key\(keyCode)"]).joined(separator: "+")
    }

    public func adding(_ modifier: Modifier) -> KeyBinding {
        KeyBinding(keyCode: keyCode, modifiers: modifiers.union([modifier]))
    }
}

/// Key names resolved to virtual key codes. `.ansi` is the US layout; a
/// layout-aware table also accepts the literal characters the current layout
/// produces and moves symbol names such as `minus` to the key that types them.
public struct KeyCodeTable: Equatable, Sendable {
    public static let ansi = KeyCodeTable(codes: KeyCodes.table)

    public let codes: [String: Int64]

    public init(codes: [String: Int64]) {
        self.codes = codes
    }

    /// `layoutCharacters` maps the character each key produces without modifiers to its key code.
    public init(layoutCharacters: [String: Int64]) {
        var codes = KeyCodes.table
        for (character, code) in layoutCharacters { codes[character] = code }
        for (name, character) in KeyCodes.symbolNames {
            guard let code = layoutCharacters[character] else { continue }
            codes[name] = code
        }
        self.codes = codes
    }

    public func code(for name: String) -> Int64? { codes[name] }
}

/// ANSI (US) virtual key codes, the values CGEvent reports for each physical key.
public enum KeyCodes {
    public static func code(for name: String) -> Int64? { table[name] }

    /// Canonical name for a key code, preferring the shortest of the aliases.
    public static func name(for code: Int64) -> String? {
        table.filter { $0.value == code }.map(\.key).min { ($0.count, $0) < ($1.count, $1) }
    }

    /// Symbol names and the character they stand for on the US layout.
    static let symbolNames: [String: String] = [
        "grave": "`", "minus": "-", "equal": "=", "leftbracket": "[", "rightbracket": "]", "semicolon": ";",
        "quote": "'", "comma": ",", "period": ".", "slash": "/", "backslash": "\\"
    ]

    static let table: [String: Int64] = [
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
    func keybindEngine(keyCodes: KeyCodeTable = .ansi) -> KeybindEngine {
        var binds: [String: [KeyBinding: Command]] = [KeybindEngine.defaultMode: legacyBindings(keyCodes: keyCodes)]
        for (mode, entries) in self.binds {
            for (bindingText, commandText) in entries {
                guard let binding = KeyBinding.parse(bindingText, keyCodes: keyCodes), let command = Command.parse(commandText) else { continue }
                binds[mode, default: [:]][binding] = command
            }
        }
        return KeybindEngine(binds: binds)
    }

    private func legacyBindings(keyCodes: KeyCodeTable) -> [KeyBinding: Command] {
        let parse = { (text: String) in KeyBinding.parse(text, keyCodes: keyCodes) }
        var binds: [KeyBinding: Command] = [:]
        let simple: [(String, Command)] = [
            ("focus_left", .focus(.left)), ("focus_down", .focus(.down)), ("focus_up", .focus(.up)), ("focus_right", .focus(.right)),
            ("move_left", .move(.left)), ("move_down", .move(.down)), ("move_up", .move(.up)), ("move_right", .move(.right)),
            ("maximize", .maximize), ("toggle_float", .toggleFloat), ("terminal_toggle", .toggleTerminal)
        ]
        for (name, command) in simple {
            guard let binding = hotkeys[name].flatMap(parse) else { continue }
            binds[binding] = command
        }
        if let resize = hotkeys["resize"].flatMap(parse) {
            binds[resize] = .resize(.grow)
            binds[resize.adding(.shift)] = .resize(.shrink)
        }
        for workspace in 1...9 {
            guard let binding = parse(hotkeys["workspace_\(workspace)"] ?? "alt+\(workspace)") else { continue }
            binds[binding] = .workspace(workspace)
            binds[binding.adding(.shift)] = .sendToWorkspace(workspace)
        }
        return binds
    }
}

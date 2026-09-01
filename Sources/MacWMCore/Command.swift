public enum Query: String, Equatable, Sendable {
    case state, windows, workspaces
}

public enum Command: Equatable, Sendable {
    case status
    /// JSON view of the daemon state for scripts and external bars.
    case query(Query)
    case reload
    case layout(LayoutKind)
    case workspace(Int)
    /// Back to the workspace that was active before the current one.
    case previousWorkspace
    /// Center the focused floating window on its screen.
    case center
    case sendToWorkspace(Int)
    /// Send the focused window to a workspace and follow it there.
    case moveToWorkspace(Int)
    case focus(Direction)
    case move(Direction)
    case resize(ResizeOperation)
    case maximize
    case toggleFloat
    case toggleTerminal
    case close
    /// Toggle a scratchpad by its configured name or bundle identifier.
    case scratchpad(String)
    /// Focus the next or previous window of the active workspace.
    case cycleFocus(forward: Bool)
    /// Flip the split direction of the focused window's parent node in the BSP tree.
    case toggleSplit
    /// Split direction for the next window opened in the active workspace.
    case preselect(SplitDirection)
    /// Run a shell command line through the user's login shell.
    case exec(String)
    /// Switches the hotkey engine to a named mode; "default" leaves any mode.
    case mode(String)

    /// Parses a command written as one string, e.g. "workspace 2".
    public static func parse(_ text: String) -> Command? {
        parse(text.split(separator: " ").map(String.init))
    }

    public static func parse(_ arguments: [String]) -> Command? {
        guard let name = arguments.first else { return nil }
        let value = arguments.dropFirst().first

        switch name {
        case "status": return arguments.count == 1 ? .status : nil
        case "query":
            guard arguments.count == 2, let value else { return nil }
            return Query(rawValue: value).map(Command.query)
        case "reload": return arguments.count == 1 ? .reload : nil
        case "layout":
            guard arguments.count == 2, let value else { return nil }
            let layoutValue = value == "master" ? "master-stack" : value
            return LayoutKind(rawValue: layoutValue).map(Command.layout)
        case "workspace":
            guard arguments.count == 2, let value else { return nil }
            if value == "previous" { return .previousWorkspace }
            return Int(value).map(Command.workspace)
        case "center": return arguments.count == 1 ? .center : nil
        case "send-to-workspace": return arguments.count == 2 ? value.flatMap(Int.init).map(Command.sendToWorkspace) : nil
        case "move-to-workspace": return arguments.count == 2 ? value.flatMap(Int.init).map(Command.moveToWorkspace) : nil
        case "focus":
            guard arguments.count == 2, let value else { return nil }
            if value == "next" { return .cycleFocus(forward: true) }
            if value == "prev" || value == "previous" { return .cycleFocus(forward: false) }
            return Direction(rawValue: value).map(Command.focus)
        case "close": return arguments.count == 1 ? .close : nil
        case "scratchpad":
            guard arguments.count == 2, let value, !value.isEmpty else { return nil }
            return .scratchpad(value)
        case "toggle-split": return arguments.count == 1 ? .toggleSplit : nil
        case "preselect":
            guard arguments.count == 2, let value else { return nil }
            return SplitDirection(rawValue: value).map(Command.preselect)
        case "exec":
            let commandLine = arguments.dropFirst().joined(separator: " ")
            return commandLine.isEmpty ? nil : .exec(commandLine)
        case "move": return value.flatMap(Direction.init(rawValue:)) .map(Command.move)
        case "resize": return value.flatMap(ResizeOperation.init(rawValue:)) .map(Command.resize)
        case "maximize": return arguments.count == 1 ? .maximize : nil
        case "toggle-float": return arguments.count == 1 ? .toggleFloat : nil
        case "toggle-terminal": return arguments.count == 1 ? .toggleTerminal : nil
        case "mode":
            guard arguments.count == 2, let value, !value.isEmpty else { return nil }
            return .mode(value)
        default: return nil
        }
    }

    public var wireValue: String {
        switch self {
        case .status: return "status"
        case let .query(query): return "query \(query.rawValue)"
        case .reload: return "reload"
        case let .layout(layout): return "layout \(layout.rawValue)"
        case let .workspace(workspace): return "workspace \(workspace)"
        case .previousWorkspace: return "workspace previous"
        case .center: return "center"
        case let .sendToWorkspace(workspace): return "send-to-workspace \(workspace)"
        case let .moveToWorkspace(workspace): return "move-to-workspace \(workspace)"
        case let .focus(direction): return "focus \(direction.rawValue)"
        case let .move(direction): return "move \(direction.rawValue)"
        case let .resize(operation): return "resize \(operation.rawValue)"
        case .maximize: return "maximize"
        case .toggleFloat: return "toggle-float"
        case .toggleTerminal: return "toggle-terminal"
        case let .mode(name): return "mode \(name)"
        case .close: return "close"
        case let .scratchpad(name): return "scratchpad \(name)"
        case let .cycleFocus(forward): return forward ? "focus next" : "focus prev"
        case .toggleSplit: return "toggle-split"
        case let .preselect(direction): return "preselect \(direction.rawValue)"
        case let .exec(commandLine): return "exec \(commandLine)"
        }
    }
}

private extension Direction {
    init?(rawValue: String) {
        switch rawValue {
        case "left": self = .left
        case "right": self = .right
        case "up": self = .up
        case "down": self = .down
        default: return nil
        }
    }

    var rawValue: String {
        switch self {
        case .left: return "left"
        case .right: return "right"
        case .up: return "up"
        case .down: return "down"
        }
    }
}

private extension SplitDirection {
    init?(rawValue: String) {
        switch rawValue {
        case "vertical": self = .vertical
        case "horizontal": self = .horizontal
        default: return nil
        }
    }

    var rawValue: String {
        switch self {
        case .vertical: return "vertical"
        case .horizontal: return "horizontal"
        }
    }
}

private extension ResizeOperation {
    init?(rawValue: String) {
        switch rawValue {
        case "grow": self = .grow
        case "shrink": self = .shrink
        default: return nil
        }
    }

    var rawValue: String {
        switch self {
        case .grow: return "grow"
        case .shrink: return "shrink"
        }
    }
}

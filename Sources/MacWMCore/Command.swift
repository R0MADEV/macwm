public enum Command: Equatable, Sendable {
    case status
    case reload
    case layout(LayoutKind)
    case workspace(Int)
    case sendToWorkspace(Int)
    case focus(Direction)
    case move(Direction)
    case resize(ResizeOperation)
    case maximize
    case toggleFloat
    case toggleTerminal

    public static func parse(_ arguments: [String]) -> Command? {
        guard let name = arguments.first else { return nil }
        let value = arguments.dropFirst().first

        switch name {
        case "status": return arguments.count == 1 ? .status : nil
        case "reload": return arguments.count == 1 ? .reload : nil
        case "layout":
            guard arguments.count == 2, let value else { return nil }
            let layoutValue = value == "master" ? "master-stack" : value
            return LayoutKind(rawValue: layoutValue).map(Command.layout)
        case "workspace": return arguments.count == 2 ? value.flatMap(Int.init).map(Command.workspace) : nil
        case "send-to-workspace": return arguments.count == 2 ? value.flatMap(Int.init).map(Command.sendToWorkspace) : nil
        case "focus": return value.flatMap(Direction.init(rawValue:)) .map(Command.focus)
        case "move": return value.flatMap(Direction.init(rawValue:)) .map(Command.move)
        case "resize": return value.flatMap(ResizeOperation.init(rawValue:)) .map(Command.resize)
        case "maximize": return arguments.count == 1 ? .maximize : nil
        case "toggle-float": return arguments.count == 1 ? .toggleFloat : nil
        case "toggle-terminal": return arguments.count == 1 ? .toggleTerminal : nil
        default: return nil
        }
    }

    public var wireValue: String {
        switch self {
        case .status: return "status"
        case .reload: return "reload"
        case let .layout(layout): return "layout \(layout.rawValue)"
        case let .workspace(workspace): return "workspace \(workspace)"
        case let .sendToWorkspace(workspace): return "send-to-workspace \(workspace)"
        case let .focus(direction): return "focus \(direction.rawValue)"
        case let .move(direction): return "move \(direction.rawValue)"
        case let .resize(operation): return "resize \(operation.rawValue)"
        case .maximize: return "maximize"
        case .toggleFloat: return "toggle-float"
        case .toggleTerminal: return "toggle-terminal"
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

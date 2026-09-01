/// Shape of the master-and-stack layout, like Hyprland's master options:
/// which side the masters take, how much of the frame they get and how many
/// windows count as masters.
public struct MasterOptions: Equatable, Sendable, Codable {
    public enum Orientation: String, Equatable, Sendable, Codable, CaseIterable {
        case left, right, top, bottom

        public var next: Orientation {
            let all = Orientation.allCases
            return all[(all.firstIndex(of: self)! + 1) % all.count]
        }
    }

    public var orientation: Orientation
    public var ratio: Double
    public var count: Int

    public init(orientation: Orientation = .left, ratio: Double = 0.5, count: Int = 1) {
        self.orientation = orientation
        self.ratio = min(max(ratio, 0.1), 0.9)
        self.count = max(1, count)
    }

    public mutating func adjustRatio(by delta: Double) {
        ratio = min(max(ratio + delta, 0.1), 0.9)
    }

    public mutating func adjustCount(by delta: Int) {
        count = max(1, count + delta)
    }
}

public enum MasterCommand: Equatable, Sendable {
    case grow
    case shrink
    case addMaster
    case removeMaster
    case orientation(MasterOptions.Orientation)
    case nextOrientation

    public static func parse(_ arguments: [String]) -> MasterCommand? {
        switch (arguments.first, arguments.dropFirst().first, arguments.count) {
        case ("grow", nil, 1): return .grow
        case ("shrink", nil, 1): return .shrink
        case ("add", nil, 1): return .addMaster
        case ("remove", nil, 1): return .removeMaster
        case ("orientation", "next", 2): return .nextOrientation
        case ("orientation", let value?, 2): return MasterOptions.Orientation(rawValue: value).map(MasterCommand.orientation)
        default: return nil
        }
    }

    public var wireValue: String {
        switch self {
        case .grow: return "grow"
        case .shrink: return "shrink"
        case .addMaster: return "add"
        case .removeMaster: return "remove"
        case let .orientation(orientation): return "orientation \(orientation.rawValue)"
        case .nextOrientation: return "orientation next"
        }
    }
}

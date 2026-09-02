public struct Frame: Equatable, Sendable, Codable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public enum SplitDirection: Sendable, Equatable, Codable {
    case horizontal
    case vertical
}

public enum Direction: Sendable, Equatable {
    case left
    case right
    case up
    case down
}

public enum ResizeOperation: Sendable, Equatable {
    case grow
    case shrink
    case wider
    case narrower
    case taller
    case shorter

    /// Change along each axis, as a sign; grow and shrink touch both.
    public var horizontalSign: Double {
        switch self {
        case .grow, .wider: return 1
        case .shrink, .narrower: return -1
        case .taller, .shorter: return 0
        }
    }

    public var verticalSign: Double {
        switch self {
        case .grow, .taller: return 1
        case .shrink, .shorter: return -1
        case .wider, .narrower: return 0
        }
    }
}

public extension Frame {
    /// Pseudotile: the window keeps its own size, clamped to the tile, centered in it.
    static func pseudotile(ownSize: (width: Double, height: Double), in tile: Frame) -> Frame {
        let width = min(ownSize.width, tile.width)
        let height = min(ownSize.height, tile.height)
        return Frame(x: tile.x + (tile.width - width) / 2, y: tile.y + (tile.height - height) / 2, width: width, height: height)
    }

    func resized(
        operation: ResizeOperation,
        amount: Double,
        minimumSize: (width: Double, height: Double) = (120, 80)
    ) -> Frame {
        let width = max(minimumSize.width, width + operation.horizontalSign * amount)
        let height = max(minimumSize.height, height + operation.verticalSign * amount)
        return Frame(
            x: x + (self.width - width) / 2,
            y: y + (self.height - height) / 2,
            width: width,
            height: height
        )
    }
}

public extension Frame {
    /// Off-screen spot used to hide a window without minimizing it. The frame
    /// keeps its size and only `visibleSliver` points stay on screen at the
    /// bottom-right corner, which macOS allows while a fully off-screen window
    /// would be pushed back.
    func parked(in screen: Frame, visibleSliver: Double = 1) -> Frame {
        Frame(
            x: screen.x + screen.width - visibleSliver,
            y: screen.y + screen.height - visibleSliver,
            width: width,
            height: height
        )
    }

    func isParked(in screen: Frame, visibleSliver: Double = 1) -> Bool {
        x >= screen.x + screen.width - visibleSliver && y >= screen.y + screen.height - visibleSliver
    }

    func centered(in container: Frame) -> Frame {
        Frame(
            x: container.x + (container.width - width) / 2,
            y: container.y + (container.height - height) / 2,
            width: width,
            height: height
        )
    }
}

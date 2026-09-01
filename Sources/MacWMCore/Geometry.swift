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
}

public extension Frame {
    func resized(
        operation: ResizeOperation,
        amount: Double,
        minimumSize: (width: Double, height: Double) = (120, 80)
    ) -> Frame {
        let signedAmount = operation == .grow ? amount : -amount
        let width = max(minimumSize.width, width + signedAmount)
        let height = max(minimumSize.height, height + signedAmount)
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

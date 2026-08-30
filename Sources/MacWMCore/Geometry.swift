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

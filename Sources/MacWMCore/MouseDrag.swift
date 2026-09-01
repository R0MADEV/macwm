/// A mouse drag started on a floating window: moves it with the cursor or
/// resizes it from its bottom-right corner.
public struct MouseDrag: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case move
        case resize
    }

    public let kind: Kind
    public let startFrame: Frame
    public let startX: Double
    public let startY: Double

    public init(kind: Kind, startFrame: Frame, startX: Double, startY: Double) {
        self.kind = kind
        self.startFrame = startFrame
        self.startX = startX
        self.startY = startY
    }

    public func frame(atX x: Double, y: Double, minimumSize: (width: Double, height: Double) = (120, 80)) -> Frame {
        let deltaX = x - startX
        let deltaY = y - startY
        switch kind {
        case .move:
            return Frame(x: startFrame.x + deltaX, y: startFrame.y + deltaY, width: startFrame.width, height: startFrame.height)
        case .resize:
            return Frame(
                x: startFrame.x,
                y: startFrame.y,
                width: max(minimumSize.width, startFrame.width + deltaX),
                height: max(minimumSize.height, startFrame.height + deltaY)
            )
        }
    }
}

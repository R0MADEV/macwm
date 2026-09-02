public enum BarPosition: String, Equatable, Sendable, Codable {
    case top
    case bottom
    case left
    case right
}

public extension BarPosition {
    /// Points the bar occupies along its screen edge.
    var thickness: Double {
        switch self {
        case .top, .bottom: return 34
        case .left, .right: return 48
        }
    }

    var isVertical: Bool { self == .left || self == .right }
}

public extension Frame {
    /// The visible area minus whatever part of the bar lies inside it. The bar
    /// hugs the screen edge, so a top bar hidden behind the menu bar costs nothing.
    func reserving(bar position: BarPosition, screen: Frame, thickness: Double? = nil) -> Frame {
        let thickness = thickness ?? position.thickness
        switch position {
        case .top:
            let barBottom = screen.y + thickness
            let top = max(y, barBottom)
            return Frame(x: x, y: top, width: width, height: max(0, y + height - top))
        case .bottom:
            let barTop = screen.y + screen.height - thickness
            return Frame(x: x, y: y, width: width, height: max(0, min(y + height, barTop) - y))
        case .left:
            let barRight = screen.x + thickness
            let left = max(x, barRight)
            return Frame(x: left, y: y, width: max(0, x + width - left), height: height)
        case .right:
            let barLeft = screen.x + screen.width - thickness
            return Frame(x: x, y: y, width: max(0, min(x + width, barLeft) - x), height: height)
        }
    }
}

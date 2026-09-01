public indirect enum WindowTree: Sendable, Equatable, Codable {
    case leaf(WindowID)
    case split(
        direction: SplitDirection,
        ratio: Double,
        first: WindowTree,
        second: WindowTree
    )

    public var windowIDs: Set<WindowID> {
        switch self {
        case let .leaf(window): return [window]
        case let .split(_, _, first, second): return first.windowIDs.union(second.windowIDs)
        }
    }

    public var leafCount: Int {
        switch self {
        case .leaf: return 1
        case let .split(_, _, first, second): return first.leafCount + second.leafCount
        }
    }

    public var isAdaptive: Bool {
        adaptiveShape(.vertical)
    }

    private func adaptiveShape(_ expectedDirection: SplitDirection) -> Bool {
        switch self {
        case .leaf:
            return true
        case let .split(direction, ratio, first, second):
            let isBalanced = abs(ratio - 0.5) < 0.001
            let nextDirection: SplitDirection = expectedDirection == .vertical ? .horizontal : .vertical
            return direction == expectedDirection
                && isBalanced
                && first.adaptiveShape(nextDirection)
                && second.adaptiveShape(nextDirection)
        }
    }

    public func swapped(_ firstID: WindowID, _ secondID: WindowID) -> WindowTree {
        switch self {
        case let .leaf(window):
            if window == firstID { return .leaf(secondID) }
            if window == secondID { return .leaf(firstID) }
            return self
        case let .split(direction, ratio, first, second):
            return .split(
                direction: direction,
                ratio: ratio,
                first: first.swapped(firstID, secondID),
                second: second.swapped(firstID, secondID)
            )
        }
    }

    /// Flips the direction of the split directly containing `id`, Hyprland's togglesplit.
    public func togglingSplit(containing id: WindowID) -> WindowTree {
        guard case let .split(direction, ratio, first, second) = self, windowIDs.contains(id) else { return self }
        let isParentOfWindow = first == .leaf(id) || second == .leaf(id)
        if isParentOfWindow {
            let flipped: SplitDirection = direction == .vertical ? .horizontal : .vertical
            return .split(direction: flipped, ratio: ratio, first: first, second: second)
        }
        return .split(direction: direction, ratio: ratio, first: first.togglingSplit(containing: id), second: second.togglingSplit(containing: id))
    }

    public func frames(in frame: Frame) -> [WindowID: Frame] {
        switch self {
        case let .leaf(window):
            return [window: frame]
        case let .split(direction, ratio, first, second):
            let boundedRatio = min(max(ratio, 0.1), 0.9)
            let firstFrame: Frame
            let secondFrame: Frame

            switch direction {
            case .horizontal:
                let firstHeight = frame.height * boundedRatio
                firstFrame = Frame(x: frame.x, y: frame.y, width: frame.width, height: firstHeight)
                secondFrame = Frame(x: frame.x, y: frame.y + firstHeight, width: frame.width, height: frame.height - firstHeight)
            case .vertical:
                let firstWidth = frame.width * boundedRatio
                firstFrame = Frame(x: frame.x, y: frame.y, width: firstWidth, height: frame.height)
                secondFrame = Frame(x: frame.x + firstWidth, y: frame.y, width: frame.width - firstWidth, height: frame.height)
            }

            return first.frames(in: firstFrame).merging(second.frames(in: secondFrame)) { _, new in new }
        }
    }
}

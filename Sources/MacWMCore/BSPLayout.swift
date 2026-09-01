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

    public var lastLeaf: WindowID {
        switch self {
        case let .leaf(window): return window
        case let .split(_, _, _, second): return second.lastLeaf
        }
    }

    /// Replaces the `target` leaf with a split holding `target` and the new window.
    public func inserting(_ id: WindowID, at target: WindowID, direction: SplitDirection, ratio: Double = 0.5) -> WindowTree {
        switch self {
        case let .leaf(window):
            guard window == target else { return self }
            return .split(direction: direction, ratio: ratio, first: .leaf(window), second: .leaf(id))
        case let .split(splitDirection, splitRatio, first, second):
            return .split(
                direction: splitDirection,
                ratio: splitRatio,
                first: first.inserting(id, at: target, direction: direction, ratio: ratio),
                second: second.inserting(id, at: target, direction: direction, ratio: ratio)
            )
        }
    }

    /// Removes a leaf; its sibling takes the parent's place. Nil when nothing is left.
    public func removing(_ id: WindowID) -> WindowTree? {
        switch self {
        case let .leaf(window):
            return window == id ? nil : self
        case let .split(direction, ratio, first, second):
            switch (first.removing(id), second.removing(id)) {
            case (nil, nil): return nil
            case (nil, let remaining?), (let remaining?, nil): return remaining
            case (let newFirst?, let newSecond?): return .split(direction: direction, ratio: ratio, first: newFirst, second: newSecond)
            }
        }
    }

    /// Dwindle rule: a wide leaf is split side by side, a tall one top and bottom.
    public func automaticSplitDirection(for id: WindowID, in frame: Frame) -> SplitDirection {
        let leafFrame = frames(in: frame)[id] ?? frame
        return leafFrame.width >= leafFrame.height ? .vertical : .horizontal
    }

    /// Gives the side holding `id` more (or less) of its nearest split, so a
    /// keyboard resize of a tiled window changes the layout instead of fighting it.
    public func adjustingRatio(for id: WindowID, by delta: Double) -> WindowTree {
        guard case let .split(direction, ratio, first, second) = self, windowIDs.contains(id) else { return self }
        let isParentOfWindow = first == .leaf(id) || second == .leaf(id)
        guard isParentOfWindow else {
            return .split(direction: direction, ratio: ratio, first: first.adjustingRatio(for: id, by: delta), second: second.adjustingRatio(for: id, by: delta))
        }
        let signedDelta = first == .leaf(id) ? delta : -delta
        let bounded = min(max(ratio + signedDelta, 0.1), 0.9)
        return .split(direction: direction, ratio: bounded, first: first, second: second)
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
            let (firstFrame, secondFrame) = Self.childFrames(direction: direction, ratio: ratio, in: frame)
            return first.frames(in: firstFrame).merging(second.frames(in: secondFrame)) { _, new in new }
        }
    }

    /// Mouse resize of a tiled window: horizontal drag moves the nearest
    /// vertical split above the window, vertical drag the nearest horizontal
    /// one, each by the dragged fraction of that split's frame. Positive deltas
    /// make the window wider and taller.
    public func resizing(_ id: WindowID, deltaX: Double, deltaY: Double, in frame: Frame) -> WindowTree {
        resizingNode(id, deltaX: deltaX, deltaY: deltaY, in: frame).tree
    }

    private func resizingNode(_ id: WindowID, deltaX: Double, deltaY: Double, in frame: Frame) -> (tree: WindowTree, needsVertical: Bool, needsHorizontal: Bool) {
        switch self {
        case let .leaf(window):
            let isTarget = window == id
            return (self, isTarget, isTarget)
        case let .split(direction, ratio, first, second):
            guard windowIDs.contains(id) else { return (self, false, false) }
            let (firstFrame, secondFrame) = Self.childFrames(direction: direction, ratio: ratio, in: frame)
            let isInFirst = first.windowIDs.contains(id)
            let child = isInFirst
                ? first.resizingNode(id, deltaX: deltaX, deltaY: deltaY, in: firstFrame)
                : second.resizingNode(id, deltaX: deltaX, deltaY: deltaY, in: secondFrame)
            var newRatio = ratio
            var needsVertical = child.needsVertical
            var needsHorizontal = child.needsHorizontal
            let sign: Double = isInFirst ? 1 : -1
            if direction == .vertical, needsVertical, frame.width > 0 {
                newRatio += sign * deltaX / frame.width
                needsVertical = false
            }
            if direction == .horizontal, needsHorizontal, frame.height > 0 {
                newRatio += sign * deltaY / frame.height
                needsHorizontal = false
            }
            let bounded = min(max(newRatio, 0.1), 0.9)
            let tree = WindowTree.split(direction: direction, ratio: bounded, first: isInFirst ? child.tree : first, second: isInFirst ? second : child.tree)
            return (tree, needsVertical, needsHorizontal)
        }
    }

    private static func childFrames(direction: SplitDirection, ratio: Double, in frame: Frame) -> (Frame, Frame) {
        let boundedRatio = min(max(ratio, 0.1), 0.9)
        switch direction {
        case .horizontal:
            let firstHeight = frame.height * boundedRatio
            return (
                Frame(x: frame.x, y: frame.y, width: frame.width, height: firstHeight),
                Frame(x: frame.x, y: frame.y + firstHeight, width: frame.width, height: frame.height - firstHeight)
            )
        case .vertical:
            let firstWidth = frame.width * boundedRatio
            return (
                Frame(x: frame.x, y: frame.y, width: firstWidth, height: frame.height),
                Frame(x: frame.x + firstWidth, y: frame.y, width: frame.width - firstWidth, height: frame.height)
            )
        }
    }
}

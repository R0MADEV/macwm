public enum BSPLayout {
    public static func tree(for windows: [WindowID]) -> WindowTree? {
        guard !windows.isEmpty else { return nil }
        return buildTree(windows, direction: .vertical)
    }

    public static func tree(for windows: [WindowID], in frame: Frame) -> WindowTree? {
        return tree(for: windows)
    }

    public static func frames(for tree: WindowTree, in frame: Frame, outerGap: Double = 8, innerGap: Double = 8) -> [WindowID: Frame] {
        let safeOuterGap = max(0, outerGap)
        let safeInnerGap = max(0, innerGap)
        let usableFrame = Frame(x: frame.x + safeOuterGap, y: frame.y + safeOuterGap, width: max(0, frame.width - safeOuterGap * 2), height: max(0, frame.height - safeOuterGap * 2))
        return treeFrames(tree, in: usableFrame, gap: safeInnerGap)
    }

    private static func treeFrames(_ tree: WindowTree, in frame: Frame, gap: Double) -> [WindowID: Frame] {
        switch tree {
        case let .leaf(window): return [window: frame]
        case let .split(direction, ratio, first, second):
            let boundedRatio = min(max(ratio, 0.1), 0.9)
            switch direction {
            case .vertical:
                let available = max(0, frame.width - gap)
                let width = available * boundedRatio
                return treeFrames(first, in: Frame(x: frame.x, y: frame.y, width: width, height: frame.height), gap: gap)
                    .merging(treeFrames(second, in: Frame(x: frame.x + width + gap, y: frame.y, width: available - width, height: frame.height), gap: gap)) { _, new in new }
            case .horizontal:
                let available = max(0, frame.height - gap)
                let height = available * boundedRatio
                return treeFrames(first, in: Frame(x: frame.x, y: frame.y, width: frame.width, height: height), gap: gap)
                    .merging(treeFrames(second, in: Frame(x: frame.x, y: frame.y + height + gap, width: frame.width, height: available - height), gap: gap)) { _, new in new }
            }
        }
    }

    public static func frames(
        for windows: [WindowID],
        in frame: Frame,
        outerGap: Double = 8,
        innerGap: Double = 8
    ) -> [WindowID: Frame] {
        guard !windows.isEmpty else { return [:] }
        let safeOuterGap = max(0, outerGap)
        let safeInnerGap = max(0, innerGap)
        let usableFrame = Frame(
            x: frame.x + safeOuterGap,
            y: frame.y + safeOuterGap,
            width: max(0, frame.width - safeOuterGap * 2),
            height: max(0, frame.height - safeOuterGap * 2)
        )
        guard let tree = tree(for: windows) else { return [:] }
        return treeFrames(tree, in: usableFrame, gap: safeInnerGap)
    }

    private static func buildTree(_ windows: [WindowID], direction: SplitDirection) -> WindowTree? {
        guard !windows.isEmpty else { return nil }
        guard windows.count > 1 else { return .leaf(windows[0]) }
        let firstCount = max(1, windows.count / 2)
        let firstWindows = Array(windows[..<firstCount])
        let secondWindows = Array(windows[firstCount...])
        let nextDirection: SplitDirection = direction == .vertical ? .horizontal : .vertical
        guard let first = buildTree(firstWindows, direction: nextDirection),
              let second = buildTree(secondWindows, direction: nextDirection) else { return nil }
        return .split(direction: direction, ratio: 0.5, first: first, second: second)
    }

}

public enum LayoutEngine {
    public static func frames(for windows: [WindowID], layout: LayoutKind, in frame: Frame, outerGap: Double = 8, innerGap: Double = 8) -> [WindowID: Frame] {
        guard !windows.isEmpty else { return [:] }
        let outer = max(0, outerGap)
        let gap = max(0, innerGap)
        let usable = Frame(x: frame.x + outer, y: frame.y + outer, width: max(0, frame.width - outer * 2), height: max(0, frame.height - outer * 2))
        switch layout {
        case .bsp:
            return BSPLayout.frames(for: windows, in: frame, outerGap: outer, innerGap: gap)
        case .monocle:
            return Dictionary(uniqueKeysWithValues: windows.map { ($0, usable) })
        case .stack:
            return verticalFrames(windows, in: usable, gap: gap)
        case .masterStack:
            guard windows.count > 1 else { return [windows[0]: usable] }
            let available = max(0, usable.width - gap)
            let masterWidth = available * 0.5
            var result = [windows[0]: Frame(x: usable.x, y: usable.y, width: masterWidth, height: usable.height)]
            result.merge(verticalFrames(Array(windows.dropFirst()), in: Frame(x: usable.x + masterWidth + gap, y: usable.y, width: available - masterWidth, height: usable.height), gap: gap)) { _, new in new }
            return result
        }
    }

    private static func verticalFrames(_ windows: [WindowID], in frame: Frame, gap: Double) -> [WindowID: Frame] {
        let height = max(0, (frame.height - gap * Double(max(0, windows.count - 1))) / Double(windows.count))
        return Dictionary(uniqueKeysWithValues: windows.enumerated().map { index, id in
            (id, Frame(x: frame.x, y: frame.y + Double(index) * (height + gap), width: frame.width, height: height))
        })
    }
}

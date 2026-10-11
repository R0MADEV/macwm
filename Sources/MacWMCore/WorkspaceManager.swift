public struct WorkspaceManager: Sendable {
    public let count: Int
    public private(set) var activeWorkspace: Int
    /// Workspace active before the current one, for back-and-forth switching.
    public private(set) var previousWorkspace: Int?
    private var assignments: [WindowID: Int]
    private var keyAssignments: [WindowKey: Int]
    private var keyOwners: [WindowKey: WindowID]
    private var windowKeys: [WindowID: WindowKey]
    private var trees: [Int: WindowTree]
    private var layouts: [Int: LayoutKind]
    private var lastFocused: [Int: WindowID] = [:]
    /// Workspaces whose window set changed outside a tiling pass, so the
    /// next pass lays them out as a fresh grid.
    private var staleGrids: Set<Int> = []
    /// Smallest size each window accepted, learned from windows that stayed
    /// larger than their tile.
    private var minimumSizes: [WindowID: Size] = [:]
    private var groups = WindowGroups()

    public init(count: Int = 9, assignments: [WindowKey: Int] = [:], activeWorkspace: Int = 1, trees: [Int: WindowTree] = [:], layouts: [Int: LayoutKind] = [:]) {
        let normalizedCount = max(1, count)
        self.count = normalizedCount
        self.activeWorkspace = (1...normalizedCount).contains(activeWorkspace) ? activeWorkspace : 1
        self.assignments = [:]
        keyAssignments = assignments.filter { (1...normalizedCount).contains($0.value) }
        keyOwners = [:]
        windowKeys = [:]
        self.trees = trees.filter { (1...normalizedCount).contains($0.key) }
        self.layouts = layouts.filter { (1...normalizedCount).contains($0.key) }
    }

    public func workspace(for window: WindowID) -> Int {
        assignments[window] ?? 1
    }

    public mutating func register(_ window: WindowID) {
        guard assignments[window] == nil else { return }
        assignments[window] = 1
    }

    public mutating func register(_ window: ManagedWindow) {
        guard assignments[window.id] == nil else { return }
        let exactAssignment = keyAssignments[window.persistentKey]
        let titleKey = WindowKey(bundleIdentifier: window.bundleIdentifier, title: window.title, processID: window.processID)
        let legacyKey = WindowKey(bundleIdentifier: window.bundleIdentifier, title: window.title)
        let key = window.persistentKey
        assignments[window.id] = exactAssignment ?? keyAssignments[titleKey] ?? keyAssignments[legacyKey] ?? 1
        windowKeys[window.id] = key
        keyOwners[key] = window.id
    }

    /// `restorePersisted` is for windows that already existed when the daemon
    /// started or reloaded. Windows created while running always open on
    /// `defaultWorkspace` unless a rule says otherwise.
    public mutating func register(_ window: ManagedWindow, rules: [WindowRule], defaultWorkspace: Int = 1, restorePersisted: Bool = true) {
        guard assignments[window.id] == nil else { return }
        let rule = rules.first { $0.matches(bundleIdentifier: window.bundleIdentifier, title: window.title, subrole: window.subrole) }
        let key = window.persistentKey
        let hasDifferentOwner = keyOwners[key].map { $0 != window.id } ?? false
        let canRestore = restorePersisted && !hasDifferentOwner
        let persistedWorkspace = canRestore ? keyAssignments[key] : nil
        let workspace = rule?.workspace ?? persistedWorkspace ?? defaultWorkspace
        assignments[window.id] = isValid(workspace) ? workspace : 1
        windowKeys[window.id] = key
        if !hasDifferentOwner {
            keyAssignments[key] = assignments[window.id]
        }
        keyOwners[key] = window.id
    }

    public var persistedAssignments: [WindowKey: Int] {
        keyAssignments.filter { keyOwners[$0.key] != nil }
    }

    public var persistedTrees: [Int: WindowTree] { trees }
    public var persistedLayouts: [Int: LayoutKind] { layouts }
    public func layout(for workspace: Int, default defaultLayout: LayoutKind = .bsp) -> LayoutKind { layouts[workspace] ?? defaultLayout }
    public mutating func setLayout(_ layout: LayoutKind, for workspace: Int) {
        guard isValid(workspace) else { return }
        layouts[workspace] = layout
    }

    public func storedLayoutTree(for workspace: Int) -> WindowTree? { trees[workspace] }

    /// Only used to shape the grid when no real frame is known.
    public static let referenceFrame = Frame(x: 0, y: 0, width: 1600, height: 1000)

    public func layoutTree(for windows: [WindowID], in workspace: Int, frame: Frame = WorkspaceManager.referenceFrame) -> WindowTree? {
        guard isValid(workspace), !windows.isEmpty else { return nil }
        return reconciledTree(for: windows, in: workspace, frame: frame)
    }

    public mutating func validatedLayoutTree(for windows: [WindowID], in workspace: Int, frame: Frame = WorkspaceManager.referenceFrame) -> WindowTree? {
        guard isValid(workspace) else { return nil }
        guard !windows.isEmpty else {
            trees.removeValue(forKey: workspace)
            return nil
        }
        let tree = reconciledTree(for: windows, in: workspace, frame: frame)
        trees[workspace] = tree
        staleGrids.remove(workspace)
        return tree
    }

    /// Whenever windows open or close the workspace becomes a fresh grid,
    /// keeping the windows' order with new ones last; manual resizes and
    /// swaps last until then. A corrupt tree is rebuilt.
    private func reconciledTree(for windows: [WindowID], in workspace: Int, frame: Frame) -> WindowTree? {
        let windowSet = Set(windows)
        let stored = trees[workspace].flatMap { $0.leafCount == $0.windowIDs.count ? $0 : nil }
        let kept = stored?.leafOrder.filter { windowSet.contains($0) } ?? []
        var order = kept
        for id in windows where !order.contains(id) && groups.leader(of: id).map({ $0 == id }) ?? true { order.append(id) }
        let isUnchanged = !staleGrids.contains(workspace) && stored?.windowIDs == Set(order)
        if isUnchanged, let stored, fitsItsWindows(stored, in: frame) { return stored }
        return WindowTree.grid(for: order, in: frame, minimumSizes: minimumSizes)
    }

    public func hasMinimumSize(_ window: WindowID) -> Bool { minimumSizes[window] != nil }

    /// No hand resize may leave a tile smaller than this.
    private static let smallestTile = Size(width: 100, height: 100)

    /// Every tile is at least as large as its window's minimum and the smallest tile.
    private func fitsItsWindows(_ tree: WindowTree, in frame: Frame) -> Bool {
        tree.frames(in: frame).allSatisfy { id, tile in
            let minimum = minimumSizes[id] ?? Size(width: 0, height: 0)
            let isWideEnough = tile.width + 1 >= max(minimum.width, Self.smallestTile.width)
            let isTallEnough = tile.height + 1 >= max(minimum.height, Self.smallestTile.height)
            return isWideEnough && isTallEnough
        }
    }

    /// Remembers that `window` cannot be smaller than `size`; true when that is
    /// new, and its workspace is laid out again on the next pass.
    public mutating func recordMinimumSize(_ size: Size, for window: WindowID) -> Bool {
        let known = minimumSizes[window] ?? Size(width: 0, height: 0)
        // Frames come back with fractions of a point; growth below one point is noise.
        let isWider = size.width > known.width + 1
        let isTaller = size.height > known.height + 1
        guard isWider || isTaller else { return false }
        minimumSizes[window] = Size(width: max(known.width, size.width), height: max(known.height, size.height))
        if let workspace = assignments[window] { staleGrids.insert(workspace) }
        return true
    }

    public mutating func setLayoutTree(_ tree: WindowTree?, for workspace: Int) {
        guard isValid(workspace) else { return }
        if let tree { trees[workspace] = tree } else { trees.removeValue(forKey: workspace) }
    }

    public mutating func swap(_ first: WindowID, _ second: WindowID, in workspace: Int) -> Bool {
        guard isValid(workspace), let tree = trees[workspace], tree.windowIDs.contains(first), tree.windowIDs.contains(second) else { return false }
        trees[workspace] = tree.swapped(first, second)
        return true
    }

    // MARK: - Tab groups

    public func group(containing id: WindowID) -> [WindowID]? { groups.members(ofGroupContaining: id) }
    public func activeMember(ofGroupContaining id: WindowID) -> WindowID? { groups.activeMember(ofGroupContaining: id) }

    /// Leaves for the layout: ungrouped windows plus one leader per group.
    public func layoutLeaves(for windows: [WindowID]) -> [WindowID] {
        windows.filter { id in groups.leader(of: id).map { $0 == id } ?? true }
    }

    /// Grouped windows that are not their group's active member.
    public func hiddenGroupMembers(among windows: [WindowID]) -> Set<WindowID> {
        Set(windows.filter { groups.leader(of: $0) != nil && groups.activeMember(ofGroupContaining: $0) != $0 })
    }

    /// Creates a group around a lone window, or dissolves the group the window is in.
    @discardableResult
    public mutating func toggleGroup(containing id: WindowID, in workspace: Int) -> Bool {
        guard isValid(workspace), assignments[id] == workspace else { return false }
        guard let leader = groups.leader(of: id) else {
            groups.create(with: id)
            return true
        }
        let members = groups.dissolve(leader)
        var tree = trees[workspace]
        for member in members where member != leader {
            tree = tree?.inserting(member, at: leader, direction: .vertical) ?? .leaf(member)
        }
        trees[workspace] = tree
        return true
    }

    /// Moves `id` into the group holding `target`, creating it when needed, and shows `id`.
    @discardableResult
    public mutating func addToGroup(_ id: WindowID, containing target: WindowID, in workspace: Int) -> Bool {
        guard isValid(workspace), id != target, assignments[id] == workspace, assignments[target] == workspace, groups.leader(of: id) == nil else { return false }
        if groups.leader(of: target) == nil { groups.create(with: target) }
        guard let leader = groups.leader(of: target) else { return false }
        groups.add(id, to: leader)
        trees[workspace] = trees[workspace]?.removing(id)
        return true
    }

    /// Takes a window out of its group into a tile of its own next to the group.
    @discardableResult
    public mutating func leaveGroup(_ id: WindowID, in workspace: Int) -> Bool {
        guard isValid(workspace), let leader = groups.leader(of: id) else { return false }
        if let promoted = groups.remove(id) {
            trees[workspace] = trees[workspace]?.swapped(id, promoted)
            trees[workspace] = trees[workspace]?.inserting(id, at: promoted, direction: .vertical)
        } else if leader != id {
            trees[workspace] = trees[workspace]?.inserting(id, at: leader, direction: .vertical)
        }
        return true
    }

    /// Shows the next or previous member; returns the window to focus.
    public mutating func cycleGroup(containing id: WindowID, forward: Bool) -> WindowID? {
        groups.cycle(id, forward: forward)
    }

    public mutating func showGroupMember(_ id: WindowID) {
        groups.setActive(id)
    }

    public mutating func adjustSplitRatio(containing window: WindowID, by delta: Double, in workspace: Int) -> Bool {
        guard isValid(workspace), let tree = trees[workspace], tree.windowIDs.contains(window) else { return false }
        trees[workspace] = tree.adjustingRatio(for: window, by: delta)
        return true
    }

    public mutating func resizeTiled(_ window: WindowID, deltaX: Double, deltaY: Double, frame: Frame, in workspace: Int) -> Bool {
        guard isValid(workspace), let tree = trees[workspace], tree.windowIDs.contains(window) else { return false }
        trees[workspace] = tree.resizing(window, deltaX: deltaX, deltaY: deltaY, in: frame)
        return true
    }

    /// Adopts the frame the user gave a tiled window by dragging its edges.
    public mutating func fitTiled(_ window: WindowID, to target: Frame, frame: Frame, in workspace: Int) -> Bool {
        guard isValid(workspace), let tree = trees[workspace], tree.windowIDs.contains(window) else { return false }
        let fitted = tree.fitting(window, to: target, in: frame)
        guard fitted != tree, fitsItsWindows(fitted, in: frame) else { return false }
        trees[workspace] = fitted
        return true
    }

    public mutating func toggleSplit(containing window: WindowID, in workspace: Int) -> Bool {
        guard isValid(workspace), let tree = trees[workspace], tree.windowIDs.contains(window) else { return false }
        trees[workspace] = tree.togglingSplit(containing: window)
        return true
    }

    public func windows(in workspace: Int) -> [WindowID] {
        guard isValid(workspace) else { return [] }
        return assignments
            .filter { self.workspace(for: $0.key) == workspace }
            .map(\.key)
            .sorted { $0.rawValue < $1.rawValue }
    }

    public func isValid(_ workspace: Int) -> Bool {
        (1...count).contains(workspace)
    }

    public mutating func assign(_ window: WindowID, to workspace: Int) {
        guard isValid(workspace) else { return }
        assignments[window] = workspace
    }

    public mutating func assign(_ window: ManagedWindow, to workspace: Int) {
        guard isValid(workspace) else { return }
        assignments[window.id] = workspace
        keyAssignments[window.persistentKey] = workspace
    }

    public mutating func remove(_ windowID: WindowID) {
        if let workspace = assignments[windowID] {
            if let promoted = groups.remove(windowID) {
                trees[workspace] = trees[workspace]?.swapped(windowID, promoted)
            } else {
                trees[workspace] = trees[workspace]?.removing(windowID)
                staleGrids.insert(workspace)
            }
        }
        assignments.removeValue(forKey: windowID)
        minimumSizes.removeValue(forKey: windowID)
        guard let key = windowKeys.removeValue(forKey: windowID), keyOwners[key] == windowID else { return }
        keyOwners.removeValue(forKey: key)
        keyAssignments.removeValue(forKey: key)
    }

    /// Remembers the window the user last focused in its workspace so switching
    /// back can return keyboard focus there.
    public mutating func recordFocus(_ window: WindowID) {
        guard let workspace = assignments[window] else { return }
        lastFocused[workspace] = window
    }

    public func lastFocusedWindow(in workspace: Int) -> WindowID? {
        guard let window = lastFocused[workspace], assignments[window] == workspace else { return nil }
        return window
    }

    public mutating func activate(_ workspace: Int) {
        guard isValid(workspace), workspace != activeWorkspace else { return }
        previousWorkspace = activeWorkspace
        activeWorkspace = workspace
    }

}

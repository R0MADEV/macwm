public struct WorkspaceManager: Sendable {
    public let count: Int
    public private(set) var activeWorkspace: Int
    private var assignments: [WindowID: Int]
    private var keyAssignments: [WindowKey: Int]
    private var keyOwners: [WindowKey: WindowID]
    private var windowKeys: [WindowID: WindowKey]
    private var trees: [Int: WindowTree]
    private var layouts: [Int: LayoutKind]
    private var lastFocused: [Int: WindowID] = [:]
    private var preselections: [Int: SplitDirection] = [:]

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

    /// Only used to pick automatic split directions when no real frame is known.
    public static let referenceFrame = Frame(x: 0, y: 0, width: 1600, height: 1000)

    /// The next window opened in the workspace splits its target in this direction.
    public mutating func preselect(_ direction: SplitDirection, in workspace: Int) {
        guard isValid(workspace) else { return }
        preselections[workspace] = direction
    }

    public func layoutTree(for windows: [WindowID], in workspace: Int, frame: Frame = WorkspaceManager.referenceFrame) -> WindowTree? {
        guard isValid(workspace), !windows.isEmpty else { return nil }
        return reconciledTree(for: windows, in: workspace, frame: frame).tree
    }

    public mutating func validatedLayoutTree(for windows: [WindowID], in workspace: Int, frame: Frame = WorkspaceManager.referenceFrame) -> WindowTree? {
        guard isValid(workspace) else { return nil }
        guard !windows.isEmpty else {
            trees.removeValue(forKey: workspace)
            return nil
        }
        let result = reconciledTree(for: windows, in: workspace, frame: frame)
        trees[workspace] = result.tree
        if result.usedPreselection { preselections.removeValue(forKey: workspace) }
        return result.tree
    }

    /// Keeps the stored structure like Hyprland's dwindle layout: closed windows
    /// collapse their split and new windows split the last focused leaf, or the
    /// last leaf when nothing was focused. A missing or corrupt tree is rebuilt.
    private func reconciledTree(for windows: [WindowID], in workspace: Int, frame: Frame) -> (tree: WindowTree?, usedPreselection: Bool) {
        let windowSet = Set(windows)
        let hasDuplicates = windowSet.count != windows.count
        guard !hasDuplicates, let stored = trees[workspace], stored.leafCount == stored.windowIDs.count else {
            return (BSPLayout.tree(for: windows), false)
        }
        var tree: WindowTree? = stored
        for id in stored.windowIDs where !windowSet.contains(id) { tree = tree?.removing(id) }
        var preselection = preselections[workspace]
        var usedPreselection = false
        for id in windows where !stored.windowIDs.contains(id) {
            guard let current = tree else {
                tree = .leaf(id)
                continue
            }
            let focused = lastFocused[workspace].flatMap { current.windowIDs.contains($0) ? $0 : nil }
            let target = focused ?? current.lastLeaf
            let direction = preselection ?? current.automaticSplitDirection(for: target, in: frame)
            usedPreselection = usedPreselection || preselection != nil
            preselection = nil
            tree = current.inserting(id, at: target, direction: direction)
        }
        return (tree, usedPreselection)
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
        assignments.removeValue(forKey: windowID)
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
        guard isValid(workspace) else { return }
        activeWorkspace = workspace
    }

}

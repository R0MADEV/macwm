/// Tab groups, Hyprland's `togglegroup`: several windows share one tile and
/// only the active member is visible. The group is represented in the BSP
/// tree by its leader leaf; the other members leave the tree while grouped.
struct WindowGroups: Equatable, Sendable {
    private var members: [WindowID: [WindowID]] = [:]
    private var leaders: [WindowID: WindowID] = [:]
    private var active: [WindowID: WindowID] = [:]

    func leader(of id: WindowID) -> WindowID? { leaders[id] }

    func members(ofGroupContaining id: WindowID) -> [WindowID]? {
        leaders[id].flatMap { members[$0] }
    }

    func activeMember(ofGroupContaining id: WindowID) -> WindowID? {
        leaders[id].flatMap { active[$0] }
    }

    mutating func create(with id: WindowID) {
        members[id] = [id]
        leaders[id] = id
        active[id] = id
    }

    mutating func add(_ id: WindowID, to leader: WindowID) {
        members[leader, default: [leader]].append(id)
        leaders[id] = leader
        active[leader] = id
    }

    /// Drops a member; returns the group's new leader when the leader itself left.
    @discardableResult
    mutating func remove(_ id: WindowID) -> WindowID? {
        guard let leader = leaders.removeValue(forKey: id) else { return nil }
        let previousActive = active.removeValue(forKey: leader)
        let remaining = (members.removeValue(forKey: leader) ?? []).filter { $0 != id }
        guard let promoted = remaining.first else { return nil }
        members[promoted] = remaining
        for member in remaining { leaders[member] = promoted }
        active[promoted] = previousActive.flatMap { remaining.contains($0) ? $0 : nil } ?? promoted
        return leader == id ? promoted : nil
    }

    mutating func dissolve(_ leader: WindowID) -> [WindowID] {
        let all = members.removeValue(forKey: leader) ?? []
        for member in all { leaders.removeValue(forKey: member) }
        active.removeValue(forKey: leader)
        return all
    }

    mutating func cycle(_ id: WindowID, forward: Bool) -> WindowID? {
        guard let leader = leaders[id], let all = members[leader], let current = active[leader], let index = all.firstIndex(of: current) else { return nil }
        let next = all[(index + (forward ? 1 : all.count - 1)) % all.count]
        active[leader] = next
        return next
    }

    mutating func setActive(_ id: WindowID) {
        guard let leader = leaders[id] else { return }
        active[leader] = id
    }
}

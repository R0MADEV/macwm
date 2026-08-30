public struct EventCoalescer<Key: Hashable & Sendable>: Sendable {
    private var pending: Set<Key> = []

    public init() {}

    public mutating func enqueue(_ key: Key) -> Bool {
        pending.insert(key).inserted
    }

    @discardableResult
    public mutating func consume(_ key: Key) -> Bool {
        pending.remove(key) != nil
    }
}

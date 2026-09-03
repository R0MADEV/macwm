/// Keeps a key visible for a couple of misses before treating it as gone, so
/// a single bad read (a locked database, a torn log line, a slow process
/// scan) does not blink a status pill off and back on a moment later.
public struct FlickerGuard {
    private var missStreak: [String: Int] = [:]
    private let missesToDrop: Int

    public init(missesToDrop: Int = 2) {
        self.missesToDrop = missesToDrop
    }

    /// Returns the keys to keep showing this tick, given who was actually observed.
    public mutating func observe(_ present: Set<String>) -> Set<String> {
        for key in Set(missStreak.keys).union(present) {
            missStreak[key] = present.contains(key) ? 0 : missStreak[key, default: 0] + 1
        }
        missStreak = missStreak.filter { $0.value < missesToDrop }
        return Set(missStreak.keys)
    }
}

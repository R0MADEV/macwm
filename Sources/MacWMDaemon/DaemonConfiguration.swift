import Foundation
import MacWMCore

final class DaemonConfiguration: @unchecked Sendable {
    var value: Config

    init(_ value: Config) {
        self.value = value
    }
}

/// Keybind engine shared between the hotkey tap thread and the main thread.
final class DaemonKeybinds: @unchecked Sendable {
    private let lock = NSLock()
    private var engine: KeybindEngine

    init(_ engine: KeybindEngine) {
        self.engine = engine
    }

    var mode: String { lock.withLock { engine.mode } }

    func handle(_ press: KeyBinding) -> KeybindEngine.Resolution {
        lock.withLock { engine.handle(press) }
    }

    func enter(mode: String) {
        lock.withLock { engine.enter(mode: mode) }
    }

    func replace(_ engine: KeybindEngine) {
        lock.withLock { self.engine = engine }
    }
}

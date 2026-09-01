import AppKit
import CoreGraphics
import MacWMCore

/// Feeds every key press to the keybind engine and dispatches the resolved
/// commands to the main thread.
final class HotkeyManager: @unchecked Sendable {
    private var tap: EventTap?
    private let handler: (Command) -> Void
    private let keybinds: DaemonKeybinds

    init?(keybinds: DaemonKeybinds, handler: @escaping (Command) -> Void) {
        self.handler = handler
        self.keybinds = keybinds
        let keyDownMask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let tap = EventTap(name: "macwm.hotkeys", mask: keyDownMask, callback: { [weak self] type, event in
            guard type == .keyDown, let self else { return Unmanaged.passUnretained(event) }
            return self.handle(event)
        }) else { return nil }
        self.tap = tap
    }

    private func handle(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let arrivedAt = DispatchTime.now().uptimeNanoseconds
        defer { Self.reportIfSlow(event: event, arrivedAt: arrivedAt) }
        let press = KeyBinding(keyCode: event.getIntegerValueField(.keyboardEventKeycode), modifiers: EventModifiers.modifiers(of: event.flags))
        switch keybinds.handle(press) {
        case .unbound:
            return Unmanaged.passUnretained(event)
        case .consumed:
            // A mode switch happened on this thread; let main publish the new mode.
            let mode = keybinds.mode
            DispatchQueue.main.async { [weak self] in
                self?.handler(.mode(mode))
            }
            return nil
        case let .command(command):
            DispatchQueue.main.async { [weak self] in
                self?.handler(command)
            }
            return nil
        }
    }

    /// Diagnostics for keyboard lag: how long the event waited before reaching
    /// the tap and how long the tap itself took. Normal values are well under a
    /// millisecond each.
    private static func reportIfSlow(event: CGEvent, arrivedAt: UInt64) {
        let deliveryMs = Double(arrivedAt &- event.timestamp) / 1_000_000
        let callbackMs = Double(DispatchTime.now().uptimeNanoseconds &- arrivedAt) / 1_000_000
        let isSlow = deliveryMs > 20 || callbackMs > 5
        guard isSlow else { return }
        fputs("macwm: slow key event: delivery \(Int(deliveryMs)) ms, tap \(String(format: "%.2f", callbackMs)) ms\n", stderr)
    }
}

enum EventModifiers {
    static func modifiers(of flags: CGEventFlags) -> Set<Modifier> {
        var modifiers: Set<Modifier> = []
        if flags.contains(.maskShift) { modifiers.insert(.shift) }
        if flags.contains(.maskControl) { modifiers.insert(.ctrl) }
        if flags.contains(.maskAlternate) { modifiers.insert(.alt) }
        if flags.contains(.maskCommand) { modifiers.insert(.cmd) }
        return modifiers
    }
}

import AppKit
import CoreGraphics
import MacWMCore

/// Global keyboard tap that feeds every key press to the keybind engine and
/// dispatches the resolved commands to the main thread.
final class HotkeyManager: @unchecked Sendable {
    private var eventTap: CFMachPort? = nil
    private var runLoopSource: CFRunLoopSource? = nil
    private var tapRunLoop: CFRunLoop? = nil
    private let handler: (Command) -> Void
    private let keybinds: DaemonKeybinds

    init?(keybinds: DaemonKeybinds, handler: @escaping (Command) -> Void) {
        self.handler = handler
        self.keybinds = keybinds
        let keyDownMask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: keyDownMask,
            callback: macwmHotkeyCallback,
            userInfo: context
        ) else { return nil }

        self.eventTap = eventTap
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0) else { return nil }
        self.runLoopSource = source
        startTapThread()
    }

    deinit {
        guard let eventTap else { return }
        CGEvent.tapEnable(tap: eventTap, enable: false)
        guard let tapRunLoop, let runLoopSource else { return }
        CFRunLoopRemoveSource(tapRunLoop, runLoopSource, .commonModes)
        CFRunLoopStop(tapRunLoop)
    }

    /// The tap is active and sits in front of every key press in the session,
    /// so it must never wait on the main thread, which blocks on Accessibility
    /// calls to busy applications. Matching only dispatches to main and returns.
    private func startTapThread() {
        let thread = Thread { [self] in
            guard let eventTap, let runLoopSource else { return }
            tapRunLoop = CFRunLoopGetCurrent()
            CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            CGEvent.tapEnable(tap: eventTap, enable: true)
            fputs("macwm: hotkey tap listening on thread \(Thread.current.name ?? "unnamed")\n", stderr)
            CFRunLoopRun()
            fputs("macwm: hotkey tap thread exited\n", stderr)
        }
        thread.name = "macwm.hotkeys"
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    fileprivate func handle(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let arrivedAt = DispatchTime.now().uptimeNanoseconds
        defer { Self.reportIfSlow(event: event, arrivedAt: arrivedAt) }
        let press = KeyBinding(keyCode: event.getIntegerValueField(.keyboardEventKeycode), modifiers: Self.modifiers(of: event.flags))
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

    fileprivate func enable() {
        guard let eventTap else { return }
        CGEvent.tapEnable(tap: eventTap, enable: true)
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

    private static func modifiers(of flags: CGEventFlags) -> Set<Modifier> {
        var modifiers: Set<Modifier> = []
        if flags.contains(.maskShift) { modifiers.insert(.shift) }
        if flags.contains(.maskControl) { modifiers.insert(.ctrl) }
        if flags.contains(.maskAlternate) { modifiers.insert(.alt) }
        if flags.contains(.maskCommand) { modifiers.insert(.cmd) }
        return modifiers
    }
}

private func macwmHotkeyCallback(
    _ proxy: CGEventTapProxy,
    _ type: CGEventType,
    _ event: CGEvent,
    _ userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let manager = Unmanaged<HotkeyManager>.fromOpaque(userInfo).takeUnretainedValue()
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        manager.enable()
        return Unmanaged.passUnretained(event)
    }
    guard type == .keyDown else { return Unmanaged.passUnretained(event) }
    return manager.handle(event)
}

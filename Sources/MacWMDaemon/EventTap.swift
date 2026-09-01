import AppKit
import CoreGraphics

/// An active session event tap serviced on its own user-interactive thread.
/// Taps sit in front of every matching event in the session, so their
/// callbacks must never wait on the main thread, which blocks on
/// Accessibility calls to busy applications.
final class EventTap: @unchecked Sendable {
    private var tap: CFMachPort? = nil
    private var source: CFRunLoopSource? = nil
    private var runLoop: CFRunLoop? = nil
    private let name: String
    private let callback: (CGEventType, CGEvent) -> Unmanaged<CGEvent>?

    init?(name: String, mask: CGEventMask, callback: @escaping (CGEventType, CGEvent) -> Unmanaged<CGEvent>?) {
        self.name = name
        self.callback = callback
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: macwmEventTapCallback,
            userInfo: context
        ) else { return nil }
        self.tap = tap
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else { return nil }
        self.source = source
        startThread()
    }

    deinit {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        guard let runLoop, let source else { return }
        CFRunLoopRemoveSource(runLoop, source, .commonModes)
        CFRunLoopStop(runLoop)
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let wasDisabled = type == .tapDisabledByTimeout || type == .tapDisabledByUserInput
        if wasDisabled {
            fputs("macwm: event tap \(name) was disabled by macOS; re-enabling\n", stderr)
            enable()
            return Unmanaged.passUnretained(event)
        }
        return callback(type, event)
    }

    private func enable() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func startThread() {
        let thread = Thread { [self] in
            guard let tap, let source else { return }
            runLoop = CFRunLoopGetCurrent()
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            fputs("macwm: event tap \(name) listening on its own thread\n", stderr)
            CFRunLoopRun()
            fputs("macwm: event tap \(name) thread exited\n", stderr)
        }
        thread.name = name
        thread.qualityOfService = .userInteractive
        thread.start()
    }
}

private func macwmEventTapCallback(
    _ proxy: CGEventTapProxy,
    _ type: CGEventType,
    _ event: CGEvent,
    _ userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<EventTap>.fromOpaque(userInfo).takeUnretainedValue()
    return tap.handle(type: type, event: event)
}

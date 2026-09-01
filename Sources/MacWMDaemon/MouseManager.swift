import AppKit
import CoreGraphics
import Foundation
import MacWMCore

/// Floating windows of the active workspace that the mouse may grab, shared
/// between the main thread, which publishes them after every layout pass, and
/// the mouse tap thread, which hit-tests them.
final class MouseTargets: @unchecked Sendable {
    private let lock = NSLock()
    private var floatingWindows: [WindowID: ManagedWindow] = [:]

    func update(_ windows: [ManagedWindow]) {
        lock.withLock { floatingWindows = Dictionary(uniqueKeysWithValues: windows.map { ($0.id, $0) }) }
    }

    func window(withID id: WindowID) -> ManagedWindow? {
        lock.withLock { floatingWindows[id] }
    }
}

/// Option + left drag moves a floating window; Option + right drag resizes it
/// from its bottom-right corner. Everything else passes through untouched.
final class MouseManager: @unchecked Sendable {
    private var tap: EventTap?
    private let client: AXClient
    private let targets: MouseTargets
    private let onDragEnd: (WindowID, Frame) -> Void
    private var drag: (window: ManagedWindow, drag: MouseDrag)?

    init?(client: AXClient, targets: MouseTargets, onDragEnd: @escaping (WindowID, Frame) -> Void) {
        self.client = client
        self.targets = targets
        self.onDragEnd = onDragEnd
        let types: [CGEventType] = [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .rightMouseDown, .rightMouseDragged, .rightMouseUp]
        let mask = types.reduce(CGEventMask(0)) { $0 | CGEventMask(1 << $1.rawValue) }
        guard let tap = EventTap(name: "macwm.mouse", mask: mask, callback: { [weak self] type, event in
            guard let self else { return Unmanaged.passUnretained(event) }
            return self.handle(type: type, event: event)
        }) else { return nil }
        self.tap = tap
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        let location = event.location
        switch type {
        case .leftMouseDown, .rightMouseDown:
            guard event.flags.contains(.maskAlternate), drag == nil else { return pass }
            guard let id = client.windowID(at: location), let window = targets.window(withID: id),
                  let frame = client.currentFrame(for: window) else { return pass }
            let kind: MouseDrag.Kind = type == .leftMouseDown ? .move : .resize
            drag = (window, MouseDrag(kind: kind, startFrame: frame, startX: location.x, startY: location.y))
            return nil
        case .leftMouseDragged, .rightMouseDragged:
            guard let drag else { return pass }
            _ = client.setFrame(drag.drag.frame(atX: location.x, y: location.y), for: drag.window)
            return nil
        case .leftMouseUp, .rightMouseUp:
            guard let drag else { return pass }
            self.drag = nil
            let frame = drag.drag.frame(atX: location.x, y: location.y)
            _ = client.setFrame(frame, for: drag.window)
            let id = drag.window.id
            DispatchQueue.main.async { [onDragEnd] in onDragEnd(id, frame) }
            return nil
        default:
            return pass
        }
    }
}

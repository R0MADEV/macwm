import AppKit
import CoreGraphics
import Foundation
import MacWMCore

/// Visible windows of the active workspace that the mouse may grab, shared
/// between the main thread, which publishes them after every layout pass, and
/// the mouse tap thread, which hit-tests them.
final class MouseTargets: @unchecked Sendable {
    private let lock = NSLock()
    private var windows: [WindowID: ManagedWindow] = [:]

    func update(_ windows: [ManagedWindow]) {
        lock.withLock { self.windows = Dictionary(uniqueKeysWithValues: windows.map { ($0.id, $0) }) }
    }

    func window(withID id: WindowID) -> ManagedWindow? {
        lock.withLock { windows[id] }
    }
}

/// Option + left drag moves a floating window or, on a tiled one, swaps it
/// with the tiled window it is dropped on. Option + right drag resizes a
/// floating window from its bottom-right corner or, on a tiled one, moves the
/// splits around it. Everything else passes through untouched.
final class MouseManager: @unchecked Sendable {
    private enum Drag {
        case floating(ManagedWindow, MouseDrag)
        case tiledMove(ManagedWindow)
        case tiledResize(ManagedWindow, lastX: Double, lastY: Double, lastDispatch: UInt64)
    }

    private static let resizeDispatchIntervalNs: UInt64 = 33_000_000

    private var tap: EventTap?
    var isTrusted = true { didSet { isTrusted ? tap?.resume() : tap?.pause() } }
    private let client: AXClient
    private let targets: MouseTargets
    private let onFloatingDragEnd: (WindowID, Frame) -> Void
    private let onTiledResize: (WindowID, Double, Double) -> Void
    private let onTiledSwap: (WindowID, WindowID) -> Void
    private var drag: Drag?

    init?(
        client: AXClient,
        targets: MouseTargets,
        onFloatingDragEnd: @escaping (WindowID, Frame) -> Void,
        onTiledResize: @escaping (WindowID, Double, Double) -> Void,
        onTiledSwap: @escaping (WindowID, WindowID) -> Void
    ) {
        self.client = client
        self.targets = targets
        self.onFloatingDragEnd = onFloatingDragEnd
        self.onTiledResize = onTiledResize
        self.onTiledSwap = onTiledSwap
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
            guard let id = client.windowID(at: location), let window = targets.window(withID: id) else { return pass }
            let isLeftButton = type == .leftMouseDown
            if window.isTileable {
                drag = isLeftButton ? .tiledMove(window) : .tiledResize(window, lastX: location.x, lastY: location.y, lastDispatch: 0)
                return nil
            }
            guard let frame = client.currentFrame(for: window) else { return pass }
            drag = .floating(window, MouseDrag(kind: isLeftButton ? .move : .resize, startFrame: frame, startX: location.x, startY: location.y))
            return nil
        case .leftMouseDragged, .rightMouseDragged:
            guard let drag else { return pass }
            switch drag {
            case let .floating(window, mouseDrag):
                _ = client.setFrame(mouseDrag.frame(atX: location.x, y: location.y), for: window)
            case .tiledMove:
                break
            case let .tiledResize(window, lastX, lastY, lastDispatch):
                let now = DispatchTime.now().uptimeNanoseconds
                guard now &- lastDispatch >= Self.resizeDispatchIntervalNs else { break }
                dispatchTiledResize(window, deltaX: location.x - lastX, deltaY: location.y - lastY)
                self.drag = .tiledResize(window, lastX: location.x, lastY: location.y, lastDispatch: now)
            }
            return nil
        case .leftMouseUp, .rightMouseUp:
            guard let drag else { return pass }
            self.drag = nil
            switch drag {
            case let .floating(window, mouseDrag):
                let frame = mouseDrag.frame(atX: location.x, y: location.y)
                _ = client.setFrame(frame, for: window)
                DispatchQueue.main.async { [onFloatingDragEnd] in onFloatingDragEnd(window.id, frame) }
            case let .tiledMove(window):
                guard let targetID = client.windowID(at: location), targetID != window.id,
                      let target = targets.window(withID: targetID), target.isTileable else { break }
                DispatchQueue.main.async { [onTiledSwap] in onTiledSwap(window.id, targetID) }
            case let .tiledResize(window, lastX, lastY, _):
                dispatchTiledResize(window, deltaX: location.x - lastX, deltaY: location.y - lastY)
            }
            return nil
        default:
            return pass
        }
    }

    private func dispatchTiledResize(_ window: ManagedWindow, deltaX: Double, deltaY: Double) {
        guard deltaX != 0 || deltaY != 0 else { return }
        DispatchQueue.main.async { [onTiledResize] in onTiledResize(window.id, deltaX, deltaY) }
    }
}

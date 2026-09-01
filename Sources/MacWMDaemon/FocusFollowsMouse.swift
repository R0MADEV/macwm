import AppKit
import MacWMCore

/// Focuses the managed window under the cursor when the pointer comes to rest
/// over a different one. Polling the cursor from the main thread keeps mouse
/// events out of the tap and lets Accessibility hit tests block harmlessly.
final class FocusFollowsMouse: @unchecked Sendable {
    private let client: AXClient
    private let focus: (WindowID) -> Void
    private var timer: Timer?
    private var lastLocation = NSPoint.zero
    private var lastHitID: WindowID?

    init(client: AXClient, focus: @escaping (WindowID) -> Void) {
        self.client = client
        self.focus = focus
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != (timer != nil) else { return }
        timer?.invalidate()
        timer = nil
        lastHitID = nil
        guard enabled else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in self?.poll() }
    }

    private func poll() {
        let location = NSEvent.mouseLocation
        let isDraggingOrClicking = NSEvent.pressedMouseButtons != 0
        guard location != lastLocation, !isDraggingOrClicking else { return }
        lastLocation = location
        let accessibilityOriginY = NSScreen.screens.first?.frame.maxY ?? 0
        let point = CGPoint(x: location.x, y: accessibilityOriginY - location.y)
        guard let id = client.windowID(at: point), id != lastHitID else { return }
        lastHitID = id
        focus(id)
    }
}

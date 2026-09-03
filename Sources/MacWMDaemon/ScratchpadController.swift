import AppKit
import MacWMCore

/// Toggles one application's window like a drop-down terminal: launches the
/// application when needed, minimizes its window when visible and restores it
/// otherwise. Scratchpad applications are never tiled, parked or hidden by
/// workspace switches.
final class ScratchpadController: @unchecked Sendable {
    private let client: AXClient
    private let bundleIdentifier: String
    /// Share of the screen the window drops down over when shown; nil keeps its own size.
    private let screenShare: Double?

    init(client: AXClient, bundleIdentifier: String, screenShare: Double?) {
        self.client = client
        self.bundleIdentifier = bundleIdentifier
        self.screenShare = screenShare
    }

    func toggle() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            fputs("macwm: scratchpad application is not installed (\(bundleIdentifier))\n", stderr)
            return
        }
        guard let application = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first else {
            // Controllers are created per toggle, so the completion must keep
            // this instance alive until the application has launched.
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { application, error in
                guard error == nil, let application else { return }
                DispatchQueue.main.async { self.restore(application) }
            }
            return
        }
        if application.isHidden {
            restore(application)
            return
        }
        guard let window = client.windows(for: application).first else {
            application.activate(options: [.activateIgnoringOtherApps])
            return
        }
        // Quake style: bring it forward and frame it unless it is already the
        // frontmost window, in which case hide it.
        let isInFront = !client.isMinimized(window) && !application.isHidden && NSWorkspace.shared.frontmostApplication?.processIdentifier == application.processIdentifier
        if isInFront {
            _ = client.setHidden(true, for: window)
        } else {
            restore(application)
        }
    }

    private func restore(_ application: NSRunningApplication) {
        guard let window = client.windows(for: application).first else { return }
        application.unhide()
        guard client.setHidden(false, for: window) else { return }
        application.activate(options: [.activateIgnoringOtherApps])

        // Read the restored window again so the frame uses its current screen
        // instead of the pre-restore snapshot.
        guard let restoredWindow = client.windows(for: application).first, let element = client.element(for: restoredWindow) else { return }
        if let screenShare, let frame = dropDownFrame(for: restoredWindow, share: screenShare) {
            _ = client.setFrame(frame, for: restoredWindow)
        }
        _ = client.focus(element)
    }

    /// The whole screen at 100%; below that, the top part of the visible area,
    /// under the bar and the menu bar, like a drop-down terminal.
    private func dropDownFrame(for window: ManagedWindow, share: Double) -> Frame? {
        if share >= 100 { return client.screenFrame(for: window) }
        guard let visible = client.visibleScreenFrame(for: window) else { return nil }
        return Frame(x: visible.x, y: visible.y, width: visible.width, height: (visible.height * share / 100).rounded())
    }
}

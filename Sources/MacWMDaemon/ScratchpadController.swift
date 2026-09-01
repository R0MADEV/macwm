import AppKit
import MacWMCore

/// Toggles one application's window like a drop-down terminal: launches the
/// application when needed, minimizes its window when visible and restores it
/// otherwise. Scratchpad applications are never tiled, parked or hidden by
/// workspace switches.
final class ScratchpadController: @unchecked Sendable {
    private let client: AXClient
    private let bundleIdentifier: String
    private let fillsScreen: Bool

    init(client: AXClient, bundleIdentifier: String, fillsScreen: Bool) {
        self.client = client
        self.bundleIdentifier = bundleIdentifier
        self.fillsScreen = fillsScreen
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
        if client.isMinimized(window) {
            restore(application)
        } else {
            _ = client.setHidden(true, for: window)
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
        if fillsScreen, let frame = client.screenFrame(for: restoredWindow) {
            _ = client.setFrame(frame, for: restoredWindow)
        }
        _ = client.focus(element)
    }
}

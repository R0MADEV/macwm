import AppKit

final class TerminalController: @unchecked Sendable {
    private let client: AXClient
    private(set) var bundleIdentifier: String

    init(client: AXClient, bundleIdentifier: String) {
        self.client = client
        self.bundleIdentifier = bundleIdentifier
    }

    func update(bundleIdentifier: String) {
        self.bundleIdentifier = bundleIdentifier
    }

    func toggle() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            fputs("macwm: terminal application is not installed (\(bundleIdentifier))\n", stderr)
            return
        }
        guard let application = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first else {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { [weak self] application, error in
                guard let self, error == nil, let application else { return }
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

        // Read the restored window again so terminalFrame uses its current
        // screen instead of the pre-restore/minimized snapshot.
        guard let restoredWindow = client.windows(for: application).first,
              let frame = client.terminalFrame(for: restoredWindow),
              client.setFrame(frame, for: restoredWindow),
              let element = client.element(for: restoredWindow) else { return }
        _ = client.focus(element)
    }
}

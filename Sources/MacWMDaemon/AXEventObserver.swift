import ApplicationServices
import AppKit

final class AXEventObserver {
    enum Event {
        case windowCreated(AXUIElement)
        case windowDestroyed(AXUIElement)
        case focusedWindowChanged(AXUIElement)
        case windowVisibilityChanged(AXUIElement)
        case environmentChanged
    }

    private var observer: AXObserver?
    private let handler: (Event) -> Void

    init?(processID: pid_t, handler: @escaping (Event) -> Void) {
        self.handler = handler
        var createdObserver: AXObserver?
        guard AXObserverCreate(processID, Self.callback, &createdObserver) == .success,
              let createdObserver else { return nil }
        observer = createdObserver

        let application = AXUIElementCreateApplication(processID)
        let notifications: [String] = [
            kAXWindowCreatedNotification,
            kAXUIElementDestroyedNotification,
            kAXFocusedWindowChangedNotification,
            kAXWindowMiniaturizedNotification,
            kAXWindowDeminiaturizedNotification
        ]

        for notification in notifications {
            guard AXObserverAddNotification(createdObserver, application, notification as CFString, Unmanaged.passUnretained(self).toOpaque()) == .success else {
                continue
            }
        }

        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(createdObserver),
            .defaultMode
        )
    }

    deinit {
        guard let observer else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
    }

    private static let callback: AXObserverCallback = { _, element, notification, refcon in
        guard let refcon else { return }
        let observer = Unmanaged<AXEventObserver>.fromOpaque(refcon).takeUnretainedValue()
        observer.handle(element: element, notification: notification)
    }

    private func handle(element: AXUIElement, notification: CFString) {
        switch notification as String {
        case kAXWindowCreatedNotification:
            handler(.windowCreated(element))
        case kAXUIElementDestroyedNotification:
            handler(.windowDestroyed(element))
        case kAXFocusedWindowChangedNotification:
            handler(.focusedWindowChanged(element))
        case kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification:
            handler(.windowVisibilityChanged(element))
        default:
            return
        }
    }
}

/// Owns AX observers for the current application set and reconnects them when
/// macOS recreates an application or resumes Accessibility services.
final class AXObserverRegistry: @unchecked Sendable {
    private var observers: [pid_t: AXEventObserver] = [:]
    private var notificationTokens: [NSObjectProtocol] = []
    private var pendingRescan = false
    private let handler: (pid_t, AXEventObserver.Event) -> Void

    init(handler: @escaping (pid_t, AXEventObserver.Event) -> Void) {
        self.handler = handler
    }

    func start() {
        let center = NSWorkspace.shared.notificationCenter
        let names: [Notification.Name] = [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didHideApplicationNotification,
            NSWorkspace.didUnhideApplicationNotification,
            NSWorkspace.didWakeNotification,
            NSWorkspace.willSleepNotification
        ]
        for name in names {
            notificationTokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                self?.workspaceChanged(note)
            })
        }
        notificationTokens.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.scheduleRescan() })
        for application in NSWorkspace.shared.runningApplications where !application.isTerminated {
            connect(application)
        }
    }

    deinit {
        for token in notificationTokens { NSWorkspace.shared.notificationCenter.removeObserver(token); NotificationCenter.default.removeObserver(token) }
    }

    private func workspaceChanged(_ note: Notification) {
        if let application = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
            if note.name == NSWorkspace.didLaunchApplicationNotification {
                connect(application)
                // Many apps show their first window well after launching; look again.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.scheduleRescan() }
            }
            if note.name == NSWorkspace.didTerminateApplicationNotification { observers.removeValue(forKey: application.processIdentifier) }
        }
        scheduleRescan()
    }

    private func connect(_ application: NSRunningApplication) {
        let pid = application.processIdentifier
        guard observers[pid] == nil else { return }
        observers[pid] = AXEventObserver(processID: pid) { [weak self] event in
            self?.handler(pid, event)
        }
    }

    private func scheduleRescan() {
        guard !pendingRescan else { return }
        pendingRescan = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.pendingRescan = false
            self.handler(0, .environmentChanged)
        }
    }
}

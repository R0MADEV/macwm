import Foundation
import ApplicationServices
import AppKit
import MacWMCore
import MacWMTransport

let permissionOptions = [
    "AXTrustedCheckOptionPrompt": true
] as CFDictionary

guard AXIsProcessTrustedWithOptions(permissionOptions) else {
    fputs("macwm: Accessibility permission is required. Enable it in System Settings > Privacy & Security > Accessibility.\n", stderr)
    exit(EXIT_FAILURE)
}

// The daemon fronts every key press and reacts to focus changes, so macOS must
// never App Nap it: the first key after an idle period would pay the wake-up.
let latencyActivity = ProcessInfo.processInfo.beginActivity(
    options: [.userInitiatedAllowingIdleSystemSleep, .latencyCritical],
    reason: "macwm global hotkeys and window management"
)
// The daemon owns windows of its own, the focus border, so it runs as an
// accessory application: no Dock icon, and never managed by itself.
let application = NSApplication.shared
application.setActivationPolicy(.accessory)
let runtimeConfiguration = DaemonConfiguration(ConfigLoader.load())
let focusBorder = FocusBorder()
let groupTabBars = GroupTabBars { id in
    workspaces.value.showGroupMember(id)
    applyTiling(client: client, store: &store, config: runtimeConfiguration.value, workspaces: &workspaces.value, maximizedFrames: maximizedFrames, force: true)
    guard let window = store.windows.first(where: { $0.id == id }) else { return }
    client.focus(window)
    store.setFocusedWindow(id)
    workspaces.value.recordFocus(id)
    updateFocusBorder(store: store, config: runtimeConfiguration.value, workspaces: workspaces.value)
}
let keybinds = DaemonKeybinds(runtimeConfiguration.value.keybindEngine(keyCodes: KeyboardLayout.currentTable()))
let keyboardLayoutObserver = DistributedNotificationCenter.default().addObserver(forName: KeyboardLayout.changedNotification, object: nil, queue: .main) { _ in
    keybinds.replace(runtimeConfiguration.value.keybindEngine(keyCodes: KeyboardLayout.currentTable()))
    print("macwm: keyboard layout changed; hotkeys rebuilt")
}
let mouseTargets = MouseTargets()
let client = AXClient(rules: runtimeConfiguration.value.rules, barPosition: runtimeConfiguration.value.barPosition, barThickness: runtimeConfiguration.value.barThickness)
let workspacePersistence = WorkspacePersistence()
let persistedState = workspacePersistence.loadState()
let workspaces = DaemonWorkspaces(assignments: persistedState.assignments, activeWorkspace: persistedState.activeWorkspace, trees: persistedState.trees ?? [:], layouts: persistedState.layouts ?? [:])
let layoutGuard = LayoutGuard()
var store = WindowStore()
var maximizedFrames: [WindowID: Frame] = [:]
let parkedFrames = ParkedFrames()
let socketPath = "/tmp/macwm.sock"
let eventsSocketPath = "/tmp/macwm-events.sock"
let events = UnixSocketBroadcaster(path: eventsSocketPath)
if events == nil { fputs("macwm: unable to open the events socket at \(eventsSocketPath)\n", stderr) }
let stateNotification = Notification.Name("com.macwm.stateChanged")

for window in managedWindows(client) {
    store.upsert(window)
    if persistedState.floating?[window.persistentKey] == true { store.setFloating(true, for: window.id) }
    workspaces.value.register(window, rules: runtimeConfiguration.value.rules, defaultWorkspace: workspaces.value.activeWorkspace)
    if let rule = client.rule(for: window) { client.apply(rule: rule, to: window) }
}

if let focusedWindow = client.focusedWindow(), isManaged(focusedWindow) {
    store.upsert(focusedWindow)
    if persistedState.floating?[focusedWindow.persistentKey] == true { store.setFloating(true, for: focusedWindow.id) }
    workspaces.value.register(focusedWindow, rules: runtimeConfiguration.value.rules, defaultWorkspace: workspaces.value.activeWorkspace)
    store.setFocusedWindow(focusedWindow.id)
    workspaces.value.recordFocus(focusedWindow.id)
}

for window in store.windows {
    guard let frame = persistedState.maximized?[window.persistentKey] else { continue }
    maximizedFrames[window.id] = frame
    _ = client.setFrame(window.frame ?? frame, for: window)
}

print("macwm: tracking \(store.windows.count) windows")
if let focusedWindow = store.focusedWindow {
    print("macwm: focused \(focusedWindow.appName) - \(focusedWindow.title)")
}
showWorkspaceWindows(workspaces.value.activeWorkspace, client: client, store: &store, workspaces: workspaces.value, maximizedFrames: maximizedFrames)
applyTiling(client: client, store: &store, config: runtimeConfiguration.value, workspaces: &workspaces.value, maximizedFrames: maximizedFrames)
workspacePersistence.save(workspaces.value.persistedAssignments, activeWorkspace: workspaces.value.activeWorkspace, trees: workspaces.value.persistedTrees, layouts: workspaces.value.persistedLayouts, barPosition: runtimeConfiguration.value.barPosition)
notifyBar(store: store, workspace: workspaces.value.activeWorkspace, layout: workspaces.value.layout(for: workspaces.value.activeWorkspace, default: runtimeConfiguration.value.layout).rawValue, position: runtimeConfiguration.value.barPosition, workspaces: workspaces.value)

let observerRegistry = AXObserverRegistry { processID, event in
    guard let application = NSRunningApplication(processIdentifier: processID) else {
        if case .environmentChanged = event {
            for window in managedWindows(client) { store.upsert(window) }
            applyTiling(client: client, store: &store, config: runtimeConfiguration.value, workspaces: &workspaces.value, maximizedFrames: maximizedFrames, force: true)
        }
        return
    }
        switch event {
        case .focusedWindowChanged(_):
            guard !layoutGuard.isApplying else { return }
            // Only the focused window is read: enumerating every window of an
            // application that is busy handling a click stalls the daemon.
            guard let window = client.focusedWindow(for: application), isManaged(window) else { return }
            // Windows that appeared between an app's launch rescan and its
            // observer attaching, typical of iOS apps, are first seen here.
            let isNewWindow = !store.windows.contains { $0.id == window.id }
            store.upsert(window)
            workspaces.value.register(window, rules: runtimeConfiguration.value.rules, defaultWorkspace: workspaces.value.activeWorkspace, restorePersisted: !isNewWindow)
            store.setFocusedWindow(window.id)
            workspaces.value.recordFocus(window.id)
            print("macwm: focused \(window.appName) - \(window.title)")
            let isHiddenGroupMember = workspaces.value.hiddenGroupMembers(among: [window.id]).contains(window.id)
            if isHiddenGroupMember {
                workspaces.value.showGroupMember(window.id)
                applyTiling(client: client, store: &store, config: runtimeConfiguration.value, workspaces: &workspaces.value, maximizedFrames: maximizedFrames, force: true)
            }
            updateFocusBorder(store: store, config: runtimeConfiguration.value, workspaces: workspaces.value)
            if isNewWindow {
                if let rule = client.rule(for: window) { client.apply(rule: rule, to: window) }
                applyTiling(client: client, store: &store, config: runtimeConfiguration.value, workspaces: &workspaces.value, maximizedFrames: maximizedFrames)
                workspacePersistence.save(workspaces.value.persistedAssignments, activeWorkspace: workspaces.value.activeWorkspace, trees: workspaces.value.persistedTrees, layouts: workspaces.value.persistedLayouts)
            }
            notifyBar(store: store, workspace: workspaces.value.activeWorkspace, layout: workspaces.value.layout(for: workspaces.value.activeWorkspace, default: runtimeConfiguration.value.layout).rawValue, position: runtimeConfiguration.value.barPosition, workspaces: workspaces.value)
            let windowWorkspace = workspaces.value.workspace(for: window.id)
            guard windowWorkspace != workspaces.value.activeWorkspace else { return }
            _ = switchWorkspace(windowWorkspace, client: client, store: &store, maximizedFrames: maximizedFrames, workspaces: workspaces, config: runtimeConfiguration.value)
        case .windowDestroyed(let element):
            guard !layoutGuard.isApplying else { return }
            let id = WindowID(processID: UInt32(application.processIdentifier), elementHash: Int(truncatingIfNeeded: CFHash(element)))
            store.remove(id)
            maximizedFrames.removeValue(forKey: id)
            parkedFrames.value.removeValue(forKey: id)
            workspaces.value.remove(id)
            applyTiling(client: client, store: &store, config: runtimeConfiguration.value, workspaces: &workspaces.value, maximizedFrames: maximizedFrames)
            workspacePersistence.save(workspaces.value.persistedAssignments, activeWorkspace: workspaces.value.activeWorkspace, trees: workspaces.value.persistedTrees, layouts: workspaces.value.persistedLayouts)
            notifyBar(store: store, workspace: workspaces.value.activeWorkspace, layout: workspaces.value.layout(for: workspaces.value.activeWorkspace, default: runtimeConfiguration.value.layout).rawValue, position: runtimeConfiguration.value.barPosition, workspaces: workspaces.value)
            print("macwm: tracking \(store.windows.count) windows")
        case .windowCreated(_):
            guard !layoutGuard.isApplying else { return }
            let windows = managedWindows(client, for: application)
            store.replace(
                windows: windows,
                forProcessID: UInt32(application.processIdentifier)
            )
            for window in windows {
                workspaces.value.register(window, rules: runtimeConfiguration.value.rules, defaultWorkspace: workspaces.value.activeWorkspace, restorePersisted: false)
                if let rule = client.rule(for: window) { client.apply(rule: rule, to: window) }
                let belongsToActiveWorkspace = workspaces.value.workspace(for: window.id) == workspaces.value.activeWorkspace
                if !belongsToActiveWorkspace, let (change, liveFrame) = parkChange(for: window, keepsFrame: !window.isTileable, client: client) {
                    store.updateFrame(change.frame, for: window.id)
                    if let liveFrame { parkedFrames.value[window.id] = liveFrame }
                    client.apply([change]) { result in FrameCorrections.rereadRejected([change], result: result, client: client) }
                }
            }
            applyTiling(client: client, store: &store, config: runtimeConfiguration.value, workspaces: &workspaces.value, maximizedFrames: maximizedFrames)
            workspacePersistence.save(workspaces.value.persistedAssignments, activeWorkspace: workspaces.value.activeWorkspace, trees: workspaces.value.persistedTrees, layouts: workspaces.value.persistedLayouts)
            notifyBar(store: store, workspace: workspaces.value.activeWorkspace, layout: workspaces.value.layout(for: workspaces.value.activeWorkspace, default: runtimeConfiguration.value.layout).rawValue, position: runtimeConfiguration.value.barPosition, workspaces: workspaces.value)
            print("macwm: tracking \(store.windows.count) windows")
        case .windowVisibilityChanged:
            guard !layoutGuard.isApplying else { return }
            refresh(UInt32(application.processIdentifier), client: client, store: &store)
            showWorkspaceWindows(workspaces.value.activeWorkspace, client: client, store: &store, workspaces: workspaces.value, maximizedFrames: maximizedFrames)
            applyTiling(client: client, store: &store, config: runtimeConfiguration.value, workspaces: &workspaces.value, maximizedFrames: maximizedFrames, force: true)
            notifyBar(store: store, workspace: workspaces.value.activeWorkspace, layout: workspaces.value.layout(for: workspaces.value.activeWorkspace, default: runtimeConfiguration.value.layout).rawValue, position: runtimeConfiguration.value.barPosition, workspaces: workspaces.value)
        case .environmentChanged:
            // Without Accessibility every query answers empty; replacing the
            // store with that would abandon parked windows in the corner.
            guard !layoutGuard.isApplying, AXIsProcessTrusted() else { return }
            let windows = managedWindows(client)
            store.replaceAll(windows)
            for window in windows {
                workspaces.value.register(window, rules: runtimeConfiguration.value.rules, defaultWorkspace: workspaces.value.activeWorkspace)
            }
            applyTiling(client: client, store: &store, config: runtimeConfiguration.value, workspaces: &workspaces.value, maximizedFrames: maximizedFrames, force: true)
            workspacePersistence.save(workspaces.value.persistedAssignments, activeWorkspace: workspaces.value.activeWorkspace, trees: workspaces.value.persistedTrees, layouts: workspaces.value.persistedLayouts)
            notifyBar(store: store, workspace: workspaces.value.activeWorkspace, layout: workspaces.value.layout(for: workspaces.value.activeWorkspace, default: runtimeConfiguration.value.layout).rawValue, position: runtimeConfiguration.value.barPosition, workspaces: workspaces.value)
        }
}
observerRegistry.start()

let configWatcher = ConfigWatcher(directory: NSString(string: "~/.config/macwm").expandingTildeInPath) {
    let result = execute(.reload, client: client, store: &store, maximizedFrames: &maximizedFrames, configuration: runtimeConfiguration, workspaces: workspaces)
    print("macwm: configuration changed on disk; reload: \(result)")
}
configWatcher.start()
for name in runtimeConfiguration.value.autostart.keys.sorted() {
    guard let commandLine = runtimeConfiguration.value.autostart[name] else { continue }
    print("macwm: autostart \(name): \(commandLine)")
    launch(commandLine)
}

guard let hotkeys = HotkeyManager(keybinds: keybinds, handler: { command in
    _ = execute(command, client: client, store: &store, maximizedFrames: &maximizedFrames, configuration: runtimeConfiguration, workspaces: workspaces)
}) else {
    fputs("macwm: unable to register global hotkeys. Enable Input Monitoring for macwm-daemon.\n", stderr)
    exit(EXIT_FAILURE)
}

let mouse = MouseManager(
    client: client,
    targets: mouseTargets,
    onFloatingDragEnd: { id, frame in
        store.updateFrame(frame, for: id)
        updateFocusBorder(store: store, config: runtimeConfiguration.value, workspaces: workspaces.value)
    },
    onTiledResize: { id, deltaX, deltaY in
        guard let layoutFrame = client.layoutFrame() else { return }
        let activeWorkspace = workspaces.value.activeWorkspace
        guard workspaces.value.resizeTiled(id, deltaX: deltaX, deltaY: deltaY, frame: layoutFrame, in: activeWorkspace) else { return }
        applyTiling(client: client, store: &store, config: runtimeConfiguration.value, workspaces: &workspaces.value, maximizedFrames: maximizedFrames, force: true)
        workspacePersistence.save(workspaces.value.persistedAssignments, activeWorkspace: activeWorkspace, trees: workspaces.value.persistedTrees, layouts: workspaces.value.persistedLayouts)
    },
    onTiledSwap: { first, second in
        let activeWorkspace = workspaces.value.activeWorkspace
        guard workspaces.value.swap(first, second, in: activeWorkspace) else { return }
        applyTiling(client: client, store: &store, config: runtimeConfiguration.value, workspaces: &workspaces.value, maximizedFrames: maximizedFrames, force: true)
        workspacePersistence.save(workspaces.value.persistedAssignments, activeWorkspace: activeWorkspace, trees: workspaces.value.persistedTrees, layouts: workspaces.value.persistedLayouts)
    }
)
if mouse == nil { fputs("macwm: unable to register the mouse tap; Option+drag on floating windows is disabled.\n", stderr) }

// Losing Accessibility, for example when it is switched off in System
// Settings, must stop the taps at once: an untrusted process that keeps
// re-enabling active taps freezes keyboard and mouse for the whole Mac.
let trustWatchdog = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
    let trusted = AXIsProcessTrusted()
    guard trusted != hotkeys.isTrusted else { return }
    hotkeys.isTrusted = trusted
    mouse?.isTrusted = trusted
    fputs("macwm: Accessibility \(trusted ? "granted again; resuming" : "revoked; pausing hotkeys and mouse handling")\n", stderr)
    guard trusted else { return }
    // Windows parked while trust was gone have nobody else to bring them back.
    MainActor.assumeIsolated {
        let windows = managedWindows(client)
        store.replaceAll(windows)
        for window in windows {
            workspaces.value.register(window, rules: runtimeConfiguration.value.rules, defaultWorkspace: workspaces.value.activeWorkspace)
        }
        showWorkspaceWindows(workspaces.value.activeWorkspace, client: client, store: &store, workspaces: workspaces.value, maximizedFrames: maximizedFrames)
        applyTiling(client: client, store: &store, config: runtimeConfiguration.value, workspaces: &workspaces.value, maximizedFrames: maximizedFrames, force: true)
        notifyBar(store: store, workspace: workspaces.value.activeWorkspace, layout: workspaces.value.layout(for: workspaces.value.activeWorkspace, default: runtimeConfiguration.value.layout).rawValue, position: runtimeConfiguration.value.barPosition, workspaces: workspaces.value)
        print("macwm: recovered \(windows.count) windows after Accessibility returned")
    }
}

let focusFollowsMouse = FocusFollowsMouse(client: client, focus: { id in
    let isFocusable = store.windows.contains { $0.id == id && !$0.isHidden && workspaces.value.workspace(for: $0.id) == workspaces.value.activeWorkspace }
    guard isFocusable, store.focusedWindow?.id != id, let window = store.windows.first(where: { $0.id == id }) else { return }
    client.focus(window)
    store.setFocusedWindow(id)
    workspaces.value.recordFocus(id)
})
focusFollowsMouse.setEnabled(runtimeConfiguration.value.focusFollowsMouse)

guard let server = UnixSocketServer(path: socketPath, handler: { command in
    execute(command, client: client, store: &store, maximizedFrames: &maximizedFrames, configuration: runtimeConfiguration, workspaces: workspaces)
}) else {
    fputs("macwm: unable to create IPC socket at \(socketPath).\n", stderr)
    exit(EXIT_FAILURE)
}

application.run()

withExtendedLifetime((hotkeys, server, observerRegistry)) {}

private func execute(_ command: Command, client: AXClient, store: inout WindowStore, maximizedFrames: inout [WindowID: Frame], configuration: DaemonConfiguration, workspaces: DaemonWorkspaces) -> String {
    syncFocusedWindow(client: client, store: &store)
    if let focusedID = store.focusedWindow?.id { workspaces.value.recordFocus(focusedID) }

    switch command {
    case .status:
        let focused = store.focusedWindow.map { "\($0.appName) - \($0.title)" } ?? "none"
        let layout = workspaces.value.layout(for: workspaces.value.activeWorkspace, default: configuration.value.layout).rawValue
        return "workspace: \(workspaces.value.activeWorkspace)\nlayout: \(layout)\nmode: \(keybinds.mode)\nwindows: \(store.windows.count)\nfocused: \(focused)"
    case let .query(query):
        let layout = workspaces.value.layout(for: workspaces.value.activeWorkspace, default: configuration.value.layout).rawValue
        let snapshot = StateSnapshot(store: store, workspaces: workspaces.value, layout: layout, mode: keybinds.mode)
        switch query {
        case .state: return StateJSON.encode(snapshot)
        case .windows: return StateJSON.encode(snapshot.windows)
        case .workspaces: return StateJSON.encode(snapshot.workspaces)
        }
    case .reload:
        guard let updatedConfiguration = ConfigLoader.loadValidated() else { return "error: invalid configuration" }
        configuration.value = updatedConfiguration
        keybinds.replace(updatedConfiguration.keybindEngine(keyCodes: KeyboardLayout.currentTable()))
        updateFocusBorder(store: store, config: updatedConfiguration, workspaces: workspaces.value)
        focusFollowsMouse.setEnabled(updatedConfiguration.focusFollowsMouse)
        client.updateRules(configuration.value.rules)
        client.updateBar(position: configuration.value.barPosition, thickness: configuration.value.barThickness)
        for window in managedWindows(client) {
            store.upsert(window)
            workspaces.value.register(window, rules: configuration.value.rules, defaultWorkspace: workspaces.value.activeWorkspace)
            guard let rule = client.rule(for: window) else { continue }
            store.setFloating(rule.float, for: window.id)
            if let workspace = rule.workspace { workspaces.value.assign(window, to: workspace) }
            client.apply(rule: rule, to: window)
        }
        applyTiling(client: client, store: &store, config: configuration.value, workspaces: &workspaces.value, maximizedFrames: maximizedFrames, force: true)
        workspacePersistence.save(workspaces.value.persistedAssignments, activeWorkspace: workspaces.value.activeWorkspace, trees: workspaces.value.persistedTrees, floating: store.persistedFloating)
        notifyBar(store: store, workspace: workspaces.value.activeWorkspace, layout: workspaces.value.layout(for: workspaces.value.activeWorkspace, default: configuration.value.layout).rawValue, position: configuration.value.barPosition, workspaces: workspaces.value)
        return "ok"
    case let .layout(layout):
        workspaces.value.setLayout(layout, for: workspaces.value.activeWorkspace)
        applyTiling(client: client, store: &store, config: configuration.value, workspaces: &workspaces.value, maximizedFrames: maximizedFrames, force: true)
        workspacePersistence.save(workspaces.value.persistedAssignments, activeWorkspace: workspaces.value.activeWorkspace, trees: workspaces.value.persistedTrees, layouts: workspaces.value.persistedLayouts)
        notifyBar(store: store, workspace: workspaces.value.activeWorkspace, layout: layout.rawValue, position: configuration.value.barPosition, workspaces: workspaces.value)
        return "ok"
    case let .workspace(workspace):
        return switchWorkspace(workspace, client: client, store: &store, maximizedFrames: maximizedFrames, workspaces: workspaces, config: configuration.value)
    case .previousWorkspace:
        guard let previous = workspaces.value.previousWorkspace else { return "error: no previous workspace" }
        return switchWorkspace(previous, client: client, store: &store, maximizedFrames: maximizedFrames, workspaces: workspaces, config: configuration.value)
    case .center:
        guard let focusedWindow = store.focusedWindow, let frame = focusedWindow.frame else { return "error: no focused window" }
        guard !focusedWindow.isTileable, let visible = client.visibleScreenFrame(for: focusedWindow) else { return "error: focused window is tiled" }
        let centered = frame.centered(in: visible)
        guard client.setFrame(centered, for: focusedWindow) else { return "error: unable to move window" }
        store.updateFrame(centered, for: focusedWindow.id)
        return "ok"
    case let .sendToWorkspace(workspace):
        guard let focusedWindow = store.focusedWindow else { return "error: no focused window" }
        guard workspaces.value.isValid(workspace) else { return "error: invalid workspace" }
        workspaces.value.assign(focusedWindow, to: workspace)
        workspacePersistence.save(workspaces.value.persistedAssignments, activeWorkspace: workspaces.value.activeWorkspace, trees: workspaces.value.persistedTrees, layouts: workspaces.value.persistedLayouts)
        return switchWorkspace(workspaces.value.activeWorkspace, client: client, store: &store, maximizedFrames: maximizedFrames, workspaces: workspaces, config: configuration.value)
    case let .moveToWorkspace(workspace):
        guard let focusedWindow = store.focusedWindow else { return "error: no focused window" }
        guard workspaces.value.isValid(workspace) else { return "error: invalid workspace" }
        workspaces.value.assign(focusedWindow, to: workspace)
        workspaces.value.recordFocus(focusedWindow.id)
        workspacePersistence.save(workspaces.value.persistedAssignments, activeWorkspace: workspaces.value.activeWorkspace, trees: workspaces.value.persistedTrees, layouts: workspaces.value.persistedLayouts)
        return switchWorkspace(workspace, client: client, store: &store, maximizedFrames: maximizedFrames, workspaces: workspaces, config: configuration.value)
    case let .focus(direction):
        let candidateIDs = activeWorkspaceWindowIDs(store: store, workspaces: workspaces.value, tileableOnly: false)
        guard let target = store.window(in: direction, among: candidateIDs) else { return "error: no window in direction" }
        client.focus(target)
        store.setFocusedWindow(target.id)
        workspaces.value.recordFocus(target.id)
        warpCursor(to: target, enabled: configuration.value.cursorWarp)
        updateFocusBorder(store: store, config: configuration.value, workspaces: workspaces.value)
        applyTiling(client: client, store: &store, config: configuration.value, workspaces: &workspaces.value, maximizedFrames: maximizedFrames)
        print("macwm: focused \(target.appName) - \(target.title)")
        return "ok"
    case let .move(direction):
        guard let focusedWindow = store.focusedWindow else { return "error: no focused window" }
        guard focusedWindow.isTileable else {
            guard client.move(focusedWindow, direction: direction) else { return "error: unable to move window" }
            refresh(focusedWindow.processID, client: client, store: &store)
            return "ok"
        }
        applyTiling(client: client, store: &store, config: configuration.value, workspaces: &workspaces.value, maximizedFrames: maximizedFrames, force: true)
        let candidateIDs = activeWorkspaceWindowIDs(store: store, workspaces: workspaces.value, tileableOnly: true)
        guard focusedWindow.isTileable, let target = store.window(in: direction, among: candidateIDs) else { return "error: no tileable window in direction" }
        guard workspaces.value.swap(focusedWindow.id, target.id, in: workspaces.value.activeWorkspace) else { return "error: layout is not ready" }
        applyTiling(client: client, store: &store, config: configuration.value, workspaces: &workspaces.value, maximizedFrames: maximizedFrames, force: true)
        workspacePersistence.save(workspaces.value.persistedAssignments, activeWorkspace: workspaces.value.activeWorkspace, trees: workspaces.value.persistedTrees, layouts: workspaces.value.persistedLayouts)
        return "ok"
    case let .resize(operation):
        guard let focusedWindow = store.focusedWindow else { return "error: no focused window" }
        let activeWorkspace = workspaces.value.activeWorkspace
        let activeLayout = workspaces.value.layout(for: activeWorkspace, default: configuration.value.layout)
        let isTiled = focusedWindow.isTileable && maximizedFrames[focusedWindow.id] == nil
        if isTiled, activeLayout == .masterStack {
            configuration.value.master.adjustRatio(by: operation == .grow ? 0.05 : -0.05)
            applyTiling(client: client, store: &store, config: configuration.value, workspaces: &workspaces.value, maximizedFrames: maximizedFrames, force: true)
            return "ok"
        }
        let isTiledInBSP = isTiled && activeLayout == .bsp
        guard isTiledInBSP else {
            guard client.resize(focusedWindow, operation: operation) else { return "error: unable to resize window" }
            refresh(focusedWindow.processID, client: client, store: &store)
            return "ok"
        }
        applyTiling(client: client, store: &store, config: configuration.value, workspaces: &workspaces.value, maximizedFrames: maximizedFrames, force: true)
        let delta = operation == .grow ? 0.05 : -0.05
        guard workspaces.value.adjustSplitRatio(containing: focusedWindow.id, by: delta, in: activeWorkspace) else { return "error: layout is not ready" }
        applyTiling(client: client, store: &store, config: configuration.value, workspaces: &workspaces.value, maximizedFrames: maximizedFrames, force: true)
        workspacePersistence.save(workspaces.value.persistedAssignments, activeWorkspace: activeWorkspace, trees: workspaces.value.persistedTrees, layouts: workspaces.value.persistedLayouts)
        return "ok"
    case .maximize:
        guard let focusedWindow = store.focusedWindow, let currentFrame = focusedWindow.frame else { return "error: no focused window frame" }
        if let previousFrame = maximizedFrames[focusedWindow.id] {
            guard client.setFrame(previousFrame, for: focusedWindow) else { return "error: unable to restore window" }
            maximizedFrames.removeValue(forKey: focusedWindow.id)
            store.updateFrame(previousFrame, for: focusedWindow.id)
            workspacePersistence.save(workspaces.value.persistedAssignments, activeWorkspace: workspaces.value.activeWorkspace, trees: workspaces.value.persistedTrees, floating: store.persistedFloating, maximized: persistedMaximizedFrames(store: store, maximizedFrames: maximizedFrames))
            return "ok"
        }
        guard let targetFrame = client.visibleScreenFrame(for: focusedWindow) else { return "error: no screen" }
        guard client.setFrame(targetFrame, for: focusedWindow) else { return "error: unable to maximize window" }
        maximizedFrames[focusedWindow.id] = currentFrame
        store.updateFrame(targetFrame, for: focusedWindow.id)
        workspacePersistence.save(workspaces.value.persistedAssignments, activeWorkspace: workspaces.value.activeWorkspace, trees: workspaces.value.persistedTrees, floating: store.persistedFloating, maximized: persistedMaximizedFrames(store: store, maximizedFrames: maximizedFrames))
        return "ok"
    case .toggleFloat:
        guard store.toggleFocusedFloating() != nil else { return "error: no focused window" }
        applyTiling(client: client, store: &store, config: configuration.value, workspaces: &workspaces.value, maximizedFrames: maximizedFrames, force: true)
        workspacePersistence.save(workspaces.value.persistedAssignments, activeWorkspace: workspaces.value.activeWorkspace, trees: workspaces.value.persistedTrees, floating: store.persistedFloating)
        return "ok"
    case .toggleTerminal:
        ScratchpadController(client: client, bundleIdentifier: configuration.value.terminalBundleIdentifier, fillsScreen: true).toggle()
        return "ok"
    case let .scratchpad(name):
        let bundleIdentifier = configuration.value.scratchpads[name] ?? name
        ScratchpadController(client: client, bundleIdentifier: bundleIdentifier, fillsScreen: false).toggle()
        return "ok"
    case .close:
        guard let focusedWindow = store.focusedWindow else { return "error: no focused window" }
        guard client.close(focusedWindow) else { return "error: unable to close window" }
        return "ok"
    case let .cycleFocus(forward):
        let candidateIDs = activeWorkspaceWindowIDs(store: store, workspaces: workspaces.value, tileableOnly: false)
        guard let target = store.cyclingWindow(forward: forward, among: candidateIDs) else { return "error: no window to focus" }
        client.focus(target)
        store.setFocusedWindow(target.id)
        workspaces.value.recordFocus(target.id)
        warpCursor(to: target, enabled: configuration.value.cursorWarp)
        updateFocusBorder(store: store, config: configuration.value, workspaces: workspaces.value)
        return "ok"
    case .toggleSplit:
        guard let focusedWindow = store.focusedWindow, focusedWindow.isTileable else { return "error: no tiled window focused" }
        applyTiling(client: client, store: &store, config: configuration.value, workspaces: &workspaces.value, maximizedFrames: maximizedFrames, force: true)
        guard workspaces.value.toggleSplit(containing: focusedWindow.id, in: workspaces.value.activeWorkspace) else { return "error: layout is not ready" }
        applyTiling(client: client, store: &store, config: configuration.value, workspaces: &workspaces.value, maximizedFrames: maximizedFrames, force: true)
        workspacePersistence.save(workspaces.value.persistedAssignments, activeWorkspace: workspaces.value.activeWorkspace, trees: workspaces.value.persistedTrees, layouts: workspaces.value.persistedLayouts)
        return "ok"
    case let .group(command):
        guard let focusedWindow = store.focusedWindow else { return "error: no focused window" }
        let activeWorkspace = workspaces.value.activeWorkspace
        var windowToFocus: WindowID?
        switch command {
        case .toggle:
            guard workspaces.value.toggleGroup(containing: focusedWindow.id, in: activeWorkspace) else { return "error: window is not in this workspace" }
        case let .add(direction):
            let candidateIDs = activeWorkspaceWindowIDs(store: store, workspaces: workspaces.value, tileableOnly: true)
            guard let target = store.window(in: direction, among: candidateIDs) else { return "error: no window in direction" }
            guard workspaces.value.addToGroup(focusedWindow.id, containing: target.id, in: activeWorkspace) else { return "error: unable to group" }
        case .leave:
            guard workspaces.value.leaveGroup(focusedWindow.id, in: activeWorkspace) else { return "error: window is not grouped" }
        case let .cycle(forward):
            guard let next = workspaces.value.cycleGroup(containing: focusedWindow.id, forward: forward) else { return "error: window is not grouped" }
            windowToFocus = next
        }
        applyTiling(client: client, store: &store, config: configuration.value, workspaces: &workspaces.value, maximizedFrames: maximizedFrames, force: true)
        workspacePersistence.save(workspaces.value.persistedAssignments, activeWorkspace: activeWorkspace, trees: workspaces.value.persistedTrees, layouts: workspaces.value.persistedLayouts)
        if let windowToFocus, let window = store.windows.first(where: { $0.id == windowToFocus }) {
            client.focus(window)
            store.setFocusedWindow(windowToFocus)
            workspaces.value.recordFocus(windowToFocus)
            warpCursor(to: window, enabled: configuration.value.cursorWarp)
            updateFocusBorder(store: store, config: configuration.value, workspaces: workspaces.value)
        }
        return "ok"
    case let .master(command):
        switch command {
        case .grow: configuration.value.master.adjustRatio(by: 0.05)
        case .shrink: configuration.value.master.adjustRatio(by: -0.05)
        case .addMaster: configuration.value.master.adjustCount(by: 1)
        case .removeMaster: configuration.value.master.adjustCount(by: -1)
        case let .orientation(orientation): configuration.value.master.orientation = orientation
        case .nextOrientation: configuration.value.master.orientation = configuration.value.master.orientation.next
        }
        applyTiling(client: client, store: &store, config: configuration.value, workspaces: &workspaces.value, maximizedFrames: maximizedFrames, force: true)
        return "ok"
    case let .preselect(direction):
        workspaces.value.preselect(direction, in: workspaces.value.activeWorkspace)
        return "ok"
    case let .exec(commandLine):
        launch(commandLine)
        return "ok"
    case let .mode(name):
        keybinds.enter(mode: name)
        notifyBar(store: store, workspace: workspaces.value.activeWorkspace, layout: workspaces.value.layout(for: workspaces.value.activeWorkspace, default: configuration.value.layout).rawValue, position: configuration.value.barPosition, workspaces: workspaces.value)
        return "ok"
    }
}

/// The terminal and the scratchpads are never tiled, hidden or parked;
/// accessory apps such as the bar are already filtered out by AXClient.
private func isManaged(_ window: ManagedWindow) -> Bool {
    // Transient popups such as Chrome's omnibox dropdown report no known
    // subrole; parking or tiling them only disturbs the application.
    let knownSubroles = ["AXStandardWindow", "AXDialog", "AXSystemDialog", "AXFloatingWindow"]
    let isRealWindow = knownSubroles.contains(window.subrole)
    return isRealWindow && !runtimeConfiguration.value.unmanagedBundleIdentifiers.contains(window.bundleIdentifier)
}

private func managedWindows(_ client: AXClient) -> [ManagedWindow] {
    client.visibleWindows().filter { isManaged($0) }
}

private func managedWindows(_ client: AXClient, for application: NSRunningApplication) -> [ManagedWindow] {
    client.windows(for: application).filter { isManaged($0) }
}

private func persistedMaximizedFrames(store: WindowStore, maximizedFrames: [WindowID: Frame]) -> [WindowKey: Frame] {
    Dictionary(uniqueKeysWithValues: store.windows.compactMap { window in
        guard let frame = maximizedFrames[window.id] else { return nil }
        return (window.persistentKey, frame)
    })
}

/// Focus events keep the store current; Accessibility is only asked when the
/// frontmost application disagrees, since a busy application can take a
/// second to answer.
private func syncFocusedWindow(client: AXClient, store: inout WindowStore) {
    let frontmostProcessID = NSWorkspace.shared.frontmostApplication?.processIdentifier
    if let focused = store.focusedWindow, pid_t(focused.processID) == frontmostProcessID { return }
    guard let focusedWindow = client.focusedWindow(), isManaged(focusedWindow) else { return }
    store.upsert(focusedWindow)
    store.setFocusedWindow(focusedWindow.id)
}

private func refresh(_ processID: UInt32, client: AXClient, store: inout WindowStore) {
    guard let application = NSRunningApplication(processIdentifier: pid_t(processID)) else { return }
    store.replace(windows: managedWindows(client, for: application), forProcessID: processID)
}

private func switchWorkspace(
    _ workspace: Int,
    client: AXClient,
    store: inout WindowStore,
    maximizedFrames: [WindowID: Frame],
    workspaces: DaemonWorkspaces,
    config: Config
) -> String {
    guard workspaces.value.isValid(workspace) else { return "error: invalid workspace" }
    workspaces.value.activate(workspace)
            workspacePersistence.save(workspaces.value.persistedAssignments, activeWorkspace: workspace, trees: workspaces.value.persistedTrees, layouts: workspaces.value.persistedLayouts, barPosition: config.barPosition)
            notifyBar(store: store, workspace: workspace, layout: workspaces.value.layout(for: workspace, default: config.layout).rawValue, position: config.barPosition, workspaces: workspaces.value)

    let started = DispatchTime.now().uptimeNanoseconds
    showWorkspaceWindows(workspace, client: client, store: &store, workspaces: workspaces.value, maximizedFrames: maximizedFrames)
    let parked = DispatchTime.now().uptimeNanoseconds
    applyTiling(client: client, store: &store, config: config, workspaces: &workspaces.value, maximizedFrames: maximizedFrames, force: true)
    let tiled = DispatchTime.now().uptimeNanoseconds
    focusLastWindow(in: workspace, client: client, store: &store, workspaces: workspaces, warpCursor: config.cursorWarp)
    let focused = DispatchTime.now().uptimeNanoseconds
    reportSlowSwitch(to: workspace, park: parked &- started, tile: tiled &- parked, focus: focused &- tiled)
    updateFocusBorder(store: store, config: config, workspaces: workspaces.value)
    workspacePersistence.save(workspaces.value.persistedAssignments, activeWorkspace: workspace, trees: workspaces.value.persistedTrees, layouts: workspaces.value.persistedLayouts)
    return "ok"
}

/// Returns keyboard focus to the window last used in the workspace, or to the
/// first visible one, so the user can type right after switching.
private func focusLastWindow(in workspace: Int, client: AXClient, store: inout WindowStore, workspaces: DaemonWorkspaces, warpCursor shouldWarp: Bool) {
    let candidates = store.windows.filter { !$0.isHidden && workspaces.value.workspace(for: $0.id) == workspace }
    let remembered = workspaces.value.lastFocusedWindow(in: workspace).flatMap { id in candidates.first { $0.id == id } }
    guard let target = remembered ?? candidates.first(where: \.isTileable) ?? candidates.first else { return }
    client.focus(target)
    store.setFocusedWindow(target.id)
    workspaces.value.recordFocus(target.id)
    warpCursor(to: store.windows.first { $0.id == target.id } ?? target, enabled: shouldWarp)
}

/// Keyboard focus moves the pointer to the window's center so mouse work
/// continues where the eyes are, like Hyprland unless cursor:no_warps is set.
private func warpCursor(to window: ManagedWindow, enabled: Bool) {
    guard enabled, let frame = window.frame else { return }
    let center = CGPoint(x: frame.x + frame.width / 2, y: frame.y + frame.height / 2)
    CGWarpMouseCursorPosition(center)
    CGAssociateMouseAndMouseCursorPosition(1)
}

/// Diagnostics: phases of a workspace switch that took longer than 40 ms in total.
private func reportSlowSwitch(to workspace: Int, park: UInt64, tile: UInt64, focus: UInt64) {
    let milliseconds = { (nanoseconds: UInt64) in Double(nanoseconds) / 1_000_000 }
    let total = milliseconds(park + tile + focus)
    guard total > 40 else { return }
    fputs(String(format: "macwm: slow switch to %d: park %.0f ms, tile %.0f ms, focus %.0f ms\n", workspace, milliseconds(park), milliseconds(tile), milliseconds(focus)), stderr)
}

/// Draws the border around the focused window when it is visible in the
/// active workspace; hides it otherwise.
private func updateFocusBorder(store: WindowStore, config: Config, workspaces: WorkspaceManager) {
    let focused = store.focusedWindow
    let isVisible = focused.map { !$0.isHidden && workspaces.workspace(for: $0.id) == workspaces.activeWorkspace } ?? false
    let frame = isVisible ? focused?.frame : nil
    MainActor.assumeIsolated { focusBorder.update(options: config.border, focused: frame) }
}

private func activeWorkspaceWindowIDs(store: WindowStore, workspaces: WorkspaceManager, tileableOnly: Bool) -> Set<WindowID> {
    let ids = store.windows.filter { window in
        let isVisibleInActiveWorkspace = !window.isHidden && workspaces.workspace(for: window.id) == workspaces.activeWorkspace
        return isVisibleInActiveWorkspace && (!tileableOnly || window.isTileable)
    }.map(\.id)
    return Set(ids).subtracting(workspaces.hiddenGroupMembers(among: ids))
}

/// Runs a command line through the user's login shell so PATH and profile
/// match an interactive terminal instead of launchd's minimal environment.
private func launch(_ commandLine: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh")
    process.arguments = ["-lc", commandLine]
    process.standardInput = FileHandle.nullDevice
    do {
        try process.run()
    } catch {
        fputs("macwm: exec failed for \(commandLine): \(error.localizedDescription)\n", stderr)
    }
}

/// Parks every window outside `workspace` off-screen and brings the workspace's
/// own windows back. Parking moves windows instead of minimizing them, so the
/// switch is instant and never animates through the Dock.
private func showWorkspaceWindows(_ workspace: Int, client: AXClient, store: inout WindowStore, workspaces: WorkspaceManager, maximizedFrames: [WindowID: Frame]) {
    layoutGuard.isApplying = true
    defer { layoutGuard.isApplying = false }
    var changes: [AXClient.FrameChange] = []
    var framesToRemember: [WindowID: Frame] = [:]
    for window in store.windows where !window.isHidden {
        let belongsToWorkspace = workspaces.workspace(for: window.id) == workspace
        let isTiled = window.isTileable && maximizedFrames[window.id] == nil
        guard belongsToWorkspace else {
            guard let (change, liveFrame) = parkChange(for: window, keepsFrame: !isTiled, client: client) else { continue }
            changes.append(change)
            if let liveFrame { framesToRemember[window.id] = liveFrame }
            continue
        }
        if let change = unparkChange(for: window, willBeTiled: isTiled, client: client) { changes.append(change) }
    }
    // Optimistic: the store takes the new frames now; rejected ones are re-read below.
    for change in changes {
        store.updateFrame(change.frame, for: change.window.id)
        if let remembered = framesToRemember[change.window.id] { parkedFrames.value[change.window.id] = remembered }
    }
    let queued = changes
    client.apply(queued) { result in FrameCorrections.rereadRejected(queued, result: result, client: client) }
}

/// Runs on the main thread from apply's completion, after the application answered.
enum FrameCorrections {
    /// Re-reads the real frame of windows that did not take theirs, so parking
    /// and tiling decisions never rest on a frame the application refused.
    static func rereadRejected(_ changes: [AXClient.FrameChange], result: AXClient.ApplyResult, client: AXClient) {
        for change in changes where !result.applied.contains(change.window.id) {
            guard let actual = client.currentFrame(for: change.window) else { continue }
            MainActor.assumeIsolated { store.updateFrame(actual, for: change.window.id) }
        }
    }

    /// A window that refuses its tile size for good, like a fixed-size game,
    /// floats from now on instead of leaving a hole every pass.
    static func floatRefusingSize(_ changes: [AXClient.FrameChange], result: AXClient.ApplyResult, client: AXClient) {
        let refused = changes.filter { result.refusedSize.contains($0.window.id) && !$0.positionOnly }
        guard !refused.isEmpty else { return }
        MainActor.assumeIsolated {
            for change in refused {
                store.setFloating(true, for: change.window.id)
                print("macwm: \(change.window.appName) refuses its tile size; floating it")
            }
            applyTiling(client: client, store: &store, config: runtimeConfiguration.value, workspaces: &workspaces.value, maximizedFrames: maximizedFrames, force: true)
        }
    }
}

/// The move that parks a window, plus the live frame to remember when the
/// window keeps its own size. Nil when the window is already parked.
private func parkChange(for window: ManagedWindow, keepsFrame: Bool, client: AXClient) -> (AXClient.FrameChange, Frame?)? {
    guard let storedFrame = window.frame, let screen = client.screenFrame(for: window), !storedFrame.isParked(in: screen) else { return nil }
    // Only windows still on screen need the live frame; asking a busy or
    // heavy application for it on every switch is what made switching slow.
    let frame = keepsFrame ? client.currentFrame(for: window) ?? storedFrame : storedFrame
    guard !frame.isParked(in: screen) else { return nil }
    return (AXClient.FrameChange(window: window, frame: frame.parked(in: screen), positionOnly: true), keepsFrame ? frame : nil)
}

/// The move that brings a parked floating or maximized window back; tiled
/// windows are placed by the layout pass instead.
private func unparkChange(for window: ManagedWindow, willBeTiled: Bool, client: AXClient) -> AXClient.FrameChange? {
    guard let frame = window.frame, let screen = client.screenFrame(for: window), frame.isParked(in: screen) else { return nil }
    let savedFrame = parkedFrames.value.removeValue(forKey: window.id)
    guard !willBeTiled else { return nil }
    let restored = savedFrame ?? frame.centered(in: client.visibleScreenFrame(for: window) ?? screen)
    return AXClient.FrameChange(window: window, frame: restored, positionOnly: true)
}

private func notifyBar(store: WindowStore, workspace: Int, layout: String, position: BarPosition = .top, workspaces: WorkspaceManager? = nil) {
    let counts = Dictionary(uniqueKeysWithValues: (1...(workspaces?.count ?? 9)).map { workspace in
        (String(workspace), workspaces?.windows(in: workspace).count ?? 0)
    })
    DistributedNotificationCenter.default().post(
        name: stateNotification,
        object: nil,
        userInfo: [
            "workspace": workspace, "layout": layout, "position": position.rawValue, "windows": counts, "mode": keybinds.mode,
            "focusedApp": store.focusedWindow?.appName ?? "", "focusedTitle": store.focusedWindow?.title ?? ""
        ]
    )
    guard let events, let workspaces else { return }
    events.broadcast(StateJSON.encode(StateEvent(event: "state", state: StateSnapshot(store: store, workspaces: workspaces, layout: layout, mode: keybinds.mode))))
}

private func applyTiling(client: AXClient, store: inout WindowStore, config: Config, workspaces: inout WorkspaceManager, maximizedFrames: [WindowID: Frame], force: Bool = false) {
    guard !layoutGuard.isApplying else { return }
    layoutGuard.isApplying = true
    defer { layoutGuard.isApplying = false }
    mouseTargets.update(store.windows.filter { window in
        !window.isHidden && workspaces.workspace(for: window.id) == workspaces.activeWorkspace
    })
    guard config.autoTile || force else { return }
    guard let layoutFrame = client.layoutFrame() else { return }
    let tileableWindows = store.windows.filter {
        $0.isTileable && $0.frame != nil && maximizedFrames[$0.id] == nil && workspaces.workspace(for: $0.id) == workspaces.activeWorkspace
    }
    let windowIDs = workspaces.layoutLeaves(for: tileableWindows.map(\.id))
    let layout = workspaces.layout(for: workspaces.activeWorkspace, default: config.layout)
    let frames: [WindowID: Frame]
    let gaps = LayoutEngine.gaps(outer: config.outerGap, inner: config.innerGap, smart: config.smartGaps, windowCount: windowIDs.count)
    if layout == .bsp, let tree = workspaces.validatedLayoutTree(for: windowIDs, in: workspaces.activeWorkspace, frame: layoutFrame) {
        frames = BSPLayout.frames(for: tree, in: layoutFrame, outerGap: gaps.outer, innerGap: gaps.inner)
    } else {
        frames = LayoutEngine.frames(for: windowIDs, layout: layout, in: layoutFrame, outerGap: gaps.outer, innerGap: gaps.inner, master: config.master)
    }
    let monocleHiddenIDs = layout == .monocle ? monocleHiddenWindowIDs(tileableWindows, focusedID: store.focusedWindow?.id) : []
    var changes: [AXClient.FrameChange] = []
    var tabGroups: [GroupTabBars.Group] = []
    for window in tileableWindows {
        let isHiddenByGroup = workspaces.hiddenGroupMembers(among: [window.id]).contains(window.id)
        if monocleHiddenIDs.contains(window.id) || isHiddenByGroup {
            if let (change, _) = parkChange(for: window, keepsFrame: false, client: client) { changes.append(change) }
            continue
        }
        if let members = workspaces.group(containing: window.id), let leader = members.first, let tile = frames[leader] {
            // Only the active member is here; it takes the leader's tile under the tab strip.
            let hasTabs = members.count > 1
            let frame = hasTabs ? Frame(x: tile.x, y: tile.y + GroupTabBars.height, width: tile.width, height: max(0, tile.height - GroupTabBars.height)) : tile
            changes.append(AXClient.FrameChange(window: window, frame: frame, positionOnly: false))
            if hasTabs {
                let titles = members.map { id in (id, store.windows.first { $0.id == id }?.title ?? "") }
                tabGroups.append(GroupTabBars.Group(leader: leader, members: titles, active: window.id, frame: tile))
            }
            continue
        }
        guard let frame = frames[window.id] else { continue }
        changes.append(AXClient.FrameChange(window: window, frame: frame, positionOnly: false))
    }
    for change in changes { store.updateFrame(change.frame, for: change.window.id) }
    let queued = changes
    client.apply(queued) { result in
        FrameCorrections.rereadRejected(queued, result: result, client: client)
        FrameCorrections.floatRefusingSize(queued, result: result, client: client)
    }
    MainActor.assumeIsolated { groupTabBars.update(tabGroups) }
    print("macwm: applied \(layout.rawValue) to \(tileableWindows.count) windows")
    updateFocusBorder(store: store, config: config, workspaces: workspaces)
}

private func monocleHiddenWindowIDs(_ windows: [ManagedWindow], focusedID: WindowID?) -> Set<WindowID> {
    let visibleID = windows.first(where: { $0.id == focusedID })?.id ?? windows.first?.id
    return Set(windows.map(\.id).filter { $0 != visibleID })
}

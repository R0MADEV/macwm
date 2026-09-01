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
let runtimeConfiguration = DaemonConfiguration(ConfigLoader.load())
let keybinds = DaemonKeybinds(runtimeConfiguration.value.keybindEngine())
let client = AXClient(rules: runtimeConfiguration.value.rules)
let terminalController = TerminalController(client: client, bundleIdentifier: runtimeConfiguration.value.terminalBundleIdentifier)
let workspacePersistence = WorkspacePersistence()
let persistedState = workspacePersistence.loadState()
let workspaces = DaemonWorkspaces(assignments: persistedState.assignments, activeWorkspace: persistedState.activeWorkspace, trees: persistedState.trees ?? [:], layouts: persistedState.layouts ?? [:])
let layoutGuard = LayoutGuard()
var store = WindowStore()
var maximizedFrames: [WindowID: Frame] = [:]
let parkedFrames = ParkedFrames()
let socketPath = "/tmp/macwm.sock"
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
notifyBar(workspace: workspaces.value.activeWorkspace, layout: workspaces.value.layout(for: workspaces.value.activeWorkspace, default: runtimeConfiguration.value.layout).rawValue, position: runtimeConfiguration.value.barPosition, workspaces: workspaces.value)

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
            store.upsert(window)
            workspaces.value.register(window, rules: runtimeConfiguration.value.rules, defaultWorkspace: workspaces.value.activeWorkspace)
            store.setFocusedWindow(window.id)
            workspaces.value.recordFocus(window.id)
            print("macwm: focused \(window.appName) - \(window.title)")
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
            notifyBar(workspace: workspaces.value.activeWorkspace, layout: workspaces.value.layout(for: workspaces.value.activeWorkspace, default: runtimeConfiguration.value.layout).rawValue, position: runtimeConfiguration.value.barPosition, workspaces: workspaces.value)
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
                if !belongsToActiveWorkspace { park(window, keepsFrame: !window.isTileable, client: client, store: &store) }
            }
            applyTiling(client: client, store: &store, config: runtimeConfiguration.value, workspaces: &workspaces.value, maximizedFrames: maximizedFrames)
            workspacePersistence.save(workspaces.value.persistedAssignments, activeWorkspace: workspaces.value.activeWorkspace, trees: workspaces.value.persistedTrees, layouts: workspaces.value.persistedLayouts)
            notifyBar(workspace: workspaces.value.activeWorkspace, layout: workspaces.value.layout(for: workspaces.value.activeWorkspace, default: runtimeConfiguration.value.layout).rawValue, position: runtimeConfiguration.value.barPosition, workspaces: workspaces.value)
            print("macwm: tracking \(store.windows.count) windows")
        case .windowVisibilityChanged:
            guard !layoutGuard.isApplying else { return }
            refresh(UInt32(application.processIdentifier), client: client, store: &store)
            applyTiling(client: client, store: &store, config: runtimeConfiguration.value, workspaces: &workspaces.value, maximizedFrames: maximizedFrames, force: true)
            notifyBar(workspace: workspaces.value.activeWorkspace, layout: workspaces.value.layout(for: workspaces.value.activeWorkspace, default: runtimeConfiguration.value.layout).rawValue, position: runtimeConfiguration.value.barPosition, workspaces: workspaces.value)
        case .environmentChanged:
            guard !layoutGuard.isApplying else { return }
            let windows = managedWindows(client)
            store.replaceAll(windows)
            for window in windows {
                workspaces.value.register(window, rules: runtimeConfiguration.value.rules, defaultWorkspace: workspaces.value.activeWorkspace)
            }
            applyTiling(client: client, store: &store, config: runtimeConfiguration.value, workspaces: &workspaces.value, maximizedFrames: maximizedFrames, force: true)
            workspacePersistence.save(workspaces.value.persistedAssignments, activeWorkspace: workspaces.value.activeWorkspace, trees: workspaces.value.persistedTrees, layouts: workspaces.value.persistedLayouts)
            notifyBar(workspace: workspaces.value.activeWorkspace, layout: workspaces.value.layout(for: workspaces.value.activeWorkspace, default: runtimeConfiguration.value.layout).rawValue, position: runtimeConfiguration.value.barPosition, workspaces: workspaces.value)
        }
}
observerRegistry.start()

guard let hotkeys = HotkeyManager(keybinds: keybinds, handler: { command in
    _ = execute(command, client: client, store: &store, maximizedFrames: &maximizedFrames, configuration: runtimeConfiguration, workspaces: workspaces)
}) else {
    fputs("macwm: unable to register global hotkeys. Enable Input Monitoring for macwm-daemon.\n", stderr)
    exit(EXIT_FAILURE)
}

guard let server = UnixSocketServer(path: socketPath, handler: { command in
    execute(command, client: client, store: &store, maximizedFrames: &maximizedFrames, configuration: runtimeConfiguration, workspaces: workspaces)
}) else {
    fputs("macwm: unable to create IPC socket at \(socketPath).\n", stderr)
    exit(EXIT_FAILURE)
}

RunLoop.main.run()

withExtendedLifetime((hotkeys, server, observerRegistry)) {}

private func execute(_ command: Command, client: AXClient, store: inout WindowStore, maximizedFrames: inout [WindowID: Frame], configuration: DaemonConfiguration, workspaces: DaemonWorkspaces) -> String {
    syncFocusedWindow(client: client, store: &store)
    if let focusedID = store.focusedWindow?.id { workspaces.value.recordFocus(focusedID) }

    switch command {
    case .status:
        let focused = store.focusedWindow.map { "\($0.appName) - \($0.title)" } ?? "none"
        let layout = workspaces.value.layout(for: workspaces.value.activeWorkspace, default: configuration.value.layout).rawValue
        return "workspace: \(workspaces.value.activeWorkspace)\nlayout: \(layout)\nmode: \(keybinds.mode)\nwindows: \(store.windows.count)\nfocused: \(focused)"
    case .reload:
        guard let updatedConfiguration = ConfigLoader.loadValidated() else { return "error: invalid configuration" }
        configuration.value = updatedConfiguration
        terminalController.update(bundleIdentifier: updatedConfiguration.terminalBundleIdentifier)
        keybinds.replace(updatedConfiguration.keybindEngine())
        client.updateRules(configuration.value.rules)
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
        notifyBar(workspace: workspaces.value.activeWorkspace, layout: workspaces.value.layout(for: workspaces.value.activeWorkspace, default: configuration.value.layout).rawValue, position: configuration.value.barPosition, workspaces: workspaces.value)
        return "ok"
    case let .layout(layout):
        workspaces.value.setLayout(layout, for: workspaces.value.activeWorkspace)
        applyTiling(client: client, store: &store, config: configuration.value, workspaces: &workspaces.value, maximizedFrames: maximizedFrames, force: true)
        workspacePersistence.save(workspaces.value.persistedAssignments, activeWorkspace: workspaces.value.activeWorkspace, trees: workspaces.value.persistedTrees, layouts: workspaces.value.persistedLayouts)
        notifyBar(workspace: workspaces.value.activeWorkspace, layout: layout.rawValue, position: configuration.value.barPosition, workspaces: workspaces.value)
        return "ok"
    case let .workspace(workspace):
        return switchWorkspace(workspace, client: client, store: &store, maximizedFrames: maximizedFrames, workspaces: workspaces, config: configuration.value)
    case let .sendToWorkspace(workspace):
        guard let focusedWindow = store.focusedWindow else { return "error: no focused window" }
        guard workspaces.value.isValid(workspace) else { return "error: invalid workspace" }
        workspaces.value.assign(focusedWindow, to: workspace)
        workspacePersistence.save(workspaces.value.persistedAssignments, activeWorkspace: workspaces.value.activeWorkspace, trees: workspaces.value.persistedTrees, layouts: workspaces.value.persistedLayouts)
        return switchWorkspace(workspaces.value.activeWorkspace, client: client, store: &store, maximizedFrames: maximizedFrames, workspaces: workspaces, config: configuration.value)
    case let .focus(direction):
        let candidateIDs = activeWorkspaceWindowIDs(store: store, workspaces: workspaces.value, tileableOnly: false)
        guard let target = store.window(in: direction, among: candidateIDs), let element = client.element(for: target) else { return "error: no window in direction" }
        guard client.focus(element) else { return "error: unable to focus window" }
        store.setFocusedWindow(target.id)
        workspaces.value.recordFocus(target.id)
        applyTiling(client: client, store: &store, config: configuration.value, workspaces: &workspaces.value, maximizedFrames: maximizedFrames)
        print("macwm: focused \(target.appName) - \(target.title)")
        return "ok"
    case let .move(direction):
        guard let focusedWindow = store.focusedWindow else { return "error: no focused window" }
        applyTiling(client: client, store: &store, config: configuration.value, workspaces: &workspaces.value, maximizedFrames: maximizedFrames, force: true)
        let candidateIDs = activeWorkspaceWindowIDs(store: store, workspaces: workspaces.value, tileableOnly: true)
        guard focusedWindow.isTileable, let target = store.window(in: direction, among: candidateIDs) else { return "error: no tileable window in direction" }
        guard workspaces.value.swap(focusedWindow.id, target.id, in: workspaces.value.activeWorkspace) else { return "error: layout is not ready" }
        applyTiling(client: client, store: &store, config: configuration.value, workspaces: &workspaces.value, maximizedFrames: maximizedFrames, force: true)
        workspacePersistence.save(workspaces.value.persistedAssignments, activeWorkspace: workspaces.value.activeWorkspace, trees: workspaces.value.persistedTrees, layouts: workspaces.value.persistedLayouts)
        return "ok"
    case let .resize(operation):
        guard let focusedWindow = store.focusedWindow else { return "error: no focused window" }
        guard client.resize(focusedWindow, operation: operation) else { return "error: unable to resize window" }
        refresh(focusedWindow.processID, client: client, store: &store)
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
        terminalController.toggle()
        return "ok"
    case let .mode(name):
        keybinds.enter(mode: name)
        notifyBar(workspace: workspaces.value.activeWorkspace, layout: workspaces.value.layout(for: workspaces.value.activeWorkspace, default: configuration.value.layout).rawValue, position: configuration.value.barPosition, workspaces: workspaces.value)
        return "ok"
    }
}

/// The configured terminal is never tiled, hidden or parked; accessory apps
/// such as the bar are already filtered out by AXClient.
private func isManaged(_ window: ManagedWindow) -> Bool {
    window.bundleIdentifier != terminalController.bundleIdentifier
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

private func syncFocusedWindow(client: AXClient, store: inout WindowStore) {
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
            notifyBar(workspace: workspace, layout: workspaces.value.layout(for: workspace, default: config.layout).rawValue, position: config.barPosition, workspaces: workspaces.value)

    showWorkspaceWindows(workspace, client: client, store: &store, workspaces: workspaces.value, maximizedFrames: maximizedFrames)
    applyTiling(client: client, store: &store, config: config, workspaces: &workspaces.value, maximizedFrames: maximizedFrames, force: true)
    focusLastWindow(in: workspace, client: client, store: &store, workspaces: workspaces)
    workspacePersistence.save(workspaces.value.persistedAssignments, activeWorkspace: workspace, trees: workspaces.value.persistedTrees, layouts: workspaces.value.persistedLayouts)
    return "ok"
}

/// Returns keyboard focus to the window last used in the workspace, or to the
/// first visible one, so the user can type right after switching.
private func focusLastWindow(in workspace: Int, client: AXClient, store: inout WindowStore, workspaces: DaemonWorkspaces) {
    let candidates = store.windows.filter { !$0.isHidden && workspaces.value.workspace(for: $0.id) == workspace }
    let remembered = workspaces.value.lastFocusedWindow(in: workspace).flatMap { id in candidates.first { $0.id == id } }
    guard let target = remembered ?? candidates.first(where: \.isTileable) ?? candidates.first,
          let element = client.element(for: target), client.focus(element) else { return }
    store.setFocusedWindow(target.id)
    workspaces.value.recordFocus(target.id)
}

private func activeWorkspaceWindowIDs(store: WindowStore, workspaces: WorkspaceManager, tileableOnly: Bool) -> Set<WindowID> {
    Set(store.windows.filter { window in
        let isInActiveWorkspace = workspaces.workspace(for: window.id) == workspaces.activeWorkspace
        return isInActiveWorkspace && (!tileableOnly || window.isTileable)
    }.map(\.id))
}

/// Parks every window outside `workspace` off-screen and brings the workspace's
/// own windows back. Parking moves windows instead of minimizing them, so the
/// switch is instant and never animates through the Dock.
private func showWorkspaceWindows(_ workspace: Int, client: AXClient, store: inout WindowStore, workspaces: WorkspaceManager, maximizedFrames: [WindowID: Frame]) {
    layoutGuard.isApplying = true
    defer { layoutGuard.isApplying = false }
    for window in store.windows {
        let belongsToWorkspace = workspaces.workspace(for: window.id) == workspace
        let isTiled = window.isTileable && maximizedFrames[window.id] == nil
        guard belongsToWorkspace else {
            park(window, keepsFrame: !isTiled, client: client, store: &store)
            continue
        }
        unpark(window, willBeTiled: isTiled, client: client, store: &store)
    }
}

/// `keepsFrame` saves the live frame so floating and maximized windows come back
/// where the user left them; tiled windows are re-placed by the layout instead.
private func park(_ window: ManagedWindow, keepsFrame: Bool, client: AXClient, store: inout WindowStore) {
    guard let storedFrame = window.frame, let screen = client.screenFrame(for: window) else { return }
    let frame = keepsFrame ? client.currentFrame(for: window) ?? storedFrame : storedFrame
    guard !frame.isParked(in: screen) else { return }
    if keepsFrame { parkedFrames.value[window.id] = frame }
    let target = frame.parked(in: screen)
    guard client.setFrame(target, for: window) else { return }
    store.updateFrame(target, for: window.id)
}

private func unpark(_ window: ManagedWindow, willBeTiled: Bool, client: AXClient, store: inout WindowStore) {
    guard let frame = window.frame, let screen = client.screenFrame(for: window), frame.isParked(in: screen) else { return }
    let savedFrame = parkedFrames.value.removeValue(forKey: window.id)
    guard !willBeTiled else { return }
    let restored = savedFrame ?? frame.centered(in: client.visibleScreenFrame(for: window) ?? screen)
    guard client.setFrame(restored, for: window) else { return }
    store.updateFrame(restored, for: window.id)
}

private func notifyBar(workspace: Int, layout: String, position: BarPosition = .top, workspaces: WorkspaceManager? = nil) {
    let counts = Dictionary(uniqueKeysWithValues: (1...(workspaces?.count ?? 9)).map { workspace in
        (String(workspace), workspaces?.windows(in: workspace).count ?? 0)
    })
    DistributedNotificationCenter.default().post(
        name: stateNotification,
        object: nil,
        userInfo: ["workspace": workspace, "layout": layout, "position": position.rawValue, "windows": counts, "mode": keybinds.mode]
    )
}

private func applyTiling(client: AXClient, store: inout WindowStore, config: Config, workspaces: inout WorkspaceManager, maximizedFrames: [WindowID: Frame], force: Bool = false) {
    guard !layoutGuard.isApplying else { return }
    layoutGuard.isApplying = true
    defer { layoutGuard.isApplying = false }
    guard config.autoTile || force else { return }
    guard let screen = NSScreen.screens.first else { return }
    let visibleFrame = screen.visibleFrame
    let screenFrame = screen.frame
    let tileableWindows = store.windows.filter {
        $0.isTileable && $0.frame != nil && maximizedFrames[$0.id] == nil && workspaces.workspace(for: $0.id) == workspaces.activeWorkspace
    }
    let layoutFrame = Frame(
        x: visibleFrame.origin.x,
        y: visibleFrame.origin.y,
        width: visibleFrame.width,
        height: visibleFrame.height
    )
    let windowIDs = tileableWindows.map(\.id)
    let layout = workspaces.layout(for: workspaces.activeWorkspace, default: config.layout)
    let frames: [WindowID: Frame]
    if layout == .bsp, let tree = workspaces.validatedLayoutTree(for: windowIDs, in: workspaces.activeWorkspace) {
        frames = BSPLayout.frames(for: tree, in: layoutFrame, outerGap: config.outerGap, innerGap: config.innerGap)
    } else {
        frames = LayoutEngine.frames(for: windowIDs, layout: layout, in: layoutFrame, outerGap: config.outerGap, innerGap: config.innerGap)
    }
    var appliedCount = 0
    let monocleHiddenIDs = layout == .monocle ? monocleHiddenWindowIDs(tileableWindows, focusedID: store.focusedWindow?.id) : []

    for window in tileableWindows {
        if monocleHiddenIDs.contains(window.id) {
            park(window, keepsFrame: false, client: client, store: &store)
            continue
        }
        guard let frame = frames[window.id] else { continue }
        let accessibilityFrame = Frame(
            x: frame.x,
            y: screenFrame.maxY - frame.y - frame.height,
            width: frame.width,
            height: frame.height
        )
        guard client.setFrame(accessibilityFrame, for: window) else { continue }
        store.updateFrame(accessibilityFrame, for: window.id)
        appliedCount += 1
    }
    print("macwm: applied \(layout.rawValue) to \(appliedCount)/\(tileableWindows.count) windows")
}

private func monocleHiddenWindowIDs(_ windows: [ManagedWindow], focusedID: WindowID?) -> Set<WindowID> {
    let visibleID = windows.first(where: { $0.id == focusedID })?.id ?? windows.first?.id
    return Set(windows.map(\.id).filter { $0 != visibleID })
}

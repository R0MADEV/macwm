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

let runtimeConfiguration = DaemonConfiguration(ConfigLoader.load())
let client = AXClient(rules: runtimeConfiguration.value.rules)
let terminalController = TerminalController(client: client, bundleIdentifier: runtimeConfiguration.value.terminalBundleIdentifier)
let workspacePersistence = WorkspacePersistence()
let persistedState = workspacePersistence.loadState()
let workspaces = DaemonWorkspaces(assignments: persistedState.assignments, activeWorkspace: persistedState.activeWorkspace, trees: persistedState.trees ?? [:], layouts: persistedState.layouts ?? [:])
let layoutGuard = LayoutGuard()
var store = WindowStore()
var maximizedFrames: [WindowID: Frame] = [:]
let socketPath = "/tmp/macwm.sock"
let stateNotification = Notification.Name("com.macwm.stateChanged")

for window in managedWindows(client) {
    store.upsert(window)
    if persistedState.floating?[window.persistentKey] == true { store.setFloating(true, for: window.id) }
    workspaces.value.register(window, rules: runtimeConfiguration.value.rules, defaultWorkspace: workspaces.value.activeWorkspace)
    if let rule = client.rule(for: window) { client.apply(rule: rule, to: window) }
}

if let focusedWindow = client.focusedWindow(), focusedWindow.bundleIdentifier != terminalController.bundleIdentifier {
    store.upsert(focusedWindow)
    if persistedState.floating?[focusedWindow.persistentKey] == true { store.setFloating(true, for: focusedWindow.id) }
    workspaces.value.register(focusedWindow, rules: runtimeConfiguration.value.rules, defaultWorkspace: workspaces.value.activeWorkspace)
    store.setFocusedWindow(focusedWindow.id)
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
            guard let focusedWindow = client.focusedWindowElement(for: application) else { return }
            let focusedID = WindowID(
                processID: UInt32(application.processIdentifier),
                elementHash: Int(truncatingIfNeeded: CFHash(focusedWindow))
            )
            guard let window = client.windows(for: application).first(where: { $0.id == focusedID }) else { return }
            guard window.bundleIdentifier != terminalController.bundleIdentifier else { return }
            store.upsert(window)
            workspaces.value.register(window, rules: runtimeConfiguration.value.rules, defaultWorkspace: workspaces.value.activeWorkspace)
            store.setFocusedWindow(window.id)
            print("macwm: focused \(window.appName) - \(window.title)")
        case .windowDestroyed(let element):
            guard !layoutGuard.isApplying else { return }
            let id = WindowID(processID: UInt32(application.processIdentifier), elementHash: Int(truncatingIfNeeded: CFHash(element)))
            store.remove(id)
            maximizedFrames.removeValue(forKey: id)
            workspaces.value.remove(id)
            applyTiling(client: client, store: &store, config: runtimeConfiguration.value, workspaces: &workspaces.value, maximizedFrames: maximizedFrames)
            workspacePersistence.save(workspaces.value.persistedAssignments, activeWorkspace: workspaces.value.activeWorkspace, trees: workspaces.value.persistedTrees, layouts: workspaces.value.persistedLayouts)
            notifyBar(workspace: workspaces.value.activeWorkspace, layout: workspaces.value.layout(for: workspaces.value.activeWorkspace, default: runtimeConfiguration.value.layout).rawValue, position: runtimeConfiguration.value.barPosition, workspaces: workspaces.value)
            print("macwm: tracking \(store.windows.count) windows")
        case .windowCreated(_):
            guard !layoutGuard.isApplying else { return }
            let windows = client.windows(for: application).filter { $0.bundleIdentifier != terminalController.bundleIdentifier }
            store.replace(
                windows: windows,
                forProcessID: UInt32(application.processIdentifier)
            )
            for window in windows {
                workspaces.value.register(window, rules: runtimeConfiguration.value.rules, defaultWorkspace: workspaces.value.activeWorkspace)
                if let rule = client.rule(for: window) { client.apply(rule: rule, to: window) }
            }
            applyTiling(client: client, store: &store, config: runtimeConfiguration.value, workspaces: &workspaces.value, maximizedFrames: maximizedFrames)
            workspacePersistence.save(workspaces.value.persistedAssignments, activeWorkspace: workspaces.value.activeWorkspace, trees: workspaces.value.persistedTrees, layouts: workspaces.value.persistedLayouts)
            notifyBar(workspace: workspaces.value.activeWorkspace, layout: workspaces.value.layout(for: workspaces.value.activeWorkspace, default: runtimeConfiguration.value.layout).rawValue, position: runtimeConfiguration.value.barPosition, workspaces: workspaces.value)
            print("macwm: tracking \(store.windows.count) windows")
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

guard let hotkeys = HotkeyManager(runtimeConfiguration: runtimeConfiguration, handler: { action in
    handle(action, client: client, store: &store, maximizedFrames: &maximizedFrames, configuration: runtimeConfiguration, workspaces: workspaces)
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

private func handle(_ action: HotkeyManager.Action, client: AXClient, store: inout WindowStore, maximizedFrames: inout [WindowID: Frame], configuration: DaemonConfiguration, workspaces: DaemonWorkspaces) {
    switch action {
    case let .focus(direction):
        _ = execute(.focus(direction), client: client, store: &store, maximizedFrames: &maximizedFrames, configuration: configuration, workspaces: workspaces)
    case let .move(direction):
        _ = execute(.move(direction), client: client, store: &store, maximizedFrames: &maximizedFrames, configuration: configuration, workspaces: workspaces)
    case let .resize(operation):
        _ = execute(.resize(operation), client: client, store: &store, maximizedFrames: &maximizedFrames, configuration: configuration, workspaces: workspaces)
    case let .workspace(workspace):
        _ = execute(.workspace(workspace), client: client, store: &store, maximizedFrames: &maximizedFrames, configuration: configuration, workspaces: workspaces)
    case let .sendToWorkspace(workspace):
        _ = execute(.sendToWorkspace(workspace), client: client, store: &store, maximizedFrames: &maximizedFrames, configuration: configuration, workspaces: workspaces)
    case .maximize:
        _ = execute(.maximize, client: client, store: &store, maximizedFrames: &maximizedFrames, configuration: configuration, workspaces: workspaces)
    case .toggleFloat:
        _ = execute(.toggleFloat, client: client, store: &store, maximizedFrames: &maximizedFrames, configuration: configuration, workspaces: workspaces)
    case .toggleTerminal:
        terminalController.toggle()
    }
}

private func execute(_ command: Command, client: AXClient, store: inout WindowStore, maximizedFrames: inout [WindowID: Frame], configuration: DaemonConfiguration, workspaces: DaemonWorkspaces) -> String {
    syncFocusedWindow(client: client, store: &store)

    switch command {
    case .status:
        let focused = store.focusedWindow.map { "\($0.appName) - \($0.title)" } ?? "none"
        let layout = workspaces.value.layout(for: workspaces.value.activeWorkspace, default: configuration.value.layout).rawValue
        return "workspace: \(workspaces.value.activeWorkspace)\nlayout: \(layout)\nwindows: \(store.windows.count)\nfocused: \(focused)"
    case .reload:
        guard let updatedConfiguration = ConfigLoader.loadValidated() else { return "error: invalid configuration" }
        configuration.value = updatedConfiguration
        terminalController.update(bundleIdentifier: updatedConfiguration.terminalBundleIdentifier)
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
        guard let target = store.window(in: direction), let element = client.element(for: target) else { return "error: no window in direction" }
        guard client.focus(element) else { return "error: unable to focus window" }
        store.setFocusedWindow(target.id)
        applyTiling(client: client, store: &store, config: configuration.value, workspaces: &workspaces.value, maximizedFrames: maximizedFrames)
        print("macwm: focused \(target.appName) - \(target.title)")
        return "ok"
    case let .move(direction):
        guard let focusedWindow = store.focusedWindow else { return "error: no focused window" }
        applyTiling(client: client, store: &store, config: configuration.value, workspaces: &workspaces.value, maximizedFrames: maximizedFrames, force: true)
        let activeWorkspace = workspaces.value.activeWorkspace
        let candidateIDs = Set(store.windows.filter {
            let isInActiveWorkspace = workspaces.value.workspace(for: $0.id) == activeWorkspace
            return $0.isTileable && isInActiveWorkspace
        }.map(\.id))
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
        guard let targetFrame = client.maximizedFrame(for: focusedWindow) else { return "error: no screen" }
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
    }
}

private func managedWindows(_ client: AXClient) -> [ManagedWindow] {
    client.visibleWindows().filter { $0.bundleIdentifier != terminalController.bundleIdentifier }
}

private func persistedMaximizedFrames(store: WindowStore, maximizedFrames: [WindowID: Frame]) -> [WindowKey: Frame] {
    Dictionary(uniqueKeysWithValues: store.windows.compactMap { window in
        guard let frame = maximizedFrames[window.id] else { return nil }
        return (window.persistentKey, frame)
    })
}

private func syncFocusedWindow(client: AXClient, store: inout WindowStore) {
    guard let focusedWindow = client.focusedWindow(), focusedWindow.bundleIdentifier != terminalController.bundleIdentifier else { return }
    store.upsert(focusedWindow)
    store.setFocusedWindow(focusedWindow.id)
}

private func refresh(_ processID: UInt32, client: AXClient, store: inout WindowStore) {
    guard let application = NSRunningApplication(processIdentifier: pid_t(processID)) else { return }
    store.replace(windows: client.windows(for: application), forProcessID: processID)
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

    layoutGuard.isApplying = true
    for window in store.windows {
        let shouldHide = workspaces.value.workspace(for: window.id) != workspace
        _ = client.setHidden(shouldHide, for: window)
    }
    layoutGuard.isApplying = false

    applyTiling(client: client, store: &store, config: config, workspaces: &workspaces.value, maximizedFrames: maximizedFrames, force: true)
    workspacePersistence.save(workspaces.value.persistedAssignments, activeWorkspace: workspace, trees: workspaces.value.persistedTrees, layouts: workspaces.value.persistedLayouts)
    return "ok"
}

private func notifyBar(workspace: Int, layout: String, position: BarPosition = .top, workspaces: WorkspaceManager? = nil) {
    let counts = Dictionary(uniqueKeysWithValues: (1...(workspaces?.count ?? 9)).map { workspace in
        (String(workspace), workspaces?.windows(in: workspace).count ?? 0)
    })
    DistributedNotificationCenter.default().post(
        name: stateNotification,
        object: nil,
        userInfo: ["workspace": workspace, "layout": layout, "position": position.rawValue, "windows": counts]
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

for window in tileableWindows {
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
    if layout == .monocle {
        let visibleID = tileableWindows.first(where: { $0.id == store.focusedWindow?.id })?.id ?? tileableWindows.first?.id
        for window in tileableWindows { _ = client.setHidden(window.id != visibleID, for: window) }
    }
    print("macwm: applied \(layout.rawValue) to \(appliedCount)/\(tileableWindows.count) windows")
}

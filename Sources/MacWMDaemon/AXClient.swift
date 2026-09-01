import ApplicationServices
import AppKit
import CoreGraphics
import MacWMCore

final class AXClient {
    private var rules: [WindowRule]

    init(rules: [WindowRule] = []) {
        self.rules = rules
    }

    func updateRules(_ rules: [WindowRule]) {
        self.rules = rules
    }

    func rule(for window: ManagedWindow) -> WindowRule? {
        rules.first { $0.matches(bundleIdentifier: window.bundleIdentifier, title: window.title, subrole: window.subrole) }
    }

    func apply(rule: WindowRule, to window: ManagedWindow) {
        guard let frame = window.frame, rule.center || rule.width != nil || rule.height != nil else { return }
        guard let screen = NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        let width = rule.width ?? frame.width
        let height = rule.height ?? frame.height
        let x = rule.center ? visible.origin.x + (visible.width - width) / 2 : frame.x
        let accessibilityOriginY = NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY
        let y = rule.center ? accessibilityOriginY - visible.origin.y - (visible.height + height) / 2 : frame.y
        _ = setFrame(Frame(x: x, y: y, width: width, height: height), for: window)
    }

    func visibleWindows() -> [ManagedWindow] {
        NSWorkspace.shared.runningApplications
            .filter { !$0.isTerminated }
            .flatMap { windows(for: $0) }
    }

    /// Only regular applications, the ones with a Dock icon, are managed. Menu
    /// bar and accessory apps such as macwm-bar or border drawers keep their
    /// own windows untouched.
    func isManageable(_ application: NSRunningApplication) -> Bool {
        application.activationPolicy == .regular
    }

    func windows(for application: NSRunningApplication) -> [ManagedWindow] {
        guard isManageable(application) else { return [] }
        let element = AXUIElementCreateApplication(application.processIdentifier)
        guard let elements: [AXUIElement] = value(for: element, attribute: kAXWindowsAttribute) else { return [] }

        return elements.compactMap {
            snapshot(
                for: $0,
                processID: application.processIdentifier,
                appName: application.localizedName ?? "",
                bundleIdentifier: application.bundleIdentifier ?? "",
                isApplicationHidden: application.isHidden
            )
        }
    }

    func focusedWindow(for application: NSRunningApplication) -> ManagedWindow? {
        guard isManageable(application), let window = focusedWindowElement(for: application) else { return nil }
        return snapshot(
            for: window,
            processID: application.processIdentifier,
            appName: application.localizedName ?? "",
            bundleIdentifier: application.bundleIdentifier ?? "",
            isApplicationHidden: application.isHidden
        )
    }

    func focusedWindow() -> ManagedWindow? {
        let system = AXUIElementCreateSystemWide()
        guard let applicationElement: AXUIElement = value(for: system, attribute: kAXFocusedApplicationAttribute) else { return nil }
        var processID: pid_t = 0
        guard AXUIElementGetPid(applicationElement, &processID) == .success,
              let application = NSRunningApplication(processIdentifier: processID) else { return nil }
        return focusedWindow(for: application)
    }

    func focusedWindowElement(for application: NSRunningApplication) -> AXUIElement? {
        let element = AXUIElementCreateApplication(application.processIdentifier)
        return value(for: element, attribute: kAXFocusedWindowAttribute)
    }

    func focus(_ window: AXUIElement) -> Bool {
        var processID: pid_t = 0
        guard AXUIElementGetPid(window, &processID) == .success else { return false }
        NSRunningApplication(processIdentifier: processID)?.activate(options: [.activateIgnoringOtherApps])
        guard AXUIElementPerformAction(window, kAXRaiseAction as CFString) == .success else { return false }
        return AXUIElementSetAttributeValue(window, kAXFocusedAttribute as CFString, kCFBooleanTrue) == .success
    }

    func element(for window: ManagedWindow) -> AXUIElement? {
        guard let application = NSRunningApplication(processIdentifier: pid_t(window.processID)) else { return nil }
        let applicationElement = AXUIElementCreateApplication(application.processIdentifier)
        guard let elements: [AXUIElement] = value(for: applicationElement, attribute: kAXWindowsAttribute) else { return nil }
        return elements.first { element in
            let elementID = WindowID(
                processID: window.processID,
                elementHash: Int(truncatingIfNeeded: CFHash(element))
            )
            return elementID == window.id
        }
    }

    func move(_ window: ManagedWindow, direction: Direction, distance: Double = 40) -> Bool {
        guard let frame = window.frame else { return false }
        let offset: (x: Double, y: Double)

        switch direction {
        case .left: offset = (-distance, 0)
        case .right: offset = (distance, 0)
        case .up: offset = (0, -distance)
        case .down: offset = (0, distance)
        }

        let movedFrame = Frame(
            x: frame.x + offset.x,
            y: frame.y + offset.y,
            width: frame.width,
            height: frame.height
        )
        return setFrame(movedFrame, for: window)
    }

    func resize(_ window: ManagedWindow, operation: ResizeOperation, amount: Double = 40) -> Bool {
        guard let frame = window.frame else { return false }
        return setFrame(frame.resized(operation: operation, amount: amount), for: window)
    }

    func setFrame(_ frame: Frame, for window: ManagedWindow) -> Bool {
        guard let element = element(for: window) else { return false }
        var point = CGPoint(x: frame.x, y: frame.y)
        var size = CGSize(width: frame.width, height: frame.height)
        guard let position = AXValueCreate(.cgPoint, &point), let dimensions = AXValueCreate(.cgSize, &size) else { return false }
        let positionResult = AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, position)
        if positionResult != .success {
            // Some apps reject position-first updates. Retrying size-first also
            // gives a useful diagnostic without silently losing the layout.
            let sizeResult = AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, dimensions)
            let retryResult = AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, position)
            guard sizeResult == .success, retryResult == .success else {
                fputs("macwm: setFrame failed for \(window.appName) - \(window.title) (position \(positionResult.rawValue), size \(sizeResult.rawValue), retry \(retryResult.rawValue))\n", stderr)
                return false
            }
            return true
        }
        let sizeResult = AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, dimensions)
        guard sizeResult == .success else {
            fputs("macwm: setFrame size failed for \(window.appName) - \(window.title) (status \(sizeResult.rawValue))\n", stderr)
            return false
        }
        return true
    }

    /// Identifier of the window under a screen point, resolved through the
    /// system-wide Accessibility hit test, so it matches the ids in the store.
    func windowID(at point: CGPoint) -> WindowID? {
        var hit: AXUIElement?
        let systemWide = AXUIElementCreateSystemWide()
        guard AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &hit) == .success, let hit else { return nil }
        let role: String = value(for: hit, attribute: kAXRoleAttribute) ?? ""
        let windowElement: AXUIElement? = role == kAXWindowRole ? hit : value(for: hit, attribute: kAXWindowAttribute)
        guard let windowElement else { return nil }
        var processID: pid_t = 0
        guard AXUIElementGetPid(windowElement, &processID) == .success else { return nil }
        return WindowID(processID: UInt32(processID), elementHash: Int(truncatingIfNeeded: CFHash(windowElement)))
    }

    /// Presses the window's close button, so the application runs its own close logic.
    func close(_ window: ManagedWindow) -> Bool {
        guard let element = element(for: window), let button: AXUIElement = value(for: element, attribute: kAXCloseButtonAttribute) else { return false }
        return AXUIElementPerformAction(button, kAXPressAction as CFString) == .success
    }

    func setHidden(_ hidden: Bool, for window: ManagedWindow) -> Bool {
        guard let element = element(for: window) else { return false }
        let value = NSNumber(value: hidden)
        return AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, value) == .success
    }

    /// Live frame read from Accessibility; the stored snapshot can be stale after the user drags the window.
    func currentFrame(for window: ManagedWindow) -> Frame? {
        guard let element = element(for: window) else { return nil }
        return frame(of: element)
    }

    func isMinimized(_ window: ManagedWindow) -> Bool {
        guard let element = element(for: window) else { return false }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXMinimizedAttribute as CFString, &value) == .success else { return false }
        return (value as? NSNumber)?.boolValue ?? false
    }

    /// Visible area (without menu bar and Dock) of the screen holding the window, in Accessibility coordinates.
    func visibleScreenFrame(for window: ManagedWindow) -> Frame? {
        guard let currentFrame = window.frame, let screen = screen(for: currentFrame) else { return nil }
        return accessibilityFrame(for: screen.visibleFrame)
    }

    /// Visible area of the primary screen in Accessibility coordinates, the
    /// frame every layout is computed in.
    func layoutFrame() -> Frame? {
        guard let screen = NSScreen.screens.first else { return nil }
        return accessibilityFrame(for: screen.visibleFrame)
    }

    /// Full frame of the screen holding the window, in Accessibility coordinates.
    func screenFrame(for window: ManagedWindow) -> Frame? {
        guard let currentFrame = window.frame, let screen = screen(for: currentFrame) else { return nil }
        return accessibilityFrame(for: screen.frame)
    }

    private func snapshot(for element: AXUIElement, processID: pid_t, appName: String, bundleIdentifier: String, isApplicationHidden: Bool) -> ManagedWindow? {
        let title: String = value(for: element, attribute: kAXTitleAttribute) ?? appName
        let subrole: String = value(for: element, attribute: kAXSubroleAttribute) ?? ""
        let frame = frame(of: element)
        let isMinimized: Bool = value(for: element, attribute: kAXMinimizedAttribute) ?? false
        var sizeIsSettable = DarwinBoolean(false)
        AXUIElementIsAttributeSettable(element, kAXSizeAttribute as CFString, &sizeIsSettable)
        let isFloating = rules.first { $0.matches(bundleIdentifier: bundleIdentifier, title: title, subrole: subrole) }?.float ?? false
        return ManagedWindow(
            id: WindowID(processID: UInt32(processID), elementHash: Int(truncatingIfNeeded: CFHash(element))),
            processID: UInt32(processID),
            appName: appName,
            title: title,
            frame: frame,
            subrole: subrole,
            bundleIdentifier: bundleIdentifier,
            isFloating: isFloating,
            isHidden: isMinimized || isApplicationHidden,
            isResizable: sizeIsSettable.boolValue,
            windowNumber: windowNumber(processID: processID, title: title, frame: frame)
        )
    }

    private func frame(of element: AXUIElement) -> Frame? {
        guard let position: AXValue = value(for: element, attribute: kAXPositionAttribute),
              let size: AXValue = value(for: element, attribute: kAXSizeAttribute) else { return nil }

        var point = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(position, .cgPoint, &point), AXValueGetValue(size, .cgSize, &dimensions) else { return nil }
        return Frame(x: point.x, y: point.y, width: dimensions.width, height: dimensions.height)
    }

    private func windowNumber(processID: pid_t, title: String, frame: Frame?) -> UInt32? {
        guard let entries = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return nil }
        let candidates = entries.filter { entry in
            (entry[kCGWindowOwnerPID as String] as? pid_t) == processID &&
            (entry[kCGWindowName as String] as? String) == title
        }
        guard let frame else { return candidates.first?[kCGWindowNumber as String] as? UInt32 }
        return candidates.first { entry in
            guard let value = entry[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: value as CFDictionary) else { return false }
            return abs(bounds.origin.x - frame.x) < 1 && abs(bounds.origin.y - frame.y) < 1 &&
                abs(bounds.width - frame.width) < 1 && abs(bounds.height - frame.height) < 1
        }?[kCGWindowNumber as String] as? UInt32
    }

    private func screen(for windowFrame: Frame) -> NSScreen? {
        let center = CGPoint(x: windowFrame.x + windowFrame.width / 2, y: windowFrame.y + windowFrame.height / 2)
        return NSScreen.screens.first { screen in
            let frame = accessibilityFrame(for: screen.frame)
            return CGRect(x: frame.x, y: frame.y, width: frame.width, height: frame.height).contains(center)
        } ?? NSScreen.screens.first
    }

    /// Converts an AppKit rect (origin at the bottom-left of the primary screen)
    /// into Accessibility coordinates (origin at its top-left).
    private func accessibilityFrame(for appKitRect: CGRect) -> Frame {
        let accessibilityOriginY = NSScreen.screens.first?.frame.maxY ?? appKitRect.maxY
        return Frame(
            x: appKitRect.origin.x,
            y: accessibilityOriginY - appKitRect.origin.y - appKitRect.height,
            width: appKitRect.width,
            height: appKitRect.height
        )
    }

    private func value<T>(for element: AXUIElement, attribute: String) -> T? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success, let value else { return nil }
        return value as? T
    }
}

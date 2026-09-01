import CoreGraphics
import Foundation
import MacWMCore

final class HotkeyManager: @unchecked Sendable {
    enum Action: Sendable {
        case focus(Direction)
        case move(Direction)
        case resize(ResizeOperation)
        case maximize
        case toggleFloat
        case toggleTerminal
        case workspace(Int)
        case sendToWorkspace(Int)
    }

    private var eventTap: CFMachPort? = nil
    private var runLoopSource: CFRunLoopSource? = nil
    private let handler: (Action) -> Void
    private let runtimeConfiguration: DaemonConfiguration

    init?(runtimeConfiguration: DaemonConfiguration, handler: @escaping (Action) -> Void) {
        self.handler = handler
        self.runtimeConfiguration = runtimeConfiguration
        let keyDownMask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: keyDownMask,
            callback: macwmHotkeyCallback,
            userInfo: context
        ) else { return nil }

        self.eventTap = eventTap
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0) else { return nil }
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    deinit {
        guard let eventTap else { return }
        CGEvent.tapEnable(tap: eventTap, enable: false)
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
    }

    fileprivate func handle(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        guard let action = Self.action(for: event, config: runtimeConfiguration.value) else { return Unmanaged.passUnretained(event) }
        DispatchQueue.main.async { [weak self] in
            self?.handler(action)
        }
        return nil
    }

    fileprivate func enable() {
        guard let eventTap else { return }
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    fileprivate static func action(for event: CGEvent, config: Config) -> Action? {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let candidates: [(String, Action)] = [
            ("focus_left", .focus(.left)), ("focus_down", .focus(.down)), ("focus_up", .focus(.up)), ("focus_right", .focus(.right)),
            ("move_left", .move(.left)), ("move_down", .move(.down)), ("move_up", .move(.up)), ("move_right", .move(.right)),
            ("resize", .resize(event.flags.contains(.maskShift) ? .shrink : .grow)),
            ("maximize", .maximize), ("toggle_float", .toggleFloat), ("terminal_toggle", .toggleTerminal)
        ]
        for (name, action) in candidates where matches(config.hotkeys[name], event: event, keyCode: keyCode) { return action }
        for workspace in 1...9 {
            let binding = config.hotkeys["workspace_\(workspace)"] ?? "alt+\(workspace)"
            let matchesBinding = matches(binding, event: event, keyCode: keyCode)
                || matches("shift+\(binding)", event: event, keyCode: keyCode)
            if matchesBinding { return event.flags.contains(.maskShift) ? .sendToWorkspace(workspace) : .workspace(workspace) }
        }
        return nil
    }

    private static func matches(_ binding: String?, event: CGEvent, keyCode eventKeyCode: Int64) -> Bool {
        guard let binding else { return false }
        let parts = binding.lowercased().split(separator: "+").map(String.init)
        guard let key = parts.last, keyCode(for: key) == eventKeyCode else { return false }
        let modifiers = Set(parts.dropLast())
        return modifiers.contains("shift") == event.flags.contains(.maskShift)
            && modifiers.contains("alt") == event.flags.contains(.maskAlternate)
            && modifiers.contains("ctrl") == event.flags.contains(.maskControl)
    }

    private static func keyCode(for key: String) -> Int64? {
        ["f": 3, "h": 4, "j": 38, "k": 40, "l": 37, "r": 15, "m": 46, "grave": 50, "1": 18, "2": 19, "3": 20, "4": 21, "5": 23, "6": 22, "7": 26, "8": 28, "9": 25][key]
    }
}

private func macwmHotkeyCallback(
    _ proxy: CGEventTapProxy,
    _ type: CGEventType,
    _ event: CGEvent,
    _ userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let manager = Unmanaged<HotkeyManager>.fromOpaque(userInfo).takeUnretainedValue()
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        manager.enable()
        return Unmanaged.passUnretained(event)
    }
    guard type == .keyDown else { return Unmanaged.passUnretained(event) }
    return manager.handle(event)
}

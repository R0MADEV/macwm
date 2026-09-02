import AppKit
import Darwin
import MacWMCore

/// Runs a short AppleScript on the main thread and returns its string result.
/// macOS asks once, per target application, for permission to automate it.
enum AppleScriptRunner {
    static func run(_ source: String) -> String? {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error { fputs("macwm-bar: AppleScript failed: \(error[NSAppleScript.errorMessage] ?? error)\n", stderr) }
        return result?.stringValue
    }

    static func isRunning(_ bundleIdentifier: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
    }
}

/// Tunnelblick VPN: the pill shows whether a tunnel is up, judged from utun
/// interfaces that carry an IPv4 address, which needs no permission; clicking
/// connects or disconnects through Tunnelblick's scripting interface.
@MainActor
final class VPNModule: BarModule {
    let view: NSView
    private let pill: PillView
    private let theme: BarTheme
    private var isConnected = false
    private var tunnelName = ""

    init(theme: BarTheme) {
        self.theme = theme
        pill = PillView(theme: theme, text: "VPN")
        pill.toolTip = "Tunnelblick: click to connect or disconnect"
        view = pill
        pill.onClick = { [weak self] in self?.toggle() }
    }

    func update(_ state: BarState) {
        let running = AppleScriptRunner.isRunning("net.tunnelblick.tunnelblick")
        let connected = running && Self.hasTunnelInterface()
        if connected != isConnected {
            isConnected = connected
            tunnelName = connected ? (AppleScriptRunner.run("tell application \"Tunnelblick\" to get name of (first configuration whose state is \"CONNECTED\")") ?? "") : ""
        }
        view.isHidden = !running
        let label = theme.isVertical ? "VPN" : (connected && !tunnelName.isEmpty ? "VPN · \(tunnelName)" : "VPN")
        pill.label.stringValue = (connected ? "● " : "○ ") + label
        pill.label.textColor = connected ? theme.primary : theme.secondary
        pill.setFill(connected ? theme.accent.withAlphaComponent(0.35) : theme.pill)
    }

    private func toggle() {
        if isConnected {
            _ = AppleScriptRunner.run("tell application \"Tunnelblick\" to disconnect all")
            return
        }
        let names = (AppleScriptRunner.run("tell application \"Tunnelblick\" to get name of configurations") ?? "")
            .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !names.isEmpty else { return }
        guard names.count > 1 else {
            connect(names[0])
            return
        }
        let menu = NSMenu()
        for name in names {
            let item = NSMenuItem(title: name, action: #selector(menuChosen(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = name
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: pill.bounds.height), in: pill)
    }

    @objc private func menuChosen(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        connect(name)
    }

    private func connect(_ name: String) {
        let escaped = name.replacingOccurrences(of: "\"", with: "\\\"")
        _ = AppleScriptRunner.run("tell application \"Tunnelblick\" to connect \"\(escaped)\"")
    }

    private static func hasTunnelInterface() -> Bool {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0 else { return false }
        defer { freeifaddrs(list) }
        var pointer = list
        while let entry = pointer?.pointee {
            let name = String(cString: entry.ifa_name)
            if name.hasPrefix("utun"), entry.ifa_addr?.pointee.sa_family == UInt8(AF_INET) { return true }
            pointer = entry.ifa_next
        }
        return false
    }
}

/// Now playing: the YouTube tab in Chrome, or Spotify and Music when they
/// play, with previous, play/pause and next buttons that send the system
/// media keys, so they steer whichever player macOS considers current.
@MainActor
final class MediaModule: BarModule {
    let view: NSView
    private let title = NSTextField(labelWithString: "")
    private let theme: BarTheme
    private var lastPoll = Date.distantPast
    private var nowPlaying = ""

    init(theme: BarTheme) {
        self.theme = theme
        let stack = NSStackView()
        stack.orientation = theme.isVertical ? .vertical : .horizontal
        stack.spacing = 4
        stack.alignment = theme.isVertical ? .centerX : .centerY
        title.font = theme.font
        title.textColor = theme.primary
        title.lineBreakMode = .byTruncatingTail
        title.maximumNumberOfLines = theme.isVertical ? 2 : 1
        title.widthAnchor.constraint(lessThanOrEqualToConstant: theme.isVertical ? 44 : 260).isActive = true
        let previous = Self.button("backward.fill", theme: theme) { MediaKeys.send(.previous) }
        let play = Self.button("playpause.fill", theme: theme) { MediaKeys.send(.playPause) }
        let next = Self.button("forward.fill", theme: theme) { MediaKeys.send(.next) }
        if !theme.isVertical { stack.addArrangedSubview(title) }
        for button in [previous, play, next] { stack.addArrangedSubview(button) }
        view = stack
    }

    func update(_ state: BarState) {
        // AppleScript into other apps costs a few milliseconds; once a few seconds is plenty.
        if Date().timeIntervalSince(lastPoll) > 4 {
            lastPoll = Date()
            nowPlaying = Self.currentTitle()
        }
        title.stringValue = "♪ \(nowPlaying)"
        title.toolTip = nowPlaying
        view.isHidden = nowPlaying.isEmpty
    }

    private static func currentTitle() -> String {
        if AppleScriptRunner.isRunning("com.spotify.client"),
           let text = AppleScriptRunner.run("tell application \"Spotify\" to if player state is playing then return (artist of current track) & \" – \" & (name of current track)"), !text.isEmpty {
            return text
        }
        if AppleScriptRunner.isRunning("com.apple.Music"),
           let text = AppleScriptRunner.run("tell application \"Music\" to if player state is playing then return (artist of current track) & \" – \" & (name of current track)"), !text.isEmpty {
            return text
        }
        guard AppleScriptRunner.isRunning("com.google.Chrome") else { return "" }
        let script = """
        tell application "Google Chrome"
            repeat with w in windows
                repeat with t in tabs of w
                    if URL of t contains "youtube.com/watch" or URL of t contains "music.youtube.com" then return title of t
                end repeat
            end repeat
        end tell
        return ""
        """
        let text = AppleScriptRunner.run(script) ?? ""
        return text.replacingOccurrences(of: " - YouTube Music", with: "").replacingOccurrences(of: " - YouTube", with: "")
    }

    private static func button(_ symbol: String, theme: BarTheme, action: @escaping () -> Void) -> NSButton {
        let button = MenuButton()
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: symbol)
        button.isBordered = false
        button.contentTintColor = theme.secondary
        button.widthAnchor.constraint(equalToConstant: theme.fontSize + 6).isActive = true
        button.heightAnchor.constraint(equalToConstant: theme.fontSize + 6).isActive = true
        button.onLeftClick = action
        return button
    }
}

/// The keys on the keyboard's media row, posted as system-defined events.
enum MediaKeys {
    enum Key: Int32 {
        case playPause = 16
        case next = 17
        case previous = 18
    }

    static func send(_ key: Key) {
        for isDown in [true, false] {
            let flags = NSEvent.ModifierFlags(rawValue: isDown ? 0xa00 : 0xb00)
            let data1 = Int(key.rawValue << 16) | ((isDown ? 0xa : 0xb) << 8)
            let event = NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil, subtype: 8, data1: data1, data2: -1)
            event?.cgEvent?.post(tap: .cghidEventTap)
        }
    }
}

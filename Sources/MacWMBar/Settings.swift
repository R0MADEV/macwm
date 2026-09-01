import AppKit
import MacWMCore
import SwiftUI

/// Editable hotkey with an identity that survives edits to its binding.
struct EditableHotkey: Identifiable, Equatable {
    let id = UUID()
    var entry: HotkeyEntry
}

@MainActor
final class SettingsModel: ObservableObject {
    @Published var config: Config
    @Published var hotkeys: [EditableHotkey]
    @Published var status = ""
    let isReadOnly: Bool
    let path: String

    static let commandPresets: [String] = [
        "focus left", "focus down", "focus up", "focus right", "focus next", "focus prev",
        "move left", "move down", "move up", "move right",
        "resize grow", "resize shrink", "maximize", "toggle-float", "toggle-split", "center", "close",
        "workspace previous", "toggle-terminal", "mode resize", "mode default",
        "preselect vertical", "preselect horizontal", "layout bsp", "layout stack", "layout monocle", "layout master",
        "exec open -a Safari", "scratchpad chat"
    ] + (1...9).map { "workspace \($0)" } + (1...9).map { "send-to-workspace \($0)" }

    init() {
        let file = ConfigFile.read()
        isReadOnly = file?.isHyprland ?? false
        path = file?.path ?? ConfigFile.tomlPath
        let loaded = file.flatMap { ConfigFile.parse($0.text, isHyprland: $0.isHyprland) } ?? Config()
        config = loaded
        hotkeys = loaded.hotkeyEntries.map { EditableHotkey(entry: $0) }
    }

    var modes: [String] {
        let names = Set(hotkeys.map(\.entry.mode)).union([KeybindEngine.defaultMode])
        return names.sorted { ($0 == KeybindEngine.defaultMode ? "" : $0) < ($1 == KeybindEngine.defaultMode ? "" : $1) }
    }

    /// Ids of hotkeys that share a key within their mode.
    var conflicts: Set<UUID> {
        let groups = Dictionary(grouping: hotkeys.filter { !$0.entry.binding.isEmpty }) { "\($0.entry.mode)|\($0.entry.binding)" }
        return Set(groups.values.filter { $0.count > 1 }.flatMap { $0.map(\.id) })
    }

    var invalid: Set<UUID> {
        Set(hotkeys.filter { !KeyBinding.isValidSyntax($0.entry.binding) || Command.parse($0.entry.command) == nil }.map(\.id))
    }

    var canSave: Bool { !isReadOnly && conflicts.isEmpty && invalid.isEmpty }

    func addHotkey(mode: String) {
        hotkeys.append(EditableHotkey(entry: HotkeyEntry(mode: mode, binding: "", command: "")))
    }

    func remove(_ id: UUID) {
        hotkeys.removeAll { $0.id == id }
    }

    func save() {
        guard canSave else { return }
        var updated = config
        updated.setHotkeyEntries(hotkeys.map(\.entry))
        do {
            try updated.toml().write(toFile: ConfigFile.tomlPath, atomically: true, encoding: .utf8)
            config = updated
            status = "Saved. macwm applies changes as soon as the file is written."
        } catch {
            status = "Could not save: \(error.localizedDescription)"
        }
    }

    var runningApplications: [(name: String, bundleIdentifier: String)] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { application in
                guard let bundle = application.bundleIdentifier, let name = application.localizedName else { return nil }
                return (name, bundle)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

// MARK: - Key recorder

/// Click, then press the shortcut: the view captures the next key press and
/// reports it as binding text such as "alt+shift+h".
struct KeyRecorder: NSViewRepresentable {
    @Binding var binding: String

    func makeNSView(context: Context) -> KeyRecorderView {
        let view = KeyRecorderView()
        view.onRecord = { binding = $0 }
        return view
    }

    func updateNSView(_ view: KeyRecorderView, context: Context) {
        view.binding = binding
    }
}

final class KeyRecorderView: NSView {
    var onRecord: ((String) -> Void)?
    var binding = "" { didSet { needsDisplay = true } }
    private var isRecording = false { didSet { needsDisplay = true } }

    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 150, height: 24) }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        isRecording = true
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
        var modifiers: Set<Modifier> = []
        if event.modifierFlags.contains(.shift) { modifiers.insert(.shift) }
        if event.modifierFlags.contains(.control) { modifiers.insert(.ctrl) }
        if event.modifierFlags.contains(.option) { modifiers.insert(.alt) }
        if event.modifierFlags.contains(.command) { modifiers.insert(.cmd) }
        let recorded = KeyBinding(keyCode: Int64(event.keyCode), modifiers: modifiers).text
        binding = recorded
        onRecord?(recorded)
        isRecording = false
        window?.makeFirstResponder(nil)
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 5, yRadius: 5)
        (isRecording ? NSColor.controlAccentColor.withAlphaComponent(0.2) : NSColor.controlBackgroundColor).setFill()
        path.fill()
        (isRecording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.stroke()
        let text = isRecording ? "Press keys…" : (binding.isEmpty ? "Click to record" : binding)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: binding.isEmpty && !isRecording ? NSColor.secondaryLabelColor : NSColor.labelColor
        ]
        let size = text.size(withAttributes: attributes)
        text.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2), withAttributes: attributes)
    }
}

// MARK: - Views

struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        VStack(spacing: 0) {
            if model.isReadOnly {
                Text("You are using the Hyprland-style file \(model.path). Edit that file directly; this window is read-only.")
                    .font(.callout)
                    .padding(8)
                    .frame(maxWidth: .infinity)
                    .background(Color.yellow.opacity(0.2))
            }
            TabView {
                HotkeysTab(model: model).tabItem { Text("Hotkeys") }
                GeneralTab(model: model).tabItem { Text("General") }
                AppsTab(model: model).tabItem { Text("Apps") }
            }
            .padding()
            HStack {
                Text(model.status).font(.callout).foregroundColor(.secondary).lineLimit(1)
                Spacer()
                Button("Open file") { NSWorkspace.shared.open(URL(fileURLWithPath: model.path)) }
                Button("Save") { model.save() }
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(!model.canSave)
            }
            .padding([.horizontal, .bottom])
        }
        .frame(minWidth: 680, minHeight: 480)
    }
}

struct HotkeysTab: View {
    @ObservedObject var model: SettingsModel
    @State private var mode = KeybindEngine.defaultMode

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker("Mode", selection: $mode) {
                    ForEach(model.modes, id: \.self) { Text($0) }
                }
                .frame(maxWidth: 260)
                Spacer()
                Button("Add hotkey") { model.addHotkey(mode: mode) }
            }
            Text("Click a key field and press the shortcut. Red rows share a key or have an unknown command.")
                .font(.callout).foregroundColor(.secondary)
            List {
                ForEach($model.hotkeys) { $hotkey in
                    if hotkey.entry.mode == mode {
                        HotkeyRow(hotkey: $hotkey, isProblem: model.conflicts.contains(hotkey.id) || model.invalid.contains(hotkey.id)) {
                            model.remove(hotkey.id)
                        }
                    }
                }
            }
        }
    }
}

struct HotkeyRow: View {
    @Binding var hotkey: EditableHotkey
    let isProblem: Bool
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            KeyRecorder(binding: $hotkey.entry.binding).frame(width: 150, height: 24)
            TextField("command", text: $hotkey.entry.command)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
            Menu {
                ForEach(SettingsModel.commandPresets, id: \.self) { preset in
                    Button(preset) { hotkey.entry.command = preset }
                }
            } label: { Image(systemName: "chevron.down") }
            .menuStyle(.borderlessButton)
            .frame(width: 24)
            Button(role: .destructive) { onDelete() } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless)
        }
        .foregroundColor(isProblem ? .red : .primary)
        .padding(.vertical, 2)
    }
}

struct GeneralTab: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Picker("Layout", selection: $model.config.layout) {
                Text("BSP (dwindle)").tag(LayoutKind.bsp)
                Text("Master and stack").tag(LayoutKind.masterStack)
                Text("Stack").tag(LayoutKind.stack)
                Text("Monocle").tag(LayoutKind.monocle)
            }
            Stepper("Outer gap: \(Int(model.config.outerGap))", value: $model.config.outerGap, in: 0...64)
            Stepper("Inner gap: \(Int(model.config.innerGap))", value: $model.config.innerGap, in: 0...64)
            Toggle("Smart gaps: no gaps with a single window", isOn: $model.config.smartGaps)
            Toggle("Tile new windows automatically", isOn: $model.config.autoTile)
            Toggle("Focus follows mouse", isOn: $model.config.focusFollowsMouse)
            Picker("Bar position", selection: $model.config.barPosition) {
                Text("Top").tag(BarPosition.top)
                Text("Bottom").tag(BarPosition.bottom)
                Text("Left").tag(BarPosition.left)
                Text("Right").tag(BarPosition.right)
            }
            TextField("Terminal bundle identifier", text: $model.config.terminalBundleIdentifier)
                .font(.system(.body, design: .monospaced))
        }
        .padding()
    }
}

struct AppsTab: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Window rules").font(.headline)
                Spacer()
                Menu("Add running app") {
                    ForEach(model.runningApplications, id: \.bundleIdentifier) { application in
                        Button("\(application.name)  (\(application.bundleIdentifier))") {
                            model.config.rules.append(WindowRule(bundleIdentifier: application.bundleIdentifier, float: true))
                        }
                    }
                }
                .frame(width: 180)
            }
            List {
                ForEach(model.config.rules.indices, id: \.self) { index in
                    RuleRow(rule: $model.config.rules[index]) { model.config.rules.remove(at: index) }
                }
            }
            HStack {
                Text("Scratchpads").font(.headline)
                Spacer()
                Menu("Add running app") {
                    ForEach(model.runningApplications, id: \.bundleIdentifier) { application in
                        Button("\(application.name)  (\(application.bundleIdentifier))") {
                            let name = application.name.lowercased().replacingOccurrences(of: " ", with: "-")
                            model.config.scratchpads[name] = application.bundleIdentifier
                        }
                    }
                }
                .frame(width: 180)
            }
            List {
                ForEach(model.config.scratchpads.keys.sorted(), id: \.self) { name in
                    HStack {
                        Text(name).font(.system(.body, design: .monospaced))
                        Text(model.config.scratchpads[name] ?? "").foregroundColor(.secondary)
                        Spacer()
                        Text("scratchpad \(name)").font(.callout).foregroundColor(.secondary)
                        Button(role: .destructive) { model.config.scratchpads.removeValue(forKey: name) } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                    }
                }
            }
            .frame(maxHeight: 160)
        }
    }
}

struct RuleRow: View {
    @Binding var rule: WindowRule
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(rule.bundleIdentifier).font(.system(.body, design: .monospaced))
            if let title = rule.title { Text("title: \(title)").foregroundColor(.secondary) }
            Spacer()
            Toggle("Float", isOn: Binding(get: { rule.float }, set: { rule = rule.updating(float: $0) }))
            Stepper("Workspace: \(rule.workspace.map(String.init) ?? "any")", value: Binding(get: { rule.workspace ?? 0 }, set: { rule = rule.updating(workspace: $0 == 0 ? nil : $0) }), in: 0...9)
            Button(role: .destructive) { onDelete() } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless)
        }
    }
}

private extension WindowRule {
    func updating(float: Bool? = nil, workspace: Int?? = nil) -> WindowRule {
        WindowRule(bundleIdentifier: bundleIdentifier, title: title, subrole: subrole, float: float ?? self.float, workspace: workspace ?? self.workspace, center: center, width: width, height: height)
    }
}

// MARK: - Window

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?

    func show() {
        if window == nil {
            let model = SettingsModel()
            let hosting = NSHostingController(rootView: SettingsView(model: model))
            let window = NSWindow(contentViewController: hosting)
            window.title = "macwm Settings"
            window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
            window.setContentSize(NSSize(width: 720, height: 520))
            window.center()
            window.isReleasedWhenClosed = false
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// Re-read the file on the next open so outside edits show up.
    func reset() { window = nil }
}

import AppKit
import MacWMCore

/// Tab strips drawn above tab groups: one non-activating panel per visible
/// group in the active workspace, listing its members; clicking a tab shows
/// that member.
@MainActor
final class GroupTabBars {
    nonisolated static let height: Double = 24

    struct Group {
        let leader: WindowID
        let members: [(id: WindowID, title: String)]
        let active: WindowID
        /// Full tile of the group in Accessibility coordinates.
        let frame: Frame
    }

    private var panels: [WindowID: NSPanel] = [:]
    private let onSelect: (WindowID) -> Void

    init(onSelect: @escaping (WindowID) -> Void) {
        self.onSelect = onSelect
    }

    func update(_ groups: [Group]) {
        let leaders = Set(groups.map(\.leader))
        for (leader, panel) in panels where !leaders.contains(leader) {
            panel.orderOut(nil)
            panels.removeValue(forKey: leader)
        }
        let accessibilityOriginY = NSScreen.screens.first?.frame.maxY ?? 0
        for group in groups {
            let panel = panels[group.leader] ?? makePanel()
            panels[group.leader] = panel
            panel.contentView = makeStrip(for: group)
            let frame = NSRect(x: group.frame.x, y: accessibilityOriginY - group.frame.y - Self.height, width: group.frame.width, height: Self.height)
            panel.setFrame(frame, display: true)
            panel.orderFrontRegardless()
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = true
        panel.backgroundColor = NSColor(calibratedWhite: 0.12, alpha: 1)
        panel.hasShadow = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        return panel
    }

    private func makeStrip(for group: Group) -> NSView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = 1
        stack.edgeInsets = NSEdgeInsets(top: 2, left: 2, bottom: 2, right: 2)
        for member in group.members {
            let button = TabButton(title: member.title.isEmpty ? "Untitled" : member.title, id: member.id) { [weak self] id in self?.onSelect(id) }
            let isActive = member.id == group.active
            button.isBordered = false
            button.wantsLayer = true
            button.layer?.cornerRadius = 4
            button.layer?.backgroundColor = (isActive ? NSColor(calibratedRed: 0.18, green: 0.34, blue: 0.56, alpha: 1) : NSColor(calibratedWhite: 0.2, alpha: 1)).cgColor
            button.contentTintColor = isActive ? NSColor(calibratedWhite: 0.98, alpha: 1) : NSColor(calibratedWhite: 0.7, alpha: 1)
            button.font = .systemFont(ofSize: 11, weight: isActive ? .semibold : .regular)
            button.lineBreakMode = .byTruncatingTail
            stack.addArrangedSubview(button)
        }
        return stack
    }
}

private final class TabButton: NSButton {
    private let id: WindowID
    private let onSelect: (WindowID) -> Void

    init(title: String, id: WindowID, onSelect: @escaping (WindowID) -> Void) {
        self.id = id
        self.onSelect = onSelect
        super.init(frame: .zero)
        self.title = title
        target = self
        action = #selector(tabSelected)
    }

    required init?(coder: NSCoder) { nil }

    @objc private func tabSelected() { onSelect(id) }
}

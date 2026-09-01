import AppKit
import MacWMCore

/// A transparent, click-through window that draws a frame around the focused
/// window. Gaps leave room for it, so it never covers neighboring content.
@MainActor
final class FocusBorder {
    private var window: NSWindow?
    private let view = BorderView()

    func update(options: BorderOptions, focused: Frame?) {
        guard options.enabled, options.width > 0, let focused, let rgba = BorderOptions.rgba(options.color) else {
            window?.orderOut(nil)
            return
        }
        let window = self.window ?? makeWindow()
        view.width = options.width
        view.color = NSColor(red: rgba.red, green: rgba.green, blue: rgba.blue, alpha: rgba.alpha)
        let accessibilityOriginY = NSScreen.screens.first?.frame.maxY ?? 0
        let outset = options.width
        let frame = NSRect(
            x: focused.x - outset,
            y: accessibilityOriginY - focused.y - focused.height - outset,
            width: focused.width + outset * 2,
            height: focused.height + outset * 2
        )
        window.setFrame(frame, display: true)
        view.needsDisplay = true
        window.orderFrontRegardless()
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        window.contentView = view
        self.window = window
        return window
    }
}

private final class BorderView: NSView {
    var width: Double = 3
    var color = NSColor.systemBlue

    override func draw(_ dirtyRect: NSRect) {
        let inset = CGFloat(width) / 2
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: inset, dy: inset), xRadius: 8, yRadius: 8)
        path.lineWidth = CGFloat(width)
        color.setStroke()
        path.stroke()
    }
}

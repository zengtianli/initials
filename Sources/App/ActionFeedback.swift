import AppKit

/// A short nonactivating message; errors never take keyboard focus.
enum ActionFeedback {
    private static var panel: NSPanel?
    private static var closing: DispatchWorkItem?
    static func show(_ message: String) {
        closing?.cancel(); panel?.close()
        let window = ActionFeedbackPanel(contentRect: NSRect(x: 0, y: 0, width: 440, height: 90), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        window.level = .popUpMenu; window.isFloatingPanel = true; window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        let text = NSTextField(wrappingLabelWithString: "Initials · " + message)
        text.frame = NSRect(x: 18, y: 16, width: 404, height: 58)
        window.contentView?.addSubview(text)
        if let screen = NSScreen.main?.visibleFrame { window.setFrameOrigin(NSPoint(x: screen.midX - 220, y: screen.maxY - 120)) }
        panel = window; window.orderFrontRegardless()
        let work = DispatchWorkItem { window.close(); if panel === window { panel = nil } }
        closing = work; DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: work)
    }
}

private final class ActionFeedbackPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

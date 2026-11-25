import AppKit

/// Small panel that records a new keyboard shortcut. Esc cancels, Delete removes the shortcut.
/// It's a non-activating panel (like Spotlight): it takes keyboard input without activating the app,
/// which macOS may refuse for a menu bar app.
final class ShortcutRecorder: NSObject, NSWindowDelegate {
    /// Called with the new shortcut, or nil when it was removed. Not called on cancel.
    var onRecord: ((Shortcut?) -> Void)?

    private var panel: NSPanel?
    private var monitor: Any?
    private var hint: NSTextField!

    func show() {
        if let panel { panel.makeKeyAndOrderFront(nil); return }
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 120),
                        styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.becomesKeyOnlyIfNeeded = false
        p.title = L("Keyboard Shortcut")
        p.isReleasedWhenClosed = false
        p.level = .floating
        p.delegate = self

        let title = NSTextField(labelWithString: L("Press the new shortcut"))
        title.font = .systemFont(ofSize: NSFont.systemFontSize + 2, weight: .semibold)
        title.alignment = .center
        hint = NSTextField(labelWithString: L("Esc to cancel, Delete to remove"))
        hint.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        hint.textColor = .secondaryLabelColor
        hint.alignment = .center
        let stack = NSStackView(views: [title, hint])
        stack.orientation = .vertical
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        p.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: p.contentView!.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: p.contentView!.centerYAnchor, constant: -4),
        ])

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            self?.handle(e)
            return nil
        }
        panel = p
        p.center()
        p.makeKeyAndOrderFront(nil)
    }

    private func handle(_ event: NSEvent) {
        switch Int(event.keyCode) {
        case 53:                       // Esc
            close()
        case 51, 117:                  // Delete, Forward Delete
            onRecord?(nil)
            close()
        default:
            if let shortcut = Shortcut(event: event) {
                onRecord?(shortcut)
                close()
            } else {
                hint.stringValue = L("Use at least one of ⌘, ⌥ or ⌃")
                NSSound.beep()
            }
        }
    }

    private func close() { panel?.close() }

    func windowWillClose(_ notification: Notification) {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        panel = nil
    }
}

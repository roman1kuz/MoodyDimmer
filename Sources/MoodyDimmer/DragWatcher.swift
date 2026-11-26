import AppKit

/// Watches drag and drop (files, clips, text) between apps: when the dragged item leaves
/// the source app's windows, the effect is removed from the display under it so you can see where to drop it.
/// The other displays keep it; moving the item to another display moves the gap there.
///
/// No timers: global mouse monitors. A real drag and drop differs from moving a window or
/// selecting because the source writes to the system drag pasteboard, which bumps its changeCount.
final class DragWatcher {
    /// The display (its frame) under the dragged item while it's outside the source windows: the effect goes
    /// from there. nil: no such drag.
    var onScreenChanged: ((CGRect?) -> Void)?

    private var monitors: [Any] = []
    private let dragPasteboard = NSPasteboard(name: .drag)
    private var countAtMouseDown = 0
    private var downPoint: NSPoint = .zero
    private var lastCheck: TimeInterval = 0
    /// The source app's windows (Cocoa coordinates), known once the drag has started.
    private var sourceRects: [CGRect]?
    private var screen: CGRect?
    private let ownPID = ProcessInfo.processInfo.processIdentifier

    var isRunning: Bool { !monitors.isEmpty }

    func start() {
        guard monitors.isEmpty else { return }
        let add: (NSEvent.EventTypeMask, @escaping (NSEvent) -> Void) -> Void = { mask, handler in
            if let m = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handler) { self.monitors.append(m) }
        }
        add(.leftMouseDown) { [weak self] e in self?.mouseDown(e) }
        add(.leftMouseDragged) { [weak self] e in self?.mouseDragged(e) }
        add(.leftMouseUp) { [weak self] _ in self?.mouseUp() }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        mouseUp()
    }

    private func mouseDown(_ e: NSEvent) {
        countAtMouseDown = dragPasteboard.changeCount
        downPoint = NSEvent.mouseLocation
        lastCheck = 0
        sourceRects = nil
        setScreen(nil)
    }

    private func mouseDragged(_ e: NSEvent) {
        let p = NSEvent.mouseLocation
        if sourceRects == nil {
            // Not yet known whether this is a drag: check the pasteboard at most every 50 ms and only after
            // a noticeable move, so window moves and selections don't cost extra calls.
            guard hypot(p.x - downPoint.x, p.y - downPoint.y) > 4, e.timestamp - lastCheck > 0.05 else { return }
            lastCheck = e.timestamp
            guard dragPasteboard.changeCount != countAtMouseDown else { return }
            sourceRects = Self.windowsOfApp(at: downPoint, excluding: ownPID)
        }
        guard let rects = sourceRects else { return }
        guard !rects.contains(where: { $0.contains(p) }) else { setScreen(nil); return }
        // Off every display for a moment (a corner between displays): keep the one it was on.
        setScreen(NSScreen.screens.first { NSMouseInRect(p, $0.frame, false) }?.frame ?? screen)
    }

    private func mouseUp() {
        sourceRects = nil
        setScreen(nil)
    }

    private func setScreen(_ value: CGRect?) {
        guard value != screen else { return }
        screen = value
        onScreenChanged?(value)
    }

    /// All visible normal windows of the app that owns the window under the point (where the drag began).
    private static func windowsOfApp(at point: NSPoint, excluding ownPID: pid_t) -> [CGRect] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return [] }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        var windows: [(pid: pid_t, rect: CGRect)] = []
        for w in list {
            guard (w[kCGWindowLayer as String] as? Int) == 0,
                  let pid = w[kCGWindowOwnerPID as String] as? pid_t, pid != ownPID,
                  (w[kCGWindowAlpha as String] as? Double ?? 1) > 0.01,
                  let bd = w[kCGWindowBounds as String] as? NSDictionary,
                  let r = CGRect(dictionaryRepresentation: bd as CFDictionary)
            else { continue }
            windows.append((pid, CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)))
        }
        // The list goes front to back: the first window under the point is the drag source.
        guard let source = windows.first(where: { $0.rect.contains(point) }) else { return [] }
        return windows.filter { $0.pid == source.pid }.map(\.rect)
    }
}

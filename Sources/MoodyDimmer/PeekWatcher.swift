import AppKit

/// Highlight Window Under Pointer: when the pointer rests on a dimmed window for `delay`, the effect moves below that
/// window, so it and every window above it are bright, without it becoming active. From then on, moving onto
/// another window that isn't the active one moves the effect below that one (after a short `switchDelay`), and
/// moving onto the active window, the desktop, the menu bar or the Dock brings the effect back.
///
/// The delay counts while the pointer stays over the same app's windows: many apps draw one window as several
/// (toolbars, panels, helper windows), and moving across them mustn't start the count over.
///
/// Only normal windows that are currently dimmed take part: not the desktop, its icons, the menu bar, the Dock,
/// panels or notifications on other window levels, and not windows that are bright anyway. With several displays
/// each one counts on its own: the highlight is of a window below that display's top window.
///
/// Cost: each pointer move is checked against the bright area and a cached list of window frames. The window
/// list is read only when the pointer enters a dimmed area, at most every `snapshotInterval` while it moves there,
/// and once more when the delay ends.
final class PeekWatcher {
    private let tracker: FocusTracker
    private let delay: TimeInterval = 1.5
    private let snapshotInterval: TimeInterval = 0.5
    /// While the effect is below a window, a move to another window applies after this short pause, so passing over
    /// gaps and background windows on the way doesn't count.
    private let switchDelay: TimeInterval = 0.3
    /// Moving between windows switches quickly then, so the frames are kept fresher.
    private let engagedSnapshotInterval: TimeInterval = 0.25
    /// How long a requested highlight may take to be applied before it's given up.
    private let applyTimeout: TimeInterval = 0.5
    private var peekRequestedAt: TimeInterval = 0
    private var staleRefreshRequested = false

    /// The app whose window is under the pointer, which the delay counts for, and when it ends.
    private var candidatePID: pid_t?
    private var dwell: DispatchWorkItem?
    /// A pending change while the effect is below a window: the window it moves below next (nil: back to normal).
    private var switchTarget: CGWindowID?
    private var switchWork: DispatchWorkItem?

    private struct WindowInfo {
        let id: CGWindowID
        let pid: pid_t
        let frame: CGRect      // global Cocoa coordinates
        let isNormal: Bool     // layer 0
    }
    private var snapshot: [WindowInfo] = []
    private var snapshotTime: TimeInterval = -.infinity
    private let ownPID = ProcessInfo.processInfo.processIdentifier

    init(tracker: FocusTracker) {
        self.tracker = tracker
    }

    /// Ends any highlight and forgets the pointer (the feature was turned off, or the effect is off).
    func reset() {
        cancelDwell()
        cancelSwitch()
        snapshot = []
        snapshotTime = -.infinity
        tracker.peekWindowID = nil
    }

    /// p is in global Quartz coordinates (PointerMonitor).
    func pointerMoved(_ quartz: CGPoint, at now: TimeInterval) {
        guard let main = tracker.lastTarget else { cancelDwell(); return }
        let p = Self.cocoa(quartz)
        let target = main.target(at: p)  // nil: a display without the effect

        // The effect is below a window: it stays while the pointer is on that window's visible part. Moving onto
        // another window that isn't the active one moves the effect below that window at once; moving onto the
        // active window, the desktop, the menu bar or the Dock brings the effect back.
        // A change waits `switchDelay`, so passing over gaps and background windows on the way doesn't count.
        if let peek = tracker.peekWindowID {
            guard let holder = main.all.first(where: { $0.peekID == peek }) else {
                // Requested but not applied yet. If it still isn't after a moment, it never will be (the tracker
                // skipped the refresh): drop it rather than wait forever.
                guard now - peekRequestedAt > applyTimeout else { return }
                log.debug("highlight of \(peek) wasn't applied: dropped")
                tracker.peekWindowID = nil
                return
            }
            cancelDwell()
            if let region = holder.peekRegion, region.contains(p) { cancelSwitch(); return }
            if now - snapshotTime > engagedSnapshotInterval { takeSnapshot(at: now) }
            let next = nextPeek(at: p, target: target, current: peek)
            if switchWork != nil, switchTarget == next { return }  // already waiting for this change
            cancelSwitch()
            switchTarget = next
            let work = DispatchWorkItem { [weak self] in self?.switchEnded(to: next, from: peek) }
            switchWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + switchDelay, execute: work)
            return
        }
        // On a bright window (the active one, the app's other windows it keeps bright) or a display without the
        // effect: nothing to do.
        guard let target, !isOnActive(p, target: target, now: now) else {
            cancelDwell()
            return
        }
        // In the dimmed area: which window is under the pointer?
        if now - snapshotTime > snapshotInterval { takeSnapshot(at: now) }
        guard let window = dimmedWindow(at: p, target: target) else {
            if dwell != nil { log.debug("count cancelled: no dimmed window under the pointer") }
            cancelDwell()
            return
        }
        if dwell != nil, window.pid == candidatePID { return }  // still the same app: keep counting
        cancelDwell()
        let pid = window.pid
        candidatePID = pid
        log.debug("pointer on a dimmed window of pid \(pid): highlight in \(self.delay, format: .fixed(precision: 1)) s")
        let work = DispatchWorkItem { [weak self] in self?.dwellEnded(for: pid) }
        dwell = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Whether the pointer is on the active window (or a window of the active app that's kept bright). The tracker's
    /// frames are the fast check, but they can be out of date when a window moved or resized without an
    /// Accessibility notice, so a hit there is confirmed against the window list; a stale target gets refreshed.
    private func isOnActive(_ p: CGPoint, target: FocusTarget, now: TimeInterval) -> Bool {
        guard target.activeRegion.contains(p) else { return false }
        if now - snapshotTime > snapshotInterval { takeSnapshot(at: now) }
        guard let window = windowUnder(p) else { return staleTarget() }
        if window.id == target.topID || isAboveTop(window, target: target) { return true }
        let activePID = snapshot.first(where: { $0.id == target.topID })?.pid
        if window.pid == activePID, target.holes?.contains(p) == true { return true }
        return staleTarget()
    }

    /// The window lies above the top window, so above the overlay and bright (on another display: a window
    /// reaching onto it from the display with the active window).
    private func isAboveTop(_ window: WindowInfo, target: FocusTarget) -> Bool {
        guard let i = snapshot.firstIndex(where: { $0.id == window.id }),
              let top = snapshot.firstIndex(where: { $0.id == target.topID }) else { return false }
        return i < top
    }

    /// The window under the point if it's one that's dimmed: a normal window below the top window.
    private func dimmedWindow(at p: CGPoint, target: FocusTarget) -> WindowInfo? {
        guard let window = windowUnder(p), window.id != target.topID, !isAboveTop(window, target: target) else { return nil }
        return window
    }

    /// The tracker's idea of where the active window is doesn't match the screen.
    private func staleTarget() -> Bool {
        if !staleRefreshRequested {
            staleRefreshRequested = true
            log.debug("the active window's frame is out of date: refreshing")
            tracker.scheduleUpdate()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.staleRefreshRequested = false }
        }
        return false
    }

    /// Where the effect goes when the pointer leaves the window it's below: below the window now under the pointer,
    /// or nil (back to normal) over the active window, the desktop, the menu bar or the Dock.
    private func nextPeek(at p: CGPoint, target: FocusTarget?, current: CGWindowID) -> CGWindowID? {
        let now = ProcessInfo.processInfo.systemUptime
        guard let target, !isOnActive(p, target: target, now: now), let window = dimmedWindow(at: p, target: target),
              window.id != current else { return nil }
        return window.id
    }

    private func switchEnded(to next: CGWindowID?, from peek: CGWindowID) {
        switchWork = nil
        switchTarget = nil
        guard tracker.peekWindowID == peek, let main = tracker.lastTarget else { return }
        let p = NSEvent.mouseLocation
        if main.all.contains(where: { $0.peekID == peek && $0.peekRegion?.contains(p) == true }) { return }  // came back
        takeSnapshot(at: ProcessInfo.processInfo.systemUptime)
        let target = main.target(at: p)
        guard nextPeek(at: p, target: target, current: peek) == next else { return }  // moved on: the next move decides
        if let next {
            log.debug("pointer moved to window \(next): the effect moves below it")
        } else {
            log.debug("highlight ended: the pointer left window \(peek)")
        }
        if let next, let target { request(next, over: target) } else { tracker.peekWindowID = nil }
    }

    /// `target` is the one of the window's display.
    private func request(_ id: CGWindowID, over target: FocusTarget) {
        peekRequestedAt = ProcessInfo.processInfo.systemUptime
        tracker.highlight(id, over: target.topID)
    }

    private func cancelSwitch() {
        switchWork?.cancel()
        switchWork = nil
        switchTarget = nil
    }

    /// A mouse button went down: a click or a drag starts, so no highlight is pending.
    func buttonPressed() {
        if dwell != nil { log.debug("count cancelled: mouse button pressed") }
        cancelDwell()
    }

    private func dwellEnded(for pid: pid_t) {
        dwell = nil
        candidatePID = nil
        // Still on a dimmed window of that app?
        let p = NSEvent.mouseLocation
        guard let target = tracker.lastTarget?.target(at: p),
              !isOnActive(p, target: target, now: ProcessInfo.processInfo.systemUptime) else {
            log.debug("highlight skipped: the pointer is on a bright area now")
            return
        }
        takeSnapshot(at: ProcessInfo.processInfo.systemUptime)
        guard let window = dimmedWindow(at: p, target: target), window.pid == pid else {
            log.debug("highlight skipped: the pointer moved to another app's window")
            return
        }
        log.debug("highlight window \(window.id)")
        request(window.id, over: target)
    }

    private func cancelDwell() {
        dwell?.cancel()
        dwell = nil
        candidatePID = nil
    }

    /// The normal window under the point, or nil over the desktop, the menu bar, the Dock and other system UI.
    /// Floating windows of other apps (e.g. a notch utility's mostly transparent panel) aren't in the snapshot,
    /// so they don't hide the windows below them.
    private func windowUnder(_ p: CGPoint) -> WindowInfo? {
        guard let w = snapshot.first(where: { $0.frame.contains(p) }), w.isNormal else { return nil }
        return w
    }

    private func takeSnapshot(at now: TimeInterval) {
        snapshotTime = now
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { snapshot = []; return }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        snapshot = list.compactMap { w in
            // Our own windows (the overlays, the menu) let clicks through or come and go: skip them.
            guard let pid = w[kCGWindowOwnerPID as String] as? pid_t, pid != ownPID,
                  (w[kCGWindowAlpha as String] as? Double ?? 1) > 0.01,
                  let id = w[kCGWindowNumber as String] as? CGWindowID,
                  let bd = w[kCGWindowBounds as String] as? NSDictionary,
                  let r = CGRect(dictionaryRepresentation: bd as CFDictionary), r.width > 8, r.height > 8
            else { return nil }
            let isNormal = (w[kCGWindowLayer as String] as? Int) == 0
            // Other window levels block only when they're macOS's own UI (the Dock, the menu bar, Notification
            // Center…): third-party floating windows are often large and mostly transparent.
            if !isNormal, !isSystemProcess(pid) { return nil }
            let frame = CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
            return WindowInfo(id: id, pid: pid, frame: frame, isNormal: isNormal)
        }
    }

    private var systemProcesses: [pid_t: Bool] = [:]

    /// A process of macOS itself: an Apple app or a process without an app bundle (WindowServer).
    private func isSystemProcess(_ pid: pid_t) -> Bool {
        if let known = systemProcesses[pid] { return known }
        let bundle = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
        let system = bundle.map { $0.hasPrefix("com.apple.") } ?? true
        systemProcesses[pid] = system
        return system
    }

    /// Global Quartz (origin top left of the main screen) → global Cocoa (origin bottom left).
    private static func cocoa(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x, y: (NSScreen.screens.first?.frame.height ?? 0) - p.y)
    }
}

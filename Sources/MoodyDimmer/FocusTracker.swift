import AppKit
import ApplicationServices
import os

let log = Logger(subsystem: "io.github.roman1kuz.moodydimmer", category: "focus")

/// What has to stay bright on one display.
///
/// With several displays each one keeps its own top window bright: the target of the display holding the active
/// window (activeScreen) carries the targets of the others in `others`, each built the same way around the top
/// window on that display. With Dim Active Display Only there are no others, and the other displays get no effect.
struct FocusTarget: Equatable {
    /// Top window of the active app (on another display: that display's top window).
    let topID: CGWindowID
    /// The window the overlay goes right below: the top window, or the window under the pointer while the effect
    /// is moved below it (Highlight Window Under Pointer).
    let orderBelowID: CGWindowID
    /// Extra holes (the app's other windows minus overlaps, windows tiled with the top window), global Cocoa
    /// coordinates.
    let holes: CGPath?
    /// Windows laid out side by side with the top window (Keep Tiled Windows Bright): bright with it.
    let tiledIDs: [CGWindowID]
    /// Screens fully covered by the active window (full screen video, app in full screen).
    /// No effect there: nothing to dim, and in a full screen Space the overlay would end up above the window.
    let fullscreenScreens: [CGRect]
    /// The display this target is for: the one holding most of the top window, global Cocoa coordinates.
    let activeScreen: CGRect?
    /// The overlay already sits right below orderBelowID. If not, reorder even if everything else matches.
    let orderOK: Bool
    /// orderBelowID is under our overlay (the active window went away and the one left below it takes over, or the
    /// effect moves below the window under the pointer), so it has to be uncovered smoothly rather than just rise
    /// above the overlay.
    let coveredByOverlay: Bool
    /// What stays bright: the top window plus the holes, plus what's revealed under the pointer, global Cocoa
    /// coordinates.
    let brightRegion: CGPath
    /// The active part alone: the top window plus the holes, without what's revealed under the pointer.
    let activeRegion: CGPath
    /// Windows currently above our overlay, so bright whatever we thought (e.g. a just-launched app's window that
    /// appeared before we knew about it). nil when the overlay isn't on screen. Global Cocoa coordinates.
    let aboveOverlay: CGPath?
    /// The dimmed window the pointer rests on (Highlight Window Under Pointer): the effect moves below it, so it and
    /// every window above it are bright. peekRegion is its visible part (minus windows on top of it), global Cocoa
    /// coordinates: the pointer has to stay there.
    let peekID: CGWindowID?
    let peekRegion: CGPath?
    /// Raw inputs for a cheap comparison.
    fileprivate let signature: [CGRect]
    /// The targets of the other displays (only on the active display's target).
    fileprivate(set) var others: [FocusTarget] = []

    /// This target and the other displays' ones.
    var all: [FocusTarget] { [self] + others }

    /// The target for a display, or nil when it gets no effect (no window on it, or Dim Active Display Only).
    func target(on screen: CGRect) -> FocusTarget? {
        all.first { $0.activeScreen == screen }
    }

    /// The target for the display under a point, or nil when that display gets no effect.
    func target(at p: CGPoint) -> FocusTarget? {
        all.first { $0.activeScreen?.contains(p) == true }
    }

    static func == (a: FocusTarget, b: FocusTarget) -> Bool {
        a.topID == b.topID && a.peekID == b.peekID && a.signature == b.signature && a.fullscreenScreens == b.fullscreenScreens
            && a.activeScreen == b.activeScreen && a.tiledIDs == b.tiledIDs && a.others == b.others
    }
}

/// Tracks the active window from events only: NSWorkspace + AXObserver. No polling timers.
final class FocusTracker {
    /// Called when the target changes (nil: no windows on screen, or the desktop is active).
    var onTarget: ((FocusTarget?) -> Void)?

    var mode: FocusMode = .app {
        didSet {
            guard mode != oldValue, running else { return }
            if let pid = observedPID { attach(pid: pid) }
            refresh(force: true)
        }
    }

    /// With several displays, whether the displays without the active window get the effect too, each around its
    /// own top window (off: Dim Active Display Only).
    var dimOtherScreens = true {
        didSet {
            guard dimOtherScreens != oldValue, running else { return }
            refresh(force: true)
        }
    }

    /// Windows laid out side by side with the top window stay bright with it (Keep Tiled Windows Bright).
    var keepTiledBright = true {
        didSet {
            guard keepTiledBright != oldValue, running else { return }
            refresh(force: true)
        }
    }

    /// Corner radius of the holes (≈ macOS window corner radius).
    var holeCornerRadius: CGFloat = 14

    private(set) var lastTarget: FocusTarget?

    /// A dimmed window to show bright while the pointer rests on it (set by PeekWatcher through `highlight`); nil =
    /// none. It's dropped when it's no longer on screen, no longer dimmed, or the top window of its display changes.
    var peekWindowID: CGWindowID? {
        didSet {
            guard peekWindowID != oldValue else { return }
            if peekWindowID == nil { peekForTopID = nil }
            scheduleUpdate()
        }
    }
    /// The top window of the highlighted window's display when the highlight started.
    private var peekForTopID: CGWindowID?

    /// Shows a dimmed window bright: `top` is the top window of its display now.
    func highlight(_ id: CGWindowID, over top: CGWindowID) {
        peekForTopID = top
        if peekWindowID == id { scheduleUpdate() } else { peekWindowID = id }
    }
    private var delivered = false
    private var running = false
    private var updatePending = false

    private var observer: AXObserver?
    private var appElement: AXUIElement?
    private var observedPID: pid_t?
    private var attachRetries = 0
    private var workspaceTokens: [NSObjectProtocol] = []
    private var distributedTokens: [NSObjectProtocol] = []
    private var mouseMonitor: Any?
    private var mouseDownMonitor: Any?
    /// A Finder window was closed or minimized while Finder was active. macOS keeps Finder active after its last
    /// window goes, which looks just like the desktop being clicked, but the user is still working with the
    /// windows left: they keep the effect (the top one bright). Cleared when another app activates or a click lands
    /// while Finder is active (on the desktop, or Finder's menu).
    private var finderWindowClosed = false
    private let ownPID = ProcessInfo.processInfo.processIdentifier
    /// Screens currently showing a full screen Space. The Space type changes only on a Space change,
    /// so it is computed once per event, not on every refresh.
    private var fullscreenSpaceScreens: [CGRect] = []
    /// The active app has no windows, so the target is the top window on screen, whoever owns it. Other apps'
    /// windows can come and go without any activation or AX event then, so WindowServer's window events trigger
    /// a refresh while this is set (and are ignored otherwise).
    private var followingTopWindow = false
    /// The active app is launching and has no window yet. Its first window may show up before the app answers
    /// AX (so no WindowCreated arrives): WindowServer's window events trigger a refresh meanwhile.
    private var waitingForLaunchWindow = false
    /// Windows AX reported closed or minimized that WindowServer still lists while their close animation runs
    /// (about 0.2–0.3 s). Skipping them lets the effect move on right away, alongside the animation, instead of
    /// waiting until the window leaves the list.
    private var leavingWindows: Set<CGWindowID> = []
    /// Window numbers of the observed AX windows: a destroyed element no longer tells its number.
    private var windowIDs: [AXUIElement: CGWindowID] = [:]
    private var subscribedToWindowEvents = false

    // MARK: - Lifecycle

    func start() {
        guard !running else { return }
        running = true
        if !subscribedToWindowEvents {
            subscribedToWindowEvents = true
            WindowEvents.subscribe { [weak self] type, window in
                guard let self, self.running else { return }
                // The bright window itself was destroyed: react at once instead of waiting for a delayed recheck
                // (a close is usually caught earlier through AX). While following the top window, any change counts.
                if self.followingTopWindow || (self.waitingForLaunchWindow && type == WindowEvents.shown)
                    || (type == WindowEvents.destroyed && window == self.lastTarget?.topID) {
                    self.scheduleUpdate()
                }
            }
        }
        let nc = NSWorkspace.shared.notificationCenter
        workspaceTokens = [
            nc.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                self?.frontAppChanged(app?.processIdentifier)
            },
            // After an app quits, macOS activates the next one with a delay, or none at all.
            nc.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
                self?.scheduleUpdate()
                self?.refreshSoon()
            },
            nc.addObserver(forName: NSWorkspace.didHideApplicationNotification, object: nil, queue: .main) { [weak self] _ in
                self?.scheduleUpdate()
                self?.refreshSoon()
            },
        ]
        // After a Space change, wake, unlock or user switch the active app may stay the same,
        // so no activation notification arrives: recompute explicitly.
        for name in [NSWorkspace.activeSpaceDidChangeNotification,
                     NSWorkspace.didWakeNotification,
                     NSWorkspace.screensDidWakeNotification,
                     NSWorkspace.sessionDidBecomeActiveNotification] {
            workspaceTokens.append(nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                log.debug("system event: \(note.name.rawValue, privacy: .public)")
                self?.resync()
            })
        }
        distributedTokens = [
            DistributedNotificationCenter.default().addObserver(
                forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main
            ) { [weak self] _ in
                log.debug("screen unlocked")
                self?.resync()
            },
        ]
        // Safety net for missed AX events (or a reset Accessibility permission): recheck after
        // a mouse click. Fires on clicks only; monitoring the mouse needs no permission.
        // The monitor sees the event before the app handles it (e.g. closes a window via the
        // close button), so delayed rechecks are needed too.
        // A click while Finder is active after its last window closed: on the desktop now (or Finder's menu). The
        // press comes before the release that closes a window, so it can't clear the mark the close sets.
        mouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
            self?.finderWindowClosed = false
        }
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] _ in
            self?.scheduleUpdate()
            self?.refreshSoon()
        }
        frontAppChanged(NSWorkspace.shared.frontmostApplication?.processIdentifier)
    }

    func stop() {
        guard running else { return }
        running = false
        workspaceTokens.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        distributedTokens.forEach { DistributedNotificationCenter.default().removeObserver($0) }
        workspaceTokens = []
        distributedTokens = []
        if let m = mouseMonitor { NSEvent.removeMonitor(m) }
        if let m = mouseDownMonitor { NSEvent.removeMonitor(m) }
        mouseMonitor = nil
        mouseDownMonitor = nil
        finderWindowClosed = false
        detach()
        lastTarget = nil
        delivered = false
    }

    /// Retry attaching AX (e.g. after the permission is granted).
    func ensureAttached() {
        guard running, observer == nil, AXIsProcessTrusted(),
              let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier, pid != ownPID else { return }
        attach(pid: pid)
        refresh(force: false)
    }

    // MARK: - Events

    private func frontAppChanged(_ pid: pid_t?) {
        guard let pid, pid != ownPID else { return }
        finderWindowClosed = false
        log.debug("activated pid \(pid)")
        if pid != observedPID || observer == nil {
            attachRetries = 0
            attach(pid: pid)
        }
        refresh(force: false)
        refreshSoon()
    }

    /// Full resync: reattach AX to the current app and reorder the overlay.
    private func resync() {
        guard running else { return }
        if let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier, pid != ownPID {
            attachRetries = 0
            attach(pid: pid)
        }
        refresh(force: true)
        refreshSoon()
    }

    /// WindowServer raises an activated app's window with a delay (sometimes hundreds of ms for
    /// heavy apps), so recheck twice. This isn't polling: it runs only after an event.
    private func refreshSoon() {
        for delay in [0.12, 0.4] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.scheduleUpdate() }
        }
    }

    /// Coalesces a burst of events (e.g. a window drag) into one refresh per runloop pass.
    func scheduleUpdate() {
        guard running, !updatePending else { return }
        updatePending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.updatePending = false
            self.refresh(force: false)
        }
    }

    func refresh(force: Bool) {
        guard running else { return }
        if force { fullscreenSpaceScreens = Spaces.fullscreenScreens() }
        let front = NSWorkspace.shared.frontmostApplication
        // Our own app is in front (an alert, the shortcut recorder): keep things as they are. A pending
        // highlight under the pointer can't be applied now, so it's dropped rather than left hanging.
        if front?.processIdentifier == ownPID { peekWindowID = nil; return }
        // There may be no active app at all (an app quit and focus went nowhere),
        // or it is already terminating: that means "no active window".
        var target: FocusTarget?
        if let front, !front.isTerminated, !front.isHidden {
            target = buildTargets(pid: front.processIdentifier)
        }
        // The app was just launched and hasn't shown a window yet (heavy apps take seconds to open).
        // That isn't "no active window": keep the effect as is, without flicker. The window arrives via AX
        // (WindowCreated); if it never does, the normal rule applies once the launch grace period ends.
        if target == nil, let front, !front.isTerminated, !front.isHidden, isLaunching(front) {
            waitingForLaunchWindow = true
            peekWindowID = nil
            return
        }
        waitingForLaunchWindow = false
        // No active window (the last one was closed, or an app quit and focus went nowhere): the top window on
        // screen stays bright, with the same Keep Bright rule, so other windows still don't sit in the dimmed
        // background. Except on the desktop (Finder active without windows): the user is working with the
        // desktop's files then, so nothing is dimmed. Closing or minimizing Finder's last window leaves Finder
        // active too, but that isn't the desktop (finderWindowClosed).
        followingTopWindow = false
        if target == nil, !isDesktop(front) || finderWindowClosed {
            followingTopWindow = true
            if let pid = topWindowOwner() { target = buildTargets(pid: pid) }
        }
        // orderOK == false: the window is there but the overlay isn't right below it (the window rose after
        // we placed the overlay, or something got in between): reorder even if the target "didn't change".
        let misplaced = target?.all.contains { !$0.orderOK } == true
        if force || !delivered || target != lastTarget || misplaced {
            if target == nil {
                log.debug("no window to keep bright (\(front?.localizedName ?? "no frontmost app", privacy: .public))")
            } else if followingTopWindow, target != lastTarget {
                log.debug("no active window: keeping the top window on screen bright")
            } else if misplaced && target == lastTarget {
                log.debug("reorder: overlay not directly under window")
            }
            lastTarget = target
            delivered = true
            onTarget?(target)
        }
    }

    /// How long to wait for the first window of a just-launched app.
    private let launchGrace: TimeInterval = 8
    private var launchCheckPID: pid_t?

    private func isLaunching(_ app: NSRunningApplication) -> Bool {
        guard let launched = app.launchDate else { return false }
        let remaining = launchGrace - Date().timeIntervalSince(launched)
        guard remaining > 0 else { return false }
        // One check at the end of the grace period, for an app that never opens a window.
        if launchCheckPID != app.processIdentifier {
            launchCheckPID = app.processIdentifier
            DispatchQueue.main.asyncAfter(deadline: .now() + remaining + 0.05) { [weak self] in
                self?.launchCheckPID = nil
                self?.scheduleUpdate()
            }
        }
        return true
    }

    // MARK: - AX

    /// Moves and resizes are followed in both modes: the active window's frame tells Highlight Window Under Pointer
    /// where the active window is, and in All App Windows mode the holes follow the windows.
    private var windowNotifications: [String] {
        [kAXUIElementDestroyedNotification, kAXWindowMovedNotification, kAXWindowResizedNotification]
    }

    private func attach(pid: pid_t) {
        detach()
        observedPID = pid
        guard AXIsProcessTrusted() else {
            log.debug("accessibility not trusted — AX tracking disabled")
            return
        }
        var obs: AXObserver?
        guard AXObserverCreate(pid, axCallback, &obs) == .success, let obs else {
            retryAttach(pid)
            return
        }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.5)  // a hung app must not block us
        appElement = app
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let appNotifications = [
            kAXFocusedWindowChangedNotification,
            kAXMainWindowChangedNotification,
            kAXWindowCreatedNotification,
            kAXWindowMiniaturizedNotification,
            kAXWindowDeminiaturizedNotification,
            kAXApplicationHiddenNotification,
            kAXApplicationShownNotification,
            kAXWindowMovedNotification,
            kAXWindowResizedNotification,
        ]

        var failed = false
        for n in appNotifications {
            let err = AXObserverAddNotification(obs, app, n as CFString, refcon)
            if err == .cannotComplete || err == .notImplemented && n == kAXFocusedWindowChangedNotification {
                failed = true
            }
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .commonModes)
        observer = obs

        // Window close/move notifications arrive reliably only when subscribed on the window element itself.
        var windows: CFTypeRef?
        if AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windows) == .success,
           let list = windows as? [AXUIElement] {
            for w in list { observeWindow(w) }
        }

        // A just-launched app isn't ready to answer AX yet: try again later.
        if failed { retryAttach(pid) }
    }

    private func retryAttach(_ pid: pid_t) {
        // A launching app may start answering AX only after a few seconds.
        guard attachRetries < 32 else { return }
        attachRetries += 1
        log.debug("AX attach failed for pid \(pid), retry \(self.attachRetries)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self, self.running,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return }
            self.attach(pid: pid)
            self.scheduleUpdate()
        }
    }

    fileprivate func observeWindow(_ element: AXUIElement) {
        guard let obs = observer else { return }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for n in windowNotifications {
            AXObserverAddNotification(obs, element, n as CFString, refcon)
        }
        if let id = Self.windowID(of: element) { windowIDs[element] = id }
    }

    fileprivate func handle(notification: String, element: AXUIElement) {
        switch notification {
        case kAXWindowCreatedNotification:
            observeWindow(element)
            scheduleUpdate()
        case kAXUIElementDestroyedNotification, kAXWindowMiniaturizedNotification:
            if observedIsFinder { finderWindowClosed = true }
            let id = windowIDs[element] ?? Self.windowID(of: element)
            if notification == kAXUIElementDestroyedNotification { windowIDs[element] = nil }
            if let id { markLeaving(id) }
            scheduleUpdate()
            refreshSoon()
        case kAXApplicationHiddenNotification, kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification:
            // AX reports a window close or switch (Cmd+`) before WindowServer updates the window order:
            // the list is still stale right away, so recheck later too.
            scheduleUpdate()
            refreshSoon()
        default:
            scheduleUpdate()
        }
    }

    private func detach() {
        if let obs = observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .commonModes)
        }
        observer = nil
        observedPID = nil
        appElement = nil
        windowIDs.removeAll()
    }

    /// The app's active window is in system full screen mode (its own Space).
    /// Geometry can't tell: on displays with a notch a full screen window is the same size
    /// as a zoomed one. So ask the focused and main windows for the AXFullScreen attribute.
    private func isFrontWindowFullScreen(pid: pid_t) -> Bool {
        guard let app = appElement, observedPID == pid else { return false }
        for attr in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] {
            var win: CFTypeRef?
            guard AXUIElementCopyAttributeValue(app, attr as CFString, &win) == .success, let win else { continue }
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(win as! AXUIElement, "AXFullScreen" as CFString, &value) == .success,
               (value as? Bool) == true {
                return true
            }
        }
        return false
    }

    // MARK: - Window list

    /// CGWindowID of an AX window element (private but long-standing `_AXUIElementGetWindow`). It no longer
    /// answers once the element is destroyed, so the numbers are kept from when the windows are first observed.
    private typealias GetWindow = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError
    private static let getWindow: GetWindow? = dlsym(dlopen(nil, RTLD_NOW), "_AXUIElementGetWindow")
        .map { unsafeBitCast($0, to: GetWindow.self) }

    private static func windowID(of element: AXUIElement) -> CGWindowID? {
        var id: CGWindowID = 0
        guard let getWindow, getWindow(element, &id) == .success, id != 0 else { return nil }
        return id
    }

    private func markLeaving(_ id: CGWindowID) {
        leavingWindows.insert(id)
        // By then it's gone from the window list (or, if it was only hidden, may come back).
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.leavingWindows.remove(id) }
    }

    private var observedIsFinder: Bool {
        guard let pid = observedPID else { return false }
        return NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == "com.apple.finder"
    }

    /// Finder is active without windows of its own: the user clicked the desktop (unless `finderWindowClosed`: its
    /// last window was just closed or minimized).
    private func isDesktop(_ front: NSRunningApplication?) -> Bool {
        guard let front, !front.isTerminated, !front.isHidden else { return false }
        return front.bundleIdentifier == "com.apple.finder"
    }

    /// Owner of the top normal window on screen.
    private func topWindowOwner() -> pid_t? {
        normalWindows(screens: NSScreen.screens.map(\.frame))?.first { $0.owner != ownPID && $0.rect != nil }?.owner
    }

    /// A normal window (layer 0) from the window list.
    private struct ListedWindow {
        let id: CGWindowID
        let owner: pid_t
        /// Global Cocoa frame. For other apps' windows only when actually visible and not leaving (otherwise nil:
        /// they don't count); for our own windows (the overlays) always.
        let rect: CGRect?
    }

    /// The normal windows on screen, front to back.
    private func normalWindows(screens: [CGRect]) -> [ListedWindow]? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return nil }
        let primaryHeight = screens.first?.height ?? 0
        return list.compactMap { w in
            guard (w[kCGWindowLayer as String] as? Int) == 0, let owner = w[kCGWindowOwnerPID as String] as? pid_t
            else { return nil }
            let id = w[kCGWindowNumber as String] as? CGWindowID ?? 0
            let rect: CGRect?
            if owner == ownPID {
                rect = (w[kCGWindowBounds as String] as? NSDictionary)
                    .flatMap { CGRect(dictionaryRepresentation: $0 as CFDictionary) }
                    .map { CGRect(x: $0.minX, y: primaryHeight - $0.maxY, width: $0.width, height: $0.height) }
            } else {
                rect = leavingWindows.contains(id) ? nil : Self.visibleRect(w, screens: screens, primaryHeight: primaryHeight)
            }
            return ListedWindow(id: id, owner: owner, rect: rect)
        }
    }

    /// The display holding most of a rect.
    private static func screen(holding rect: CGRect, in screens: [CGRect]) -> CGRect? {
        screens.max { area($0.intersection(rect)) < area($1.intersection(rect)) }
    }

    private static func area(_ r: CGRect) -> CGFloat { r.isNull ? 0 : r.width * r.height }

    /// A window's frame in global Cocoa coordinates if it's actually visible: not transparent, not tiny, on a
    /// screen. Filters out invisible helper windows (Electron, Telegram, Zoom…).
    private static func visibleRect(_ w: [String: Any], screens: [CGRect], primaryHeight: CGFloat) -> CGRect? {
        guard (w[kCGWindowAlpha as String] as? Double ?? 1) > 0.01,
              let bd = w[kCGWindowBounds as String] as? NSDictionary,
              let r = CGRect(dictionaryRepresentation: bd as CFDictionary),
              r.width > 8, r.height > 8
        else { return nil }
        // Global Quartz coordinates (top-left) → Cocoa (bottom-left).
        let rect = CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
        return screens.contains(where: { $0.intersects(rect) }) ? rect : nil
    }

    /// The target for the app's top window and, with several displays, the targets of the other displays.
    private func buildTargets(pid: pid_t) -> FocusTarget? {
        let screens = NSScreen.screens.map(\.frame)
        guard let windows = normalWindows(screens: screens),
              let top = windows.first(where: { $0.owner == pid && $0.owner != ownPID && $0.rect != nil }) else { return nil }
        // With one display, everything is on it.
        let active = screens.count > 1 ? Self.screen(holding: top.rect!, in: screens) : nil
        guard var target = buildTarget(pid: pid, windows: windows, screens: screens, within: active) else { return nil }
        if let active, dimOtherScreens {
            // Each other display keeps its own top window bright: the top window mostly on it, whoever owns it.
            for s in screens where s != active {
                guard let w = windows.first(where: { w in
                          w.owner != ownPID && w.rect.map { Self.screen(holding: $0, in: screens) == s } == true
                      }),
                      let t = buildTarget(pid: w.owner, windows: windows, screens: screens, within: s, top: w.id)
                else { continue }
                target.others.append(t)
            }
        }
        if peekWindowID != nil, !target.all.contains(where: { $0.peekID != nil }) {
            peekWindowID = nil  // gone, or not dimmed any more
        }
        return target
    }

    /// What stays bright around the app's top window. With several displays it's built for one display (`within`)
    /// from the windows on it, and its overlay is the one on that display; `top` picks the top window there (by
    /// default the app's first window on it).
    private func buildTarget(pid: pid_t, windows all: [ListedWindow], screens allScreens: [CGRect],
                             within: CGRect?, top forcedTop: CGWindowID? = nil) -> FocusTarget? {
        let windows = within.map { s in all.filter { w in w.rect.map { Self.area($0.intersection(s)) > 0 } ?? false } } ?? all
        let screens = within.map { [$0] } ?? allScreens

        // Windows above our overlay (everything before it in the front-to-back list).
        var above: CGMutablePath? = CGMutablePath()
        for w in windows {
            if w.owner == ownPID { break }
            guard let rect = w.rect else { continue }
            above?.addPath(CGPath(roundedRect: rect, cornerWidth: holeCornerRadius, cornerHeight: holeCornerRadius, transform: nil))
        }
        if !windows.contains(where: { $0.owner == ownPID }) {
            above = nil  // the overlay isn't on screen
        }

        var topID: CGWindowID?
        var topRect = CGRect.null
        var orderOK = false
        var checkedOrder = false
        var overlayAbove = false
        // Other apps' windows below the top window, front to back. One that lies over a window of the app further
        // down (between the app's windows) is shown bright as a whole: dimmed, it would sit like a dark patch
        // on the app's bright windows.
        var others: [(rect: CGRect, between: Bool)] = []
        var appWindows: [CGRect] = []
        // Highlight Window Under Pointer: the window, every window on top of it, and where the overlay is. A window
        // that's part of a layout (Keep Tiled Windows Bright) is highlighted with the whole layout: the overlay goes
        // below the lowest of its windows. Otherwise which neighbours brighten would depend on their order.
        var peekGroup: Set<CGWindowID> = []
        if let peek = peekWindowID, let r = windows.first(where: { $0.id == peek })?.rect {
            peekGroup = [peek]
            if keepTiledBright {
                for t in tiledWindows(top: peek, rect: r, windows: windows, screens: screens, coverCounts: false) {
                    peekGroup.insert(t.id)
                }
            }
        }
        var allAbove: [CGRect] = []
        var overlaySeen = false
        var peekFound = false              // the highlighted window itself
        var peekLowest: CGWindowID?        // the lowest window of its group found so far: the overlay goes below it
        var peekParts: [(rect: CGRect, occluders: [CGRect])] = []
        var revealed: [CGRect] = []        // the group and everything above it: bright while it's highlighted
        var peekCovered = false            // the overlay is still above the lowest one
        var peekOrderOK = false            // the overlay already sits right below the lowest one
        var peekOrderChecked = false
        // Only the target whose top window it was highlighted over looks for it.
        var peekPending: Bool { !peekGroup.isEmpty && topID != nil && topID == peekForTopID }
        // Windows above the top window (on another display: windows mostly elsewhere that reach onto this one).
        var aboveTop: [CGRect] = []

        for w in windows {
            let owner = w.owner

            if owner == ownPID {
                // The first normal window right below the top window must be our overlay.
                if topID != nil, !checkedOrder { orderOK = true; checkedOrder = true }
                if topID == nil { overlayAbove = true }
                if peekLowest != nil, !peekOrderChecked { peekOrderOK = true; peekOrderChecked = true }
                overlaySeen = true
                continue
            }

            guard let rect = w.rect else { continue }
            if peekLowest != nil { peekOrderChecked = true }  // another window between it and the overlay

            // Only a dimmed window can be highlighted: below the app's top window, and not one of the app's
            // windows that All App Windows keeps bright anyway.
            if peekPending, peekGroup.contains(w.id), !(mode == .app && owner == pid) {
                peekGroup.remove(w.id)
                if w.id == peekWindowID { peekFound = true }
                peekParts.append((rect, allAbove.filter { $0.intersects(rect) }))
                revealed = allAbove + [rect]
                peekCovered = overlaySeen
                peekLowest = w.id
                peekOrderOK = false
                peekOrderChecked = false
            }
            allAbove.append(rect)

            guard topID != nil else {
                // Everything above the app's top window is above the overlay anyway.
                if owner == pid, forcedTop == nil || w.id == forcedTop {
                    topID = w.id
                    topRect = rect
                    aboveTop = allAbove.dropLast()
                }
                continue
            }

            if !checkedOrder { checkedOrder = true }  // another app's window between the window and the overlay → orderOK = false
            if mode == .window {
                if peekPending { continue } else { break }
            }

            if owner == pid {
                appWindows.append(rect)
                for i in others.indices where others[i].rect.intersects(rect) { others[i].between = true }
                if appWindows.count >= 32, !peekPending { break }
            } else {
                others.append((rect, false))
            }
        }

        guard let topID else { return nil }
        // Screens without the effect: a full screen Space (system full screen: video, players, apps)
        // or a borderless window covering the whole screen (games, players' legacy full screen).
        var fullscreen = fullscreenSpaceScreens
        for s in screens where topRect.insetBy(dx: -1, dy: -1).contains(s) && !fullscreen.contains(s) {
            fullscreen.append(s)
        }
        // Fallback when the Space type is unavailable (the active app's window only: it asks AX).
        if fullscreen.isEmpty, !Spaces.available, forcedTop == nil, isFrontWindowFullScreen(pid: pid) {
            let center = CGPoint(x: topRect.midX, y: topRect.midY)
            fullscreen = screens.filter { $0.contains(center) }
        }
        let activeScreen = Self.screen(holding: topRect, in: screens)
        let radius = holeCornerRadius
        let topPath = CGPath(roundedRect: topRect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        func visiblePart(_ rect: CGRect, minus occluders: [CGRect]) -> CGPath {
            let p = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
            guard !occluders.isEmpty else { return p }
            let occ = CGMutablePath()
            occ.addRects(occluders)
            return p.subtracting(occ)
        }

        // The top window's frame is part of the comparison, so a moved or resized active window updates the target
        // (the overlay doesn't need it, but the active region does).
        var signature: [CGRect] = [topRect, .null]
        var holes: CGPath?
        if mode == .app, !appWindows.isEmpty {
            // The app's windows are bright whole: every other window over them is between them, so bright too.
            for rect in appWindows {
                signature.append(rect)
                let p = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
                holes = holes.map { $0.union(p) } ?? p
            }
            signature.append(.null)  // separator
            // Windows between the app's windows, minus the dimmed windows on top of them.
            for (i, other) in others.enumerated() where other.between {
                let occ = others[..<i].filter { !$0.between && $0.rect.intersects(other.rect) }.map(\.rect)
                signature.append(other.rect)
                signature.append(contentsOf: occ)
                signature.append(.null)
                let p = visiblePart(other.rect, minus: occ)
                holes = holes.map { $0.union(p) } ?? p
            }
        }
        let tiled = keepTiledBright ? tiledWindows(top: topID, rect: topRect, windows: windows, screens: screens) : []
        for (_, rect) in tiled {
            signature.append(rect)
            let p = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
            holes = holes.map { $0.union(p) } ?? p
        }
        signature.append(.null)
        let active: CGPath = holes.map { topPath.union($0) } ?? topPath
        var bright = active
        if forcedTop != nil, !aboveTop.isEmpty {
            // On another display, windows reaching onto it from the active one (above its top window) are above
            // the overlay too.
            signature.append(contentsOf: aboveTop)
            signature.append(.null)
            for rect in aboveTop {
                bright = bright.union(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
            }
        }
        var peekRegion: CGPath?
        var peekID: CGWindowID?
        if peekFound, let id = peekWindowID {
            // The effect moves below the window (its layout): it and every window above it are bright.
            signature.append(contentsOf: revealed)
            signature.append(.null)
            for part in peekParts {
                let p = visiblePart(part.rect, minus: part.occluders)
                peekRegion = peekRegion.map { $0.union(p) } ?? p
            }
            peekID = id
            for rect in revealed {
                bright = bright.union(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
            }
        }
        return FocusTarget(topID: topID, orderBelowID: peekID != nil ? peekLowest ?? topID : topID, holes: holes, tiledIDs: tiled.map(\.id),
                           fullscreenScreens: fullscreen,
                           activeScreen: activeScreen,
                           orderOK: (peekID != nil ? peekOrderOK : orderOK) || fullscreen.contains(where: screens.contains),
                           coveredByOverlay: peekID != nil ? peekCovered : overlayAbove, brightRegion: bright, activeRegion: active,
                           aboveOverlay: above, peekID: peekID, peekRegion: peekRegion, signature: signature)
    }

    // MARK: - Tiled windows

    /// How far tiled windows may be from each other and from the edges of the screen's usable area (macOS can leave
    /// margins around tiled windows).
    private static let tileGap: CGFloat = 20
    /// How much of the edge two neighbours have to share.
    private static let tileMinShared: CGFloat = 80
    /// Overlaps and overhangs this small (window borders) don't count.
    private static let tileSlack: CGFloat = 8

    /// The windows laid out side by side with the top window: snapped to halves, thirds or quarters of the screen,
    /// by macOS or a window manager. macOS doesn't tell, so it's judged by alignment, which windows placed by hand
    /// almost never have:
    /// - the windows don't overlap and none of them is covered by another window;
    /// - each lies within the screen's usable area (without the menu bar and the Dock) and is snapped to its edges:
    ///   in a corner, or across its whole height or width;
    /// - each touches another one of them along an edge, so they form one group with the top window.
    /// The layout doesn't have to fill the screen: three quarters with the fourth left empty count too. Windows that
    /// just happen to stand next to each other don't. The work is a few rectangle comparisons per window on the
    /// display, done only when the target is rebuilt anyway.
    ///
    /// `coverCounts` false: windows in front of the layout don't break it (for a layout that's dimmed and about to be
    /// highlighted: the overlay goes below it, so whatever covers it is bright anyway).
    private func tiledWindows(top: CGWindowID, rect topRect: CGRect, windows: [ListedWindow], screens: [CGRect],
                              coverCounts: Bool = true) -> [(id: CGWindowID, rect: CGRect)] {
        guard let display = Self.screen(holding: topRect, in: screens),
              let usable = NSScreen.screens.first(where: { $0.frame == display })?.visibleFrame else { return [] }
        let bounds = usable.insetBy(dx: -Self.tileSlack, dy: -Self.tileSlack)
        guard bounds.contains(topRect), Self.snapped(topRect, to: usable) else { return [] }
        // Windows on the display, front to back, that could be part of a layout: not overlapping a window in front
        // of them (with coverCounts false, only the candidates count, so windows hidden behind them still drop out).
        var inFront: [CGRect] = []
        var candidates: [(id: CGWindowID, rect: CGRect)] = []
        for w in windows where w.owner != ownPID {
            guard let r = w.rect, Self.screen(holding: r, in: screens) == display else { continue }
            let fits = w.id != top && bounds.contains(r) && Self.snapped(r, to: usable) && !Self.overlaps(r, topRect)
                && !inFront.contains(where: { Self.overlaps($0, r) })
            if fits { candidates.append((w.id, r)) }
            if fits || coverCounts { inFront.append(r) }
        }
        guard !candidates.isEmpty else { return [] }
        // The group around the top window: neighbours, their neighbours and so on.
        var group: [(id: CGWindowID, rect: CGRect)] = [(top, topRect)]
        while let i = candidates.firstIndex(where: { c in group.contains { Self.adjacent($0.rect, c.rect) } }) {
            group.append(candidates.remove(at: i))
        }
        return Array(group.dropFirst())
    }

    /// Snapped to the edges of the usable area the way tiling places windows: in a corner (two adjacent edges) or
    /// across it (two opposite edges).
    private static func snapped(_ r: CGRect, to usable: CGRect) -> Bool {
        let left = abs(r.minX - usable.minX) <= tileGap, right = abs(r.maxX - usable.maxX) <= tileGap
        let bottom = abs(r.minY - usable.minY) <= tileGap, top = abs(r.maxY - usable.maxY) <= tileGap
        return (left || right) && (top || bottom) || (left && right) || (top && bottom)
    }

    private static func overlaps(_ a: CGRect, _ b: CGRect) -> Bool {
        let i = a.intersection(b)
        return !i.isNull && i.width > tileSlack && i.height > tileSlack
    }

    /// Side by side or one above the other, sharing a good part of an edge.
    private static func adjacent(_ a: CGRect, _ b: CGRect) -> Bool {
        let sharedX = min(a.maxX, b.maxX) - max(a.minX, b.minX)
        let sharedY = min(a.maxY, b.maxY) - max(a.minY, b.minY)
        let sideBySide = (abs(a.maxX - b.minX) <= tileGap || abs(b.maxX - a.minX) <= tileGap) && sharedY >= tileMinShared
        let stacked = (abs(a.maxY - b.minY) <= tileGap || abs(b.maxY - a.minY) <= tileGap) && sharedX >= tileMinShared
        return sideBySide || stacked
    }
}

private let axCallback: AXObserverCallback = { _, element, notification, refcon in
    guard let refcon else { return }
    Unmanaged<FocusTracker>.fromOpaque(refcon).takeUnretainedValue()
        .handle(notification: notification as String, element: element)
}

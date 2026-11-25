import AppKit
import ApplicationServices
import os

let log = Logger(subsystem: "io.github.roman1kuz.moodydimmer", category: "focus")

/// What has to stay bright.
struct FocusTarget: Equatable {
    /// Top window of the active app: the overlay is placed right below it.
    let topID: CGWindowID
    /// Extra holes (the app's other windows minus overlaps), global Cocoa coordinates.
    let holes: CGPath?
    /// Screens fully covered by the active window (full screen video, app in full screen).
    /// No effect there: nothing to dim, and in a full screen Space the overlay would end up above the window.
    let fullscreenScreens: [CGRect]
    /// The overlay already sits right below topID. If not, reorder even if everything else matches.
    let orderOK: Bool
    /// The top window is under our overlay (the active window went away and the one left below it takes over),
    /// so it has to be uncovered smoothly rather than just rise above the overlay.
    let coveredByOverlay: Bool
    /// What stays bright: the top window plus the holes, global Cocoa coordinates.
    let brightRegion: CGPath
    /// Windows currently above our overlay, so bright whatever we thought (e.g. a just-launched app's window that
    /// appeared before we knew about it). nil when the overlay isn't on screen. Global Cocoa coordinates.
    let aboveOverlay: CGPath?
    /// Raw inputs for a cheap comparison.
    fileprivate let signature: [CGRect]

    static func == (a: FocusTarget, b: FocusTarget) -> Bool {
        a.topID == b.topID && a.signature == b.signature && a.fullscreenScreens == b.fullscreenScreens
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

    /// Corner radius of the holes (≈ macOS window corner radius).
    var holeCornerRadius: CGFloat = 14

    private(set) var lastTarget: FocusTarget?
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
        mouseMonitor = nil
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
        if front?.processIdentifier == ownPID { return }
        // There may be no active app at all (an app quit and focus went nowhere),
        // or it is already terminating: that means "no active window".
        var target: FocusTarget?
        if let front, !front.isTerminated, !front.isHidden {
            target = buildTarget(pid: front.processIdentifier)
        }
        // The app was just launched and hasn't shown a window yet (heavy apps take seconds to open).
        // That isn't "no active window": keep the effect as is, without flicker. The window arrives via AX
        // (WindowCreated); if it never does, the normal rule applies once the launch grace period ends.
        if target == nil, let front, !front.isTerminated, !front.isHidden, isLaunching(front) {
            waitingForLaunchWindow = true
            return
        }
        waitingForLaunchWindow = false
        // No active window (the last one was closed, or an app quit and focus went nowhere): the top window on
        // screen stays bright, with the same Keep Bright rule, so other windows still don't sit in the dimmed
        // background. Except on the desktop (Finder active without windows): the user is working with the
        // desktop's files then, so nothing is dimmed.
        followingTopWindow = false
        if target == nil, !isDesktop(front) {
            followingTopWindow = true
            if let pid = topWindowOwner() { target = buildTarget(pid: pid) }
        }
        // orderOK == false: the window is there but the overlay isn't right below it (the window rose after
        // we placed the overlay, or something got in between): reorder even if the target "didn't change".
        if force || !delivered || target != lastTarget || target?.orderOK == false {
            if target == nil {
                log.debug("no window to keep bright (\(front?.localizedName ?? "no frontmost app", privacy: .public))")
            } else if followingTopWindow, target != lastTarget {
                log.debug("no active window: keeping the top window on screen bright")
            } else if target?.orderOK == false && target == lastTarget {
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

    private var windowNotifications: [String] {
        mode == .app
            ? [kAXUIElementDestroyedNotification, kAXWindowMovedNotification, kAXWindowResizedNotification]
            : [kAXUIElementDestroyedNotification]
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
        ] + (mode == .app ? [kAXWindowMovedNotification, kAXWindowResizedNotification] : [])

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

    /// Finder is active without windows of its own: the user clicked the desktop (or closed Finder's last window).
    private func isDesktop(_ front: NSRunningApplication?) -> Bool {
        guard let front, !front.isTerminated, !front.isHidden else { return false }
        return front.bundleIdentifier == "com.apple.finder"
    }

    /// Owner of the top normal window on screen (the window list is ordered front to back).
    private func topWindowOwner() -> pid_t? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return nil }
        let screens = NSScreen.screens.map(\.frame)
        let primaryHeight = screens.first?.height ?? 0
        for w in list {
            guard (w[kCGWindowLayer as String] as? Int) == 0,
                  let owner = w[kCGWindowOwnerPID as String] as? pid_t, owner != ownPID,
                  !leavingWindows.contains(w[kCGWindowNumber as String] as? CGWindowID ?? 0),
                  Self.visibleRect(w, screens: screens, primaryHeight: primaryHeight) != nil else { continue }
            return owner
        }
        return nil
    }

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

    private func buildTarget(pid: pid_t) -> FocusTarget? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return nil }
        let screens = NSScreen.screens.map(\.frame)
        let primaryHeight = screens.first?.height ?? 0

        // Windows above our overlay (everything before it in the front-to-back list).
        var above: CGMutablePath? = CGMutablePath()
        for w in list {
            guard (w[kCGWindowLayer as String] as? Int) == 0, let owner = w[kCGWindowOwnerPID as String] as? pid_t else { continue }
            if owner == ownPID { break }
            guard !leavingWindows.contains(w[kCGWindowNumber as String] as? CGWindowID ?? 0),
                  let rect = Self.visibleRect(w, screens: screens, primaryHeight: primaryHeight) else { continue }
            above?.addPath(CGPath(roundedRect: rect, cornerWidth: holeCornerRadius, cornerHeight: holeCornerRadius, transform: nil))
        }
        if !list.contains(where: { ($0[kCGWindowOwnerPID as String] as? pid_t) == ownPID && ($0[kCGWindowLayer as String] as? Int) == 0 }) {
            above = nil  // the overlay isn't on screen
        }

        var topID: CGWindowID?
        var topRect = CGRect.null
        var orderOK = false
        var checkedOrder = false
        var overlayAbove = false
        var occluders: [CGRect] = []
        var appWindows: [(rect: CGRect, occluders: [CGRect])] = []

        for w in list {
            guard (w[kCGWindowLayer as String] as? Int) == 0,
                  let owner = w[kCGWindowOwnerPID as String] as? pid_t else { continue }

            if owner == ownPID {
                // The first normal window right below the top window must be our overlay.
                if topID != nil, !checkedOrder { orderOK = true; checkedOrder = true }
                if topID == nil { overlayAbove = true }
                continue
            }

            guard !leavingWindows.contains(w[kCGWindowNumber as String] as? CGWindowID ?? 0),
                  let rect = Self.visibleRect(w, screens: screens, primaryHeight: primaryHeight) else { continue }

            guard topID != nil else {
                // Everything above the app's top window is above the overlay anyway.
                if owner == pid, let id = w[kCGWindowNumber as String] as? CGWindowID {
                    topID = id
                    topRect = rect
                }
                continue
            }

            if !checkedOrder { checkedOrder = true }  // another app's window between the window and the overlay → orderOK = false
            if mode == .window { break }

            if owner == pid {
                appWindows.append((rect, occluders.filter { $0.intersects(rect) }))
                if appWindows.count >= 32 { break }
            } else {
                occluders.append(rect)
            }
        }

        guard let topID else { return nil }
        // Screens without the effect: a full screen Space (system full screen: video, players, apps)
        // or a borderless window covering the whole screen (games, players' legacy full screen).
        var fullscreen = fullscreenSpaceScreens
        for s in screens where topRect.insetBy(dx: -1, dy: -1).contains(s) && !fullscreen.contains(s) {
            fullscreen.append(s)
        }
        // Fallback when the Space type is unavailable.
        if fullscreen.isEmpty, !Spaces.available, isFrontWindowFullScreen(pid: pid) {
            let center = CGPoint(x: topRect.midX, y: topRect.midY)
            fullscreen = screens.filter { $0.contains(center) }
        }
        let radius = holeCornerRadius
        let topPath = CGPath(roundedRect: topRect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        guard mode == .app, !appWindows.isEmpty else {
            return FocusTarget(topID: topID, holes: nil, fullscreenScreens: fullscreen, orderOK: orderOK || !fullscreen.isEmpty,
                               coveredByOverlay: overlayAbove, brightRegion: topPath, aboveOverlay: above, signature: [])
        }

        var signature: [CGRect] = []
        var holes: CGPath?
        for (rect, occ) in appWindows {
            signature.append(rect)
            signature.append(contentsOf: occ)
            signature.append(.null)  // separator
            var p: CGPath = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
            if !occ.isEmpty {
                let occPath = CGMutablePath()
                occPath.addRects(occ)
                p = p.subtracting(occPath)
            }
            holes = holes.map { $0.union(p) } ?? p
        }
        return FocusTarget(topID: topID, holes: holes, fullscreenScreens: fullscreen, orderOK: orderOK || !fullscreen.isEmpty,
                           coveredByOverlay: overlayAbove, brightRegion: holes.map { topPath.union($0) } ?? topPath,
                           aboveOverlay: above,
                           signature: signature)
    }
}

private let axCallback: AXObserverCallback = { _, element, notification, refcon in
    guard let refcon else { return }
    Unmanaged<FocusTracker>.fromOpaque(refcon).takeUnretainedValue()
        .handle(notification: notification as String, element: element)
}

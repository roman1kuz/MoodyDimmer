import AppKit

/// One overlay per screen and what it currently keeps bright.
private final class ScreenOverlay {
    let screenFrame: CGRect
    let window: OverlayWindow
    /// The window the overlay sits right below (nil while hidden).
    var topID: CGWindowID?
    /// What's bright now (top window + holes) and the holes alone, global Cocoa coordinates.
    var bright: CGPath?
    var holes: CGPath?
    /// A focus change is animating; the final reorder and mask come when it ends.
    var transitioning = false

    init(screen: NSScreen, coverMenuBar: Bool) {
        screenFrame = screen.frame
        window = OverlayWindow(screen: screen, coverMenuBar: coverMenuBar)
    }
}

final class OverlayController {
    private let settings: Settings
    private var screens: [ScreenOverlay] = []
    private var target: FocusTarget?
    private var effects: EffectParams
    /// Why the effect is temporarily removed. The target keeps updating meanwhile.
    enum SuspendReason { case dragging, systemMode }
    private var suspendReasons: Set<SuspendReason> = []
    private var suspended: Bool { !suspendReasons.isEmpty }
    /// The target is out of date (its window is gone): ask the tracker for a fresh one.
    var onStale: (() -> Void)?
    private var staleRecheckPending = false

    init(settings: Settings) {
        self.settings = settings
        effects = EffectParams.from(settings)
        rebuildScreens()
    }

    // MARK: - Public

    func rebuildScreens() {
        // close(), not orderOut: otherwise old windows stay in NSApp.windows and are never released.
        screens.forEach { $0.window.close() }
        let cover = settings.dimMenuBar
        screens = NSScreen.screens.map { ScreenOverlay(screen: $0, coverMenuBar: cover) }
        for s in screens { s.window.effectView.apply(effects, duration: 0) }
        if let target { show(target, duration: 0) }
    }

    /// New target from the tracker.
    func update(target newTarget: FocusTarget?) {
        target = newTarget
        let d = settings.animationDuration
        guard settings.enabled, !suspended else { hideAll(duration: d); return }
        if let t = newTarget {
            show(t, duration: d)
        } else {
            hideAll(duration: d)  // no windows on screen, or the desktop is active
        }
    }

    /// Effect strength or kind changed.
    func applyEffects(animated: Bool) {
        let p = EffectParams.from(settings)
        effects = p
        let d = animated ? settings.animationDuration : 0
        for s in screens { s.window.effectView.apply(p, duration: d) }
    }

    func setSuspended(_ on: Bool, reason: SuspendReason) {
        let was = suspended
        if on { suspendReasons.insert(reason) } else { suspendReasons.remove(reason) }
        guard suspended != was else { return }
        update(target: target)
    }

    func setEnabled(_ on: Bool) {
        if on, !suspended, let target { show(target, duration: settings.animationDuration) }
        else { hideAll(duration: settings.animationDuration) }
    }

    // MARK: - Ordering

    private func show(_ t: FocusTarget, duration d: TimeInterval) {
        for s in screens {
            let w = s.window
            // The active window covers the whole screen (full screen video or app): no effect needed.
            if t.fullscreenScreens.contains(s.screenFrame) {
                hide(s, duration: 0)
                continue
            }
            if !w.wantVisible || s.topID == nil {
                // Appearing: the whole overlay fades in.
                place(s, target: t)
                fade(w, to: 1, duration: d)
            } else if d > 0, s.topID != t.topID || hasOtherWindowsAbove(t) {
                // Another window, or the same one with other windows above the overlay that we didn't know were
                // bright (e.g. a just-launched app's window): they dim smoothly instead of at once.
                switchWindows(s, to: t, duration: d)
            } else if s.transitioning, s.topID == t.topID {
                // A recheck while the change to this window is still animating: it ends in the same place.
                continue
            } else {
                // Same top window (holes changed) or instant mode.
                place(s, target: t)
                if w.alphaValue < 1 { fade(w, to: 1, duration: d) }
            }
            s.topID = t.topID
            s.bright = t.brightRegion
            s.holes = t.holes
        }
    }

    /// Puts the overlay right below the top window with the final mask, at once.
    private func place(_ s: ScreenOverlay, target t: FocusTarget) {
        let w = s.window
        s.transitioning = false
        w.effectView.setMask(maskPath(holes: t.holes, screenFrame: s.screenFrame))
        w.wantVisible = true
        orderBelow(w, t.topID)
        w.effectView.windowDidOrderIn()
    }

    /// Focus moved to another window. The overlay stays put and only the mask changes, smoothly, in the areas of
    /// the windows that brighten or dim. The background never changes: no second overlay crossfading over the
    /// whole screen (which dims the background twice halfway through and visibly weakens the blur).
    private func switchWindows(_ s: ScreenOverlay, to t: FocusTarget, duration d: TimeInterval) {
        let w = s.window, f = s.screenFrame
        let full = CGPath(rect: f, transform: nil)
        let none = CGMutablePath()
        let oldHoles = s.holes ?? none
        // What's bright right now: the holes plus whatever lies above the overlay. That's more than what we last
        // set when a window appeared above the overlay before we heard of it.
        let oldBright = t.aboveOverlay.map { oldHoles.union($0) } ?? s.bright ?? none
        let newHoles = t.holes ?? none
        let fixed: CGPath, fadeIn: CGPath, fadeOut: CGPath
        let before: () -> Void, after: () -> Void
        let final = maskPath(holes: t.holes, screenFrame: f)

        if !t.coveredByOverlay {
            // The new window rose above the overlay (a click, ⌘Tab) and is bright at once. The overlay moves
            // below it; the old windows dim and the new app's other windows brighten.
            fadeIn = oldBright.subtracting(t.brightRegion)
            fadeOut = newHoles.subtracting(oldBright)
            fixed = full.subtracting(oldBright).subtracting(newHoles)
            before = { [weak self] in self?.orderBelow(w, t.topID) }
            after = { w.effectView.setMask(final) }
        } else {
            // The active window went away and a window under the overlay takes over: it brightens in place,
            // and the overlay moves below it once it's fully uncovered.
            fadeOut = t.brightRegion.subtracting(oldHoles)
            fadeIn = oldHoles.subtracting(t.brightRegion)
            fixed = full.subtracting(t.brightRegion).subtracting(oldHoles)
            before = {}
            after = { [weak self] in
                self?.orderBelow(w, t.topID)
                w.effectView.setMask(final)
            }
        }

        s.transitioning = true
        w.effectView.transitionMask(
            fixed: localPath(fixed, screenFrame: f),
            fadeIn: localPath(fadeIn, screenFrame: f),
            fadeOut: localPath(fadeOut, screenFrame: f),
            duration: d, before: before
        ) { [weak s] in
            guard let s, s.transitioning, s.window.wantVisible else { return }
            s.transitioning = false
            after()
        }
    }

    /// Puts the overlay right below a window, if that window is still on screen. Ordering below a window that's
    /// gone puts the overlay below every window, which shows as the effect vanishing (apps often replace a
    /// launch window right away). Then the overlay stays put and the tracker rechecks.
    private func orderBelow(_ w: OverlayWindow, _ id: CGWindowID) {
        let info = (CGWindowListCopyWindowInfo(.optionIncludingWindow, id) as? [[String: Any]])?.first
        guard (info?[kCGWindowIsOnscreen as String] as? Bool) == true else {
            log.debug("window \(id) is gone: overlay left in place")
            // A recheck shortly (not at once: a window list that hasn't caught up mustn't make a tight loop).
            if !staleRecheckPending {
                staleRecheckPending = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    self?.staleRecheckPending = false
                    self?.onStale?()
                }
            }
            return
        }
        w.order(.below, relativeTo: Int(id))
    }

    /// Windows other than the target's bright ones lie above the overlay.
    private func hasOtherWindowsAbove(_ t: FocusTarget) -> Bool {
        guard let above = t.aboveOverlay else { return false }
        let extra = above.subtracting(t.brightRegion).boundingBoxOfPath
        return !extra.isNull && extra.width > 1 && extra.height > 1
    }

    private func hideAll(duration d: TimeInterval) {
        for s in screens { hide(s, duration: d) }
    }

    private func hide(_ s: ScreenOverlay, duration d: TimeInterval) {
        let w = s.window
        s.topID = nil
        s.transitioning = false
        w.wantVisible = false
        guard w.isVisible else { return }
        fade(w, to: 0, duration: d) { [weak w] in
            guard let w, !w.wantVisible else { return }
            w.orderOut(nil)
        }
    }

    private func fade(_ w: OverlayWindow, to alpha: CGFloat, duration d: TimeInterval, completion: (() -> Void)? = nil) {
        if d > 0 {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = d
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                w.animator().alphaValue = alpha
            }, completionHandler: completion)
        } else {
            w.alphaValue = alpha
            completion?()
        }
    }

    /// A global path in an overlay's window-local coordinates.
    private func localPath(_ path: CGPath, screenFrame f: CGRect) -> CGPath {
        var toLocal = CGAffineTransform(translationX: -f.minX, y: -f.minY)
        return path.copy(using: &toLocal) ?? path
    }

    /// Where the effect is visible: the whole screen minus holes, in window-local coordinates.
    private func maskPath(holes: CGPath?, screenFrame f: CGRect) -> CGPath? {
        guard let holes, holes.boundingBoxOfPath.intersects(f) else { return nil }
        let full = CGPath(rect: f, transform: nil)
        var toLocal = CGAffineTransform(translationX: -f.minX, y: -f.minY)
        let visible = full.subtracting(holes)
        return visible.copy(using: &toLocal)
    }
}

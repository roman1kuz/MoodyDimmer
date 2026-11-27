import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = Settings.shared
    private let tracker = FocusTracker()
    private let drags = DragWatcher()
    private let hotKey = HotKey()
    private let shake = ShakeDetector()
    private let pointer = PointerMonitor()
    private lazy var peek = PeekWatcher(tracker: tracker)
    private let recorder = ShortcutRecorder()
    private let systemMode = SystemModeWatcher(.spaces)
    private let screenshotUI = SystemModeWatcher(.screenshot)
    private var overlays: OverlayController!
    private var menu: StatusMenu!

    func applicationDidFinishLaunching(_ notification: Notification) {
        Localization.use(settings.language)
        overlays = OverlayController(settings: settings)
        menu = StatusMenu(settings: settings)
        menu.onMenuWillOpen = { [weak self] in self?.tracker.ensureAttached() }

        tracker.mode = settings.focusMode
        tracker.dimOtherScreens = !settings.dimActiveScreenOnly
        tracker.keepTiledBright = settings.keepTiledBright
        tracker.onTarget = { [weak self] target in self?.overlays.update(target: target) }
        overlays.onStale = { [weak self] in self?.tracker.scheduleUpdate() }

        settings.onChange = { [weak self] change in self?.settingsChanged(change) }
        drags.onScreenChanged = { [weak self] screen in self?.overlays.setDragScreen(screen) }
        // Mission Control, App Exposé and Show Desktop: no effect there; reorder under the active window after.
        systemMode.onChange = { [weak self] active in
            guard let self else { return }
            self.overlays.setSuspended(active, reason: .systemMode)
            if !active { self.tracker.refresh(force: true) }
        }
        // Picking what to capture with ⌘⇧4 or ⌘⇧5 (Hide in Screenshots): the effect steps aside, so you see what
        // you'll get. Its window selection shows a normal-level window of its own meanwhile: reorder after.
        screenshotUI.onChange = { [weak self] active in
            guard let self else { return }
            self.overlays.setSuspended(active, reason: .screenshot)
            if !active { self.tracker.refresh(force: true) }
        }

        // Quick toggle: a global shortcut and shaking the pointer. Both stay active while the effect
        // is off, so they can turn it back on.
        hotKey.onPress = { [weak self] in self?.settings.enabled.toggle() }
        shake.onShake = { [weak self] in
            guard let self else { return }
            self.settings.enabled.toggle()
            if self.pointer.lastMoveFromTrackpad { Haptics.toggled(on: self.settings.enabled) }
        }
        pointer.onMove = { [weak self] p, time in
            guard let self else { return }
            if self.settings.shakeToToggle { self.shake.moved(p, at: time) }
            if self.peekActive { self.peek.pointerMoved(p, at: time) }
        }
        // A click or a drag starts: no shake or highlight is pending.
        pointer.onButton = { [weak self] in
            self?.shake.reset()
            self?.peek.buttonPressed()
        }
        recorder.onRecord = { [weak self] shortcut in self?.settings.shortcut = shortcut }
        menu.onChangeShortcut = { [weak self] in self?.recorder.show() }
        updateQuickToggle()

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.overlays.rebuildScreens()
            self.tracker.refresh(force: true)
        }

        Permissions.requestIfNeeded()
        if settings.enabled { tracker.start() }
        updateDragWatcher()
        updateSystemModeWatcher()
    }

    /// Highlight Window Under Pointer only matters while the effect is on.
    private var peekActive: Bool { settings.highlightUnderPointer && settings.enabled }

    private func updateQuickToggle() {
        hotKey.register(settings.shortcut)
        if !settings.shakeToToggle { shake.reset() }
        updatePointerMonitor()
    }

    /// Pointer moves are needed for shake to toggle (even while the effect is off, to turn it back on) and for
    /// Highlight Window Under Pointer; with neither, the app gets no pointer moves at all.
    private func updatePointerMonitor() {
        if !peekActive { peek.reset() }
        if settings.shakeToToggle || peekActive { pointer.start() } else { pointer.stop() }
    }

    private func updateSystemModeWatcher() {
        if settings.enabled { systemMode.start() } else { systemMode.stop() }
        if settings.enabled && settings.hideInScreenshots { screenshotUI.start() } else { screenshotUI.stop() }
    }

    private func updateDragWatcher() {
        if settings.enabled && settings.hideWhileDragging { drags.start() } else { drags.stop() }
    }

    private func settingsChanged(_ change: SettingsChange) {
        menu.sync()
        switch change {
        case .enabled:
            if settings.enabled {
                tracker.start()
                tracker.refresh(force: true)
            } else {
                overlays.setEnabled(false)
                tracker.stop()
            }
            updateDragWatcher()
            updateSystemModeWatcher()
            updatePointerMonitor()
        case .focusMode:
            tracker.mode = settings.focusMode
        case .dragBehavior:
            updateDragWatcher()
        case .screenshots:
            overlays.updateCaptureVisibility()
            updateSystemModeWatcher()
        case .menuBarCoverage:
            overlays.rebuildScreens()
        case .activeScreenOnly:
            peek.reset()  // a window highlighted on another screen
            tracker.dimOtherScreens = !settings.dimActiveScreenOnly
        case .tiling:
            tracker.keepTiledBright = settings.keepTiledBright
        case .pointerHighlight:
            updatePointerMonitor()
        case .quickToggle:
            updateQuickToggle()
        case .strength:
            overlays.applyEffects(animated: false)
        case .language:
            Localization.use(settings.language)
            menu.buildMenu()
        case .animation, .menuBarIcon, .haptics:
            break  // the menu reads these itself (menu.sync() above)
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()

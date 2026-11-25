import AppKit

/// Notices Mission Control (and App Exposé) and Show Desktop, so the effect can step aside.
///
/// macOS 27 has no public notification for these modes: the Dock's old Exposé AX notifications no longer fire,
/// WindowManager (which now draws them) rejects AX notifications, and nothing is posted to NSWorkspace or the
/// distributed center. While a mode is up, WindowManager shows a window over the whole screen:
/// "ExposeShieldWindow" (layer 19) in Mission Control and App Exposé, "ShowDesktopOverlay" (layer 18) in
/// Show Desktop. Other apps' window titles need Screen Recording access, so it's matched by owner, layer and size.
///
/// Event-driven, through WindowEvents (WindowServer's window shown / destroyed events with the window number):
/// on "shown" the one window is looked up; on "hidden" a known shield is dropped. Nothing runs between events. If SkyLight's notify API is missing, it falls back to checking the
/// window list 5 times a second (see docs/performance.md).
final class SystemModeWatcher {
    /// true while Mission Control, App Exposé or Show Desktop is up.
    var onChange: ((Bool) -> Void)?
    private(set) var active = false
    private var running = false

    private static let owner = "WindowManager"
    private static let markerLayers: Set<Int> = [19, 18]

    /// Shield windows currently on screen.
    private var shields: Set<CGWindowID> = []
    /// While a mode is up: a click rechecks that the shield is still there, in case an event was missed.
    private var clickMonitor: Any?

    /// Subscribed to WindowEvents (once; events are ignored while stopped).
    private var registered = false
    private var subscribed = false

    func start() {
        guard !running else { return }
        running = true
        if !subscribed {
            subscribed = true
            registered = WindowEvents.subscribe { [weak self] type, window in self?.handle(type, window: window) }
        }
        if !registered { startPolling() }
    }

    func stop() {
        running = false
        stopPolling()
        shields.removeAll()
        set(false)
    }

    private func handle(_ type: UInt32, window: CGWindowID) {
        guard running else { return }
        switch type {
        case WindowEvents.shown:
            if isShield(window) { shields.insert(window) }
        case WindowEvents.destroyed:
            shields.remove(window)
        default:
            return
        }
        set(!shields.isEmpty)
    }

    /// One window's description: owner, layer and size.
    private func isShield(_ window: CGWindowID) -> Bool {
        guard let info = (CGWindowListCopyWindowInfo(.optionIncludingWindow, window) as? [[String: Any]])?.first else {
            return false
        }
        return Self.isShield(info)
    }

    private static func isShield(_ w: [String: Any]) -> Bool {
        guard (w[kCGWindowOwnerName as String] as? String) == owner,
              markerLayers.contains(w[kCGWindowLayer as String] as? Int ?? .min),
              let b = w[kCGWindowBounds as String] as? NSDictionary,
              let r = CGRect(dictionaryRepresentation: b as CFDictionary) else { return false }
        return NSScreen.screens.contains { abs($0.frame.width - r.width) < 2 && abs($0.frame.height - r.height) < 2 }
    }

    /// Drops shields that are gone (a missed 1326).
    private func revalidate() {
        let onScreen = Set((CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? [])
            .compactMap { $0[kCGWindowNumber as String] as? CGWindowID })
        shields.formIntersection(onScreen)
        set(!shields.isEmpty)
    }

    private func set(_ value: Bool) {
        guard value != active else { return }
        active = value
        log.debug("system mode \(value ? "on" : "off", privacy: .public)")
        if value, registered {
            clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self?.revalidate() }
            }
        } else if let m = clickMonitor {
            NSEvent.removeMonitor(m)
            clickMonitor = nil
        }
        onChange?(value)
    }

    // MARK: Fallback: polling

    private typealias CreateList = @convention(c) (UInt32, UInt32) -> Unmanaged<CFArray>?
    /// CGWindowListCreate (window numbers only, ~70 µs) isn't exposed to Swift; it's still exported.
    private static let createList: CreateList? = dlsym(dlopen(nil, RTLD_NOW), "CGWindowListCreate")
        .map { unsafeBitCast($0, to: CreateList.self) }
    private static let pollInterval: TimeInterval = 0.2
    private var timer: Timer?
    private var lastIDs: [CGWindowID] = []

    private func startPolling() {
        guard timer == nil else { return }
        log.debug("SkyLight notifications unavailable: polling for system modes")
        let t = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in self?.poll() }
        t.tolerance = Self.pollInterval / 4   // lets macOS coalesce the wakeups
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func stopPolling() {
        timer?.invalidate()
        timer = nil
        lastIDs = []
    }

    private func poll() {
        // Only window numbers each time; descriptions only when that set changes.
        guard let createList = Self.createList,
              let array = createList(CGWindowListOption.optionOnScreenOnly.rawValue, 0)?.takeRetainedValue() else { return }
        // Both CGWindowListCreate and CGWindowListCreateDescriptionFromArray use raw window numbers, not CFNumbers.
        let ids = (0..<CFArrayGetCount(array)).map {
            CGWindowID(truncatingIfNeeded: UInt(bitPattern: CFArrayGetValueAtIndex(array, $0)))
        }
        guard ids != lastIDs else { return }
        lastIDs = ids
        let info = CGWindowListCreateDescriptionFromArray(array) as? [[String: Any]] ?? []
        set(info.contains(where: Self.isShield))
    }
}

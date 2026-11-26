import AppKit

/// Pointer moves and mouse button presses, shared by the features that follow the pointer (shake to toggle,
/// highlighting the window under the pointer), so turning on both doesn't double the cost.
///
/// They come from a listen-only CGEventTap: it gets them straight from WindowServer, about three times cheaper
/// than an NSEvent global monitor (no NSEvent wrapping or AppKit dispatch). A listen-only tap for mouse events
/// needs no permission. Only plain moves are reported (not drags), so moving windows or files never counts.
final class PointerMonitor {
    /// Pointer position in global Quartz coordinates (origin at the top left of the main screen), and the time.
    var onMove: ((CGPoint, TimeInterval) -> Void)?
    /// Any mouse button went down.
    var onButton: (() -> Void)?

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    var isRunning: Bool { tap != nil }

    func start() {
        guard tap == nil else { return }
        let callback: CGEventTapCallBack = { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let me = Unmanaged<PointerMonitor>.fromOpaque(context).takeUnretainedValue()
            switch type {
            case .mouseMoved:
                me.onMove?(event.location, ProcessInfo.processInfo.systemUptime)
            case .leftMouseDown, .rightMouseDown, .otherMouseDown:
                me.onButton?()
            case .tapDisabledByTimeout, .tapDisabledByUserInput:
                // macOS turns a tap off if it's ever too slow; turn it back on.
                if let tap = me.tap { CGEvent.tapEnable(tap: tap, enable: true) }
            default:
                break
            }
            return Unmanaged.passUnretained(event)
        }
        let events: [CGEventType] = [.mouseMoved, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        let mask = events.reduce(CGEventMask(0)) { $0 | CGEventMask(1 << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap, options: .listenOnly,
                                          eventsOfInterest: mask, callback: callback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque())
        else {
            log.error("couldn't create the event tap for pointer moves")
            return
        }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
    }

    func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
    }
}

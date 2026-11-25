import AppKit

/// Detects a shake of the pointer: quick, small left-right wiggles in place, like Monocle's shake to toggle.
///
/// Only a real shake counts, to avoid false triggers from normal work:
/// - several strokes in a row (`strokesNeeded` within `window`), each quick (`maxStrokeTime`);
/// - small ones: a stroke's swing is between `minSwing` and `maxSwing`, so wide fast sweeps don't count;
/// - in place: the strokes' turning points stay within about one swing, so a zigzag that travels doesn't count;
/// - horizontal: a stroke may drift vertically by at most `maxVerticalRatio` of its swing;
/// - jitter below `reverseThreshold` doesn't count as a change of direction.
/// Only plain moves count (not drags), so moving windows or files never triggers it.
///
/// Mouse moves come from a listen-only CGEventTap: it gets them straight from WindowServer, about three times
/// cheaper than an NSEvent global monitor (no NSEvent wrapping or AppKit dispatch).
/// A listen-only tap for mouse moves needs no permission. The work per event is a few comparisons.
final class ShakeDetector {
    var onShake: (() -> Void)?

    private let strokesNeeded = 6
    private let window: TimeInterval = 1.0
    private let maxStrokeTime: TimeInterval = 0.18
    private let minSwing: CGFloat = 12
    private let maxSwing: CGFloat = 160
    private let maxVerticalRatio: CGFloat = 0.6
    /// Swings may differ, but not wildly (largest / smallest).
    private let maxSwingRatio: CGFloat = 3
    /// The turning points of the whole shake fit within this many of its largest swings.
    private let maxSpanRatio: CGFloat = 1.6
    private let reverseThreshold: CGFloat = 4
    /// A pause this long ends a shake.
    private let maxPause: TimeInterval = 0.2
    private let cooldown: TimeInterval = 1.0

    private struct Stroke {
        let swing: CGFloat
        let end: TimeInterval
        let turnX: CGFloat
    }

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var lastTime: TimeInterval = 0
    private var direction: CGFloat = 0
    /// Where the current stroke started, its furthest point so far, and its vertical extent.
    private var strokeStart = CGPoint.zero
    private var strokeStartTime: TimeInterval = 0
    private var extreme = CGPoint.zero
    private var extremeTime: TimeInterval = 0
    private var minY: CGFloat = 0
    private var maxY: CGFloat = 0
    private var strokes: [Stroke] = []
    private var lastFired: TimeInterval = 0

    func start() {
        guard tap == nil else { return }
        let callback: CGEventTapCallBack = { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let me = Unmanaged<ShakeDetector>.fromOpaque(context).takeUnretainedValue()
            switch type {
            case .mouseMoved:
                me.moved(event.location, at: ProcessInfo.processInfo.systemUptime)
            case .tapDisabledByTimeout, .tapDisabledByUserInput:
                // macOS turns a tap off if it's ever too slow; turn it back on.
                if let tap = me.tap { CGEvent.tapEnable(tap: tap, enable: true) }
            default:
                break
            }
            return Unmanaged.passUnretained(event)
        }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap, options: .listenOnly,
                                          eventsOfInterest: CGEventMask(1 << CGEventType.mouseMoved.rawValue),
                                          callback: callback, userInfo: Unmanaged.passUnretained(self).toOpaque())
        else {
            log.error("couldn't create the event tap for shake to toggle")
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
        reset(at: .zero, time: 0)
    }

    private func reset(at p: CGPoint, time: TimeInterval) {
        strokes.removeAll()
        direction = 0
        strokeStart = p
        strokeStartTime = time
        extreme = p
        extremeTime = time
        minY = p.y
        maxY = p.y
    }

    /// p is in global screen coordinates; only its changes matter, so the origin doesn't.
    private func moved(_ p: CGPoint, at now: TimeInterval) {
        defer { lastTime = now }
        if now - lastTime > maxPause { reset(at: p, time: now); return }
        minY = min(minY, p.y)
        maxY = max(maxY, p.y)

        if direction == 0 {
            // At rest: the first stroke starts once the pointer has really moved sideways.
            let dx = p.x - strokeStart.x
            if abs(dx) >= reverseThreshold { direction = dx > 0 ? 1 : -1; extreme = p; extremeTime = now }
            return
        }
        if (p.x - extreme.x) * direction > 0 {
            extreme = p  // still going the same way
            extremeTime = now
            return
        }
        guard (extreme.x - p.x) * direction >= reverseThreshold else { return }

        // Turned around at `extreme`: judge the stroke that just ended.
        let swing = abs(extreme.x - strokeStart.x)
        let ok = swing >= minSwing && swing <= maxSwing
            && extremeTime - strokeStartTime <= maxStrokeTime
            && maxY - minY <= swing * maxVerticalRatio
        if ok {
            strokes.append(Stroke(swing: swing, end: extremeTime, turnX: extreme.x))
            strokes.removeAll { now - $0.end > window }
        } else {
            strokes.removeAll()
        }
        // The next stroke starts at the turning point.
        direction = -direction
        strokeStart = extreme
        strokeStartTime = extremeTime
        minY = min(extreme.y, p.y)
        maxY = max(extreme.y, p.y)
        extreme = p
        extremeTime = now

        guard strokes.count >= strokesNeeded, now - lastFired > cooldown else { return }
        let swings = strokes.map(\.swing), turns = strokes.map(\.turnX)
        let largest = swings.max()!, smallest = swings.min()!
        guard largest / smallest <= maxSwingRatio,
              turns.max()! - turns.min()! <= largest * maxSpanRatio else { return }
        lastFired = now
        strokes.removeAll()
        onShake?()
    }
}

import AppKit

/// Detects a shake of the pointer: quick back-and-forth strokes in place, in any direction (with a mouse a
/// diagonal shake comes naturally), like Monocle's shake to toggle.
///
/// Quick strokes are what make a shake, not its exact size or direction:
/// - several strokes in a row (`strokesNeeded` within `window`), each short (at most `maxStrokeTime`) and fast (at
///   least `minSpeed` on average), and short on average (`maxMeanStrokeTime`). Recorded shakes and gentle stroking
///   move the pointer about as fast, but stroking swings wider and slower: about 150 ms a stroke against 100 ms;
/// - a stroke runs from a turning point to the point farthest from it; its swing (that distance) is between
///   `minSwing` and `maxSwing` (about a third of a laptop screen);
/// - straight enough: the path is at most `maxPathRatio` times the swing, so a slight arc from the wrist counts
///   but circling the pointer doesn't (a semicircle is about 1.57);
/// - back and forth: each stroke points roughly opposite to the previous one (within `maxTurnAngle`);
/// - in place: the turning points stay within about one swing, so a zigzag that travels doesn't count;
/// - jitter below `reverseThreshold` doesn't count as a change of direction;
/// - only with nothing held: a mouse button press drops the shake in progress (see `reset`), and none may be down
///   when it fires;
/// - one shake toggles once: after it fires, the pointer has to rest for `rearmRest` before the next one counts,
///   so a long shake with short breaks in it doesn't toggle on and off again.
/// Pointer moves come from PointerMonitor (plain moves only, not drags). The work per move is a few arithmetic
/// operations.
final class ShakeDetector {
    var onShake: (() -> Void)?

    /// Tuned on recorded trackpad moves: these values catch 32 of 34 shakes and none of 14 gentle strokings.
    private let strokesNeeded = 5
    private let window: TimeInterval = 1.0
    private let maxStrokeTime: TimeInterval = 0.18
    /// The strokes of a shake take about 90–110 ms on average; gentle stroking, 140–200 ms.
    private let maxMeanStrokeTime: TimeInterval = 0.13
    /// Average speed of a stroke, pt/s.
    private let minSpeed: CGFloat = 400
    private let minSwing: CGFloat = 20
    private let maxSwing: CGFloat = 500
    private let maxPathRatio: CGFloat = 1.4
    /// How far a stroke may point from the exact opposite of the previous one.
    private let maxTurnAngle: CGFloat = 45
    /// Swings may differ, but not wildly (largest / smallest).
    private let maxSwingRatio: CGFloat = 6
    /// The turning points of the whole shake fit within this many of its largest swings.
    private let maxSpanRatio: CGFloat = 1.6
    private let reverseThreshold: CGFloat = 4
    /// A pause this long ends a shake.
    private let maxPause: TimeInterval = 0.2
    /// After a shake fires, the pointer has to rest this long before another shake counts.
    private let rearmRest: TimeInterval = 0.5

    private struct Stroke {
        let vector: CGVector
        let swing: CGFloat
        let duration: TimeInterval
        let end: TimeInterval
        let turn: CGPoint
    }

    private var lastTime: TimeInterval = 0
    private var last = CGPoint.zero
    /// The current stroke: where it started, its farthest point from there, and the path length travelled.
    private var strokeStart = CGPoint.zero
    private var strokeStartTime: TimeInterval = 0
    private var started = false
    private var extreme = CGPoint.zero
    private var extremeDistance: CGFloat = 0
    private var extremeTime: TimeInterval = 0
    private var path: CGFloat = 0            // since the stroke started
    private var pathAtExtreme: CGFloat = 0
    private var strokes: [Stroke] = []
    private var armed = true

    /// Forgets the shake in progress (shake to toggle was turned off, or a mouse button went down): the next move
    /// starts afresh, as after a pause.
    func reset() {
        strokes.removeAll()
        lastTime = 0
    }

    private func reset(at p: CGPoint, time: TimeInterval) {
        strokes.removeAll()
        startStroke(at: p, time: time)
    }

    private func startStroke(at p: CGPoint, time: TimeInterval) {
        strokeStart = p
        strokeStartTime = time
        started = false
        extreme = p
        extremeDistance = 0
        extremeTime = time
        path = 0
        pathAtExtreme = 0
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }

    /// p is in global screen coordinates; only its changes matter, so the origin doesn't.
    func moved(_ p: CGPoint, at now: TimeInterval) {
        defer { lastTime = now; last = p }
        if now - lastTime > rearmRest { armed = true }
        if now - lastTime > maxPause { reset(at: p, time: now); return }
        path += Self.distance(p, last)
        let d = Self.distance(p, strokeStart)

        if !started {
            // At rest: the first stroke starts once the pointer has really moved.
            if d >= reverseThreshold { started = true; extreme = p; extremeDistance = d; extremeTime = now; pathAtExtreme = path }
            return
        }
        if d > extremeDistance {
            extreme = p  // still moving away from where the stroke started
            extremeDistance = d
            extremeTime = now
            pathAtExtreme = path
            return
        }
        // Turned around once the pointer has come back from the farthest point along the stroke's direction.
        let axis = CGVector(dx: (extreme.x - strokeStart.x) / extremeDistance, dy: (extreme.y - strokeStart.y) / extremeDistance)
        let back = (extreme.x - p.x) * axis.dx + (extreme.y - p.y) * axis.dy
        guard back >= reverseThreshold else { return }

        // Judge the stroke that just ended at `extreme`.
        let swing = extremeDistance
        let duration = extremeTime - strokeStartTime
        let vector = CGVector(dx: extreme.x - strokeStart.x, dy: extreme.y - strokeStart.y)
        let ok = swing >= minSwing && swing <= maxSwing
            && duration <= maxStrokeTime && swing / CGFloat(max(duration, 0.001)) >= minSpeed
            && pathAtExtreme <= swing * maxPathRatio
        if ok {
            // Back and forth: roughly opposite to the previous stroke, otherwise a new run starts here.
            if let previous = strokes.last {
                let cosine = (vector.dx * previous.vector.dx + vector.dy * previous.vector.dy) / (swing * previous.swing)
                if cosine > -cos(maxTurnAngle * .pi / 180) { strokes.removeAll() }
            }
            strokes.append(Stroke(vector: vector, swing: swing, duration: duration, end: extremeTime, turn: extreme))
            strokes.removeAll { now - $0.end > window }
        } else {
            strokes.removeAll()
        }
        // The next stroke starts at the turning point, with what was travelled since then.
        let travelled = path - pathAtExtreme
        let turnTime = extremeTime
        startStroke(at: extreme, time: turnTime)
        path = travelled
        started = true
        extreme = p
        extremeDistance = Self.distance(p, strokeStart)
        extremeTime = now
        pathAtExtreme = path

        guard strokes.count >= strokesNeeded, armed else { return }
        let swings = strokes.map(\.swing), turns = strokes.map(\.turn)
        let largest = swings.max()!, smallest = swings.min()!
        var span: CGFloat = 0
        for i in turns.indices { for j in turns.indices where j > i { span = max(span, Self.distance(turns[i], turns[j])) } }
        let meanTime = strokes.reduce(0) { $0 + $1.duration } / Double(strokes.count)
        guard largest / smallest <= maxSwingRatio, span <= largest * maxSpanRatio, meanTime <= maxMeanStrokeTime,
              NSEvent.pressedMouseButtons == 0 else { return }
        armed = false
        strokes.removeAll()
        onShake?()
    }
}

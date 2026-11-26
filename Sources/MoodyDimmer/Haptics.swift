import AppKit
import IOKit

/// Light taps of the Force Touch trackpad: while a slider is dragged (growing with its value) and a short buzz when
/// shaking the pointer toggles the effect (swelling when it comes on, fading when it goes off). Only for input that
/// comes from a trackpad: with a mouse nothing happens.
///
/// The taps drive the trackpad's actuator directly through the private MultitouchSupport framework, the way
/// HapticKey does: it lets the strength vary, and it works while the system's "Force Click and haptic feedback" is off
/// and while the app is in the background. If the framework or its functions are ever gone, it falls back to
/// NSHapticFeedbackManager (fixed strength; only when the system setting is on).
enum Haptics {
    /// Strength of a slider step: grows with the slider's value from `stepMin` (near 0) to `stepMax` (at the end).
    /// The scale is the actuator's own (0 is a light tap, 6 is strong); tuned by feel on a MacBook trackpad.
    private static let stepMin: Float = 0
    private static let stepMax: Float = 1.0
    /// The top end of a slider gets a slightly firmer tap than the steps before it.
    private static let endBoost: Float = 0.4
    /// Shaking the pointer turned the effect on or off: a short buzz of `toggleTaps` taps, `toggleGap` apart, that
    /// swells from `toggleSoft` to `toggleFirm` when the effect comes on and fades the other way when it goes off.
    private static let toggleSoft: Float = 0
    private static let toggleFirm: Float = 0.5
    private static let toggleTaps = 6
    private static let toggleGap: TimeInterval = 0.02
    /// The actuator's tap waveform (valid: 1–6, 15, 16): 1 is a soft, dull one, chosen by feel.
    fileprivate static let kind: Int32 = 1

    /// A quick drag crosses many 1 % steps at once: taps closer than this would blur into a buzz.
    private static let minInterval: TimeInterval = 0.025
    private static var lastTick: TimeInterval = 0

    /// A slider moved from one 1 % step to another, now at `fraction` (0…1); `atEnd` when it reached the top end.
    static func sliderStep(fraction: Double, atEnd: Bool) {
        guard Settings.shared.haptics else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard atEnd || now - lastTick >= minInterval else { return }
        lastTick = now
        let strength = stepMin + (stepMax - stepMin) * Float(min(max(fraction, 0), 1)) + (atEnd ? endBoost : 0)
        tap(strength: strength, fallback: atEnd ? .levelChange : .alignment)
    }

    /// Shaking the pointer turned the effect on (a swelling buzz) or off (a fading one).
    static func toggled(on: Bool) {
        guard Settings.shared.haptics else { return }
        func strength(_ i: Int) -> Float {
            let t = Float(i) / Float(toggleTaps - 1)
            return toggleSoft + (toggleFirm - toggleSoft) * (on ? t : 1 - t)
        }
        tap(strength: strength(0), fallback: .levelChange)
        for i in 1..<toggleTaps {
            DispatchQueue.main.asyncAfter(deadline: .now() + toggleGap * Double(i)) {
                _ = Actuator.shared.actuate(strength: strength(i))  // the system API can't buzz: one tap there
            }
        }
    }

    private static func tap(strength: Float, fallback: NSHapticFeedbackManager.FeedbackPattern) {
        if !Actuator.shared.actuate(strength: strength) {
            NSHapticFeedbackManager.defaultPerformer.perform(fallback, performanceTime: .now)
        }
    }

    // MARK: Where the input comes from

    /// A mouse event made by a trackpad (or another touch surface) rather than a mouse.
    static func isFromTrackpad(_ event: NSEvent) -> Bool {
        event.subtype == .touch
    }

    static func isFromTrackpad(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.mouseEventSubtype) == Int64(NSEvent.EventSubtype.touch.rawValue)
    }

    /// A scroll with a gesture phase comes from a trackpad (or a Magic Mouse, which has no actuator: harmless).
    static func isScrollFromTrackpad(_ event: NSEvent) -> Bool {
        event.hasPreciseScrollingDeltas && (!event.phase.isEmpty || !event.momentumPhase.isEmpty)
    }
}

/// The Force Touch actuators of the trackpads (the built-in one, a Magic Trackpad), through MultitouchSupport.
/// They're opened on the first tap and closed after a short idle time, so nothing is held while sliders and the
/// shake aren't used; a trackpad connected later is picked up at the next opening.
private final class Actuator {
    static let shared = Actuator()

    private typealias CreateFn = @convention(c) (UInt64) -> Unmanaged<CFTypeRef>?
    private typealias OpenCloseFn = @convention(c) (CFTypeRef) -> Int32
    private typealias ActuateFn = @convention(c) (CFTypeRef, Int32, UInt32, Float, Float) -> Int32

    private struct API {
        let create: CreateFn, open: OpenCloseFn, close: OpenCloseFn, actuate: ActuateFn
    }
    private let api: API?
    private var open: [CFTypeRef] = []
    private var closeWork: DispatchWorkItem?
    private let idleClose: TimeInterval = 3

    private init() {
        let path = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"
        guard let lib = dlopen(path, RTLD_NOW),
              let create = dlsym(lib, "MTActuatorCreateFromDeviceID"),
              let open = dlsym(lib, "MTActuatorOpen"),
              let close = dlsym(lib, "MTActuatorClose"),
              let actuate = dlsym(lib, "MTActuatorActuate")
        else {
            log.info("trackpad actuator API unavailable: using system haptic feedback")
            api = nil
            return
        }
        api = API(create: unsafeBitCast(create, to: CreateFn.self), open: unsafeBitCast(open, to: OpenCloseFn.self),
                  close: unsafeBitCast(close, to: OpenCloseFn.self), actuate: unsafeBitCast(actuate, to: ActuateFn.self))
    }

    /// false when there's no actuator to use (the caller falls back to the system API).
    /// The strength is the first float parameter (the second one makes the taps uneven).
    func actuate(strength: Float) -> Bool {
        guard let api else { return false }
        if open.isEmpty { openActuators(api) }
        guard !open.isEmpty else { return false }
        var played = false
        for a in open where api.actuate(a, Haptics.kind, 0, strength, 0) == 0 { played = true }
        scheduleClose(api)
        return played
    }

    private func openActuators(_ api: API) {
        for id in Self.deviceIDs() {
            guard let a = api.create(id)?.takeRetainedValue() else { continue }
            if api.open(a) == 0 { open.append(a) }
        }
        if open.isEmpty { log.info("no trackpad actuator could be opened") }
    }

    private func scheduleClose(_ api: API) {
        closeWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.open.forEach { _ = api.close($0) }
            self.open = []
        }
        closeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + idleClose, execute: work)
    }

    /// Multitouch devices that have a Force Touch actuator.
    private static func deviceIDs() -> [UInt64] {
        var it: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleMultitouchDevice"), &it)
                == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(it) }
        var ids: [UInt64] = []
        while case let s = IOIteratorNext(it), s != 0 {
            defer { IOObjectRelease(s) }
            func property(_ key: String) -> Any? {
                IORegistryEntryCreateCFProperty(s, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
            }
            guard (property("ActuationSupported") as? Bool) == true,
                  let id = property("Multitouch ID") as? NSNumber else { continue }
            ids.append(id.uint64Value)
        }
        return ids
    }
}

import AppKit
import QuartzCore

/// Effect parameters applied to every overlay.
/// The curves are chosen so each slider feels even across its whole range.
struct EffectParams: Equatable {
    var dimOpacity: Float     // 0…1
    var blur: Double          // 0…1, blur strength (0 = blur off)
    var grainOpacity: Float   // 0…0.5

    static func from(_ s: Settings) -> EffectParams {
        // Dim: black is composited in gamma space, so linear opacity already looks even.
        // 100% is fully black: everything but the bright windows disappears.
        let dim = s.effect.hasDim ? Float(s.dimStrength) : 0
        let blur = s.effect.hasBlur ? s.blurStrength : 0
        // Grain: barely visible at low values, so the curve is concave (x^0.75).
        let grain = s.grainStrength > 0 ? Float(0.5 * pow(s.grainStrength, 0.75)) : 0
        return EffectParams(dimOpacity: dim, blur: blur, grainOpacity: grain)
    }
}

/// NSVisualEffectView with a real blur radius.
///
/// Inside NSVisualEffectView there is a `CABackdropLayer` with a `gaussianBlur` filter (default radius ≈ 30).
/// We change its inputRadius and hide the tint layers (dimming is done separately).
/// AppKit recreates these layers only on an appearance change, so we reapply then.
/// If a future macOS changes the layer structure, we fall back to alpha-based strength.
final class BlurView: NSVisualEffectView {
    /// Radius for strength s. Perceived blur grows roughly logarithmically with the radius,
    /// so the curve is convex: 10% ≈ 1 pt, 30% ≈ 7 pt, 50% ≈ 17 pt, 80% ≈ 35 pt, 100% = 50 pt.
    static func radius(for s: Double) -> CGFloat { CGFloat(50 * pow(s, 1.6)) }

    private(set) var radius: CGFloat = 30
    /// Called after the radius is reapplied (the layers may have appeared or been recreated).
    var onReapplied: (() -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        reapplySoon()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        reapplySoon()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        reapplySoon()
    }

    private func reapplySoon() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.setRadius(self.radius, duration: 0)
            self.onReapplied?()
        }
    }

    /// Returns false when the radius can't be controlled (no backdrop layer).
    @discardableResult
    func setRadius(_ r: CGFloat, duration: TimeInterval) -> Bool {
        let old = radius
        radius = r
        guard let root = layer, let backdrop = Self.findBackdrop(in: root), Self.hasBlurFilter(backdrop) else {
            return false
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        backdrop.setValue(r, forKeyPath: "filters.gaussianBlur.inputRadius")
        // Neutral blur: hide the material's tint layers.
        for sibling in backdrop.superlayer?.sublayers ?? [] where sibling !== backdrop {
            sibling.isHidden = true
        }
        CATransaction.commit()
        if duration > 0, old != r {
            let a = CABasicAnimation(keyPath: "filters.gaussianBlur.inputRadius")
            a.fromValue = old
            a.toValue = r
            a.duration = duration
            a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            backdrop.add(a, forKey: "radius")
        }
        return true
    }

    var supportsRadius: Bool {
        guard let root = layer, let b = Self.findBackdrop(in: root) else { return false }
        return Self.hasBlurFilter(b)
    }

    private static func findBackdrop(in layer: CALayer) -> CALayer? {
        if NSStringFromClass(type(of: layer)).contains("Backdrop") { return layer }
        for sub in layer.sublayers ?? [] {
            if let found = findBackdrop(in: sub) { return found }
        }
        return nil
    }

    private static func hasBlurFilter(_ layer: CALayer) -> Bool {
        (layer.filters ?? []).contains { (($0 as AnyObject).value(forKey: "name") as? String) == "gaussianBlur" }
    }
}

/// Overlay content: blur → dim → grain. The mask cuts out the "windows".
final class EffectView: NSView {
    private let blurView = BlurView()
    private let tintView = NSView()
    private let dimLayer = CALayer()
    private let grainLayer = CALayer()
    private let maskLayer = CAShapeLayer()
    /// Mask during a focus change: a fixed part plus two parts whose opacity animates (see transitionMask).
    private let transitionLayer = CALayer()
    private let fixedPart = CAShapeLayer()
    private let fadeInPart = CAShapeLayer()
    private let fadeOutPart = CAShapeLayer()
    private var transitionID = 0
    private var current: EffectParams?
    /// Blur was applied the fallback way (the layers didn't exist yet: the window hadn't been shown).
    private var blurUsesFallback = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .never

        blurView.blendingMode = .behindWindow
        blurView.material = .fullScreenUI
        blurView.state = .active
        blurView.appearance = NSAppearance(named: .darkAqua)  // stable look, fewer layer rebuilds
        blurView.autoresizingMask = [.width, .height]
        blurView.frame = bounds
        blurView.isHidden = true
        addSubview(blurView)

        tintView.wantsLayer = true
        tintView.layerContentsRedrawPolicy = .never
        tintView.autoresizingMask = [.width, .height]
        tintView.frame = bounds
        addSubview(tintView)

        let noActions: [String: CAAction] = [
            "bounds": NSNull(), "position": NSNull(), "frame": NSNull(),
            "contents": NSNull(), "backgroundColor": NSNull(), "path": NSNull(),
            "hidden": NSNull(),
        ]

        dimLayer.backgroundColor = NSColor.black.cgColor
        dimLayer.opacity = 0
        dimLayer.actions = noActions
        tintView.layer?.addSublayer(dimLayer)

        grainLayer.isHidden = true
        grainLayer.opacity = 0
        grainLayer.actions = noActions
        tintView.layer?.addSublayer(grainLayer)

        maskLayer.fillColor = NSColor.black.cgColor
        maskLayer.actions = noActions
        transitionLayer.actions = noActions
        for part in [fixedPart, fadeInPart, fadeOutPart] {
            part.fillColor = NSColor.black.cgColor
            part.actions = noActions.merging(["opacity": NSNull()]) { $1 }
            transitionLayer.addSublayer(part)
        }

        blurView.onReapplied = { [weak self] in
            guard let self, let c = self.current, c.blur > 0 else { return }
            self.applyBlur(c.blur, duration: 0)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        dimLayer.frame = tintView.bounds
        grainLayer.frame = tintView.bounds
        maskLayer.frame = bounds
        transitionLayer.frame = bounds
        for part in [fixedPart, fadeInPart, fadeOutPart] { part.frame = bounds }
        CATransaction.commit()
    }

    /// Applies effect strengths. duration = 0 means instant.
    func apply(_ p: EffectParams, duration: TimeInterval) {
        guard p != current else { return }
        current = p

        if p.grainOpacity > 0, grainLayer.backgroundColor == nil {
            grainLayer.backgroundColor = GrainTile.shared.patternColor
        }

        CATransaction.begin()
        if duration > 0 {
            CATransaction.setAnimationDuration(duration)
        } else {
            CATransaction.setDisableActions(true)
        }
        dimLayer.opacity = p.dimOpacity
        if p.grainOpacity > 0 { grainLayer.isHidden = false }
        grainLayer.opacity = p.grainOpacity
        CATransaction.setCompletionBlock { [weak self] in
            guard let self, let c = self.current else { return }
            if c.grainOpacity == 0 { self.grainLayer.isHidden = true }
        }
        CATransaction.commit()

        applyBlur(p.blur, duration: duration)
    }

    private func applyBlur(_ s: Double, duration: TimeInterval) {
        guard s > 0 else {
            // Hide the view completely so WindowServer stops computing the blur.
            guard !blurView.isHidden else { return }
            animate(duration, { self.blurView.animator().alphaValue = 0 }, completion: { [weak self] in
                guard let self, (self.current?.blur ?? 0) == 0 else { return }
                self.blurView.isHidden = true
            })
            return
        }

        let appearing = blurView.isHidden
        if appearing {
            blurView.alphaValue = 0
            blurView.isHidden = false
            blurView.layoutSubtreeIfNeeded()
        }
        let radiusOK = blurView.setRadius(BlurView.radius(for: s), duration: appearing ? 0 : duration)
        // With a real radius the view is fully opaque (with a short ramp at the lowest values
        // to avoid a saturation jump). Without it, the fallback: strength via alpha.
        blurUsesFallback = !radiusOK
        let alpha = radiusOK ? CGFloat(min(1, s / 0.08)) : CGFloat(sqrt(s))
        if blurView.alphaValue != alpha {
            animate(duration) { self.blurView.animator().alphaValue = alpha }
        }
    }

    /// Call after the window is shown: the backdrop layer exists only for an on-screen window.
    /// The layers are created on the next draw, so try now and on the next runloop passes.
    func windowDidOrderIn(attempt: Int = 0) {
        guard blurUsesFallback, let c = current, c.blur > 0 else { return }
        blurView.layoutSubtreeIfNeeded()
        applyBlur(c.blur, duration: 0)
        guard blurUsesFallback, attempt < 3 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03 * Double(attempt)) { [weak self] in
            self?.windowDidOrderIn(attempt: attempt + 1)
        }
    }

    /// path is the area where the effect is visible (local coordinates); nil means the whole screen.
    /// Ends a running transition.
    func setMask(_ path: CGPath?) {
        cancelTransition()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let path {
            maskLayer.path = path
            if layer?.mask !== maskLayer { layer?.mask = maskLayer }
        } else if layer?.mask != nil {
            layer?.mask = nil
        }
        CATransaction.commit()
    }

    /// Animates the mask for a focus change, all in local coordinates: `fixed` stays visible, `fadeIn` goes from
    /// clear to visible, `fadeOut` from visible to clear. The three areas don't overlap, so the rest of the screen
    /// is untouched while only the windows changing state brighten or dim. `before` runs once the starting mask
    /// is on screen (to reorder the window without a flash); `completion` runs at the end unless interrupted.
    func transitionMask(fixed: CGPath, fadeIn: CGPath, fadeOut: CGPath, duration: TimeInterval,
                        before: () -> Void, completion: @escaping () -> Void) {
        cancelTransition()
        let id = transitionID
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fixedPart.path = fixed
        fadeInPart.path = fadeIn
        fadeOutPart.path = fadeOut
        fadeInPart.opacity = 0
        fadeOutPart.opacity = 1
        layer?.mask = transitionLayer
        CATransaction.commit()
        CATransaction.flush()
        before()

        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            guard let self, self.transitionID == id else { return }
            completion()
        }
        for (part, from, to) in [(fadeInPart, Float(0), Float(1)), (fadeOutPart, Float(1), Float(0))] {
            let a = CABasicAnimation(keyPath: "opacity")
            a.fromValue = from
            a.toValue = to
            a.duration = duration
            a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            part.opacity = to
            part.add(a, forKey: "fade")
        }
        CATransaction.commit()
    }

    private func cancelTransition() {
        transitionID += 1
        fadeInPart.removeAnimation(forKey: "fade")
        fadeOutPart.removeAnimation(forKey: "fade")
    }

    private func animate(_ duration: TimeInterval, _ changes: @escaping () -> Void, completion: (() -> Void)? = nil) {
        if duration > 0 {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = duration
                changes()
            }, completionHandler: completion)
        } else {
            NSAnimationContext.beginGrouping()
            NSAnimationContext.current.duration = 0
            changes()
            NSAnimationContext.endGrouping()
            completion?()
        }
    }
}

/// Noise tile, generated once (256×256 px ≈ 256 KB) and tiled via a pattern color.
///
/// Each pixel is white or black with opacity |n|, where n follows a triangular distribution
/// around zero. The grain is contrasty but barely shifts overall brightness (no grey veil).
final class GrainTile {
    static let shared = GrainTile()

    lazy var patternColor: CGColor = {
        let px = 256
        var bytes = [UInt8](repeating: 0, count: px * px * 4)
        var rng = SystemRandomNumberGenerator()
        for i in stride(from: 0, to: bytes.count, by: 4) {
            let n = Double.random(in: -0.5...0.5, using: &rng) + Double.random(in: -0.5...0.5, using: &rng)
            let a = UInt8(min(255, abs(n) * 255))
            let v: UInt8 = n > 0 ? a : 0  // premultiplied: white = (a,a,a,a), black = (0,0,0,a)
            bytes[i] = v; bytes[i + 1] = v; bytes[i + 2] = v
            bytes[i + 3] = a
        }
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        let cg = CGImage(
            width: px, height: px, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: px * 4,
            space: cs, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )!
        // 256 px = 128 pt on Retina: grain the size of a physical pixel.
        let img = NSImage(cgImage: cg, size: NSSize(width: px / 2, height: px / 2))
        return NSColor(patternImage: img).cgColor
    }()
}

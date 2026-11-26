// Generates the app icon. The app ships the dark theme of the `current` variant; every variant can also
// be drawn in a light theme for comparison.
//
//   swift scripts/make-icon.swift "$PWD" [variant] [theme]   write the icon resources (default: `current`)
//   swift scripts/make-icon.swift "$PWD" --preview <dir>     512 px PNGs of every variant in both themes
//
// Output (in Resources/):
//   AppIcon.icon   Icon Composer format; build-app.sh compiles it with Xcode's actool
//                  (macOS applies the icon shape mask itself)
//   AppIcon.icns   fallback for builds without Xcode
//
// Previews of all variants are kept in Design/AppIcon (regenerate with --preview Design/AppIcon).
//
// Variants:
//   cascade  a background window behind the active one, under one veil (matches the menu bar icon)
//   veil     the active window centered, background windows symmetric under one veil
//   dimmer   a dimmer knob: a scale from dim to bright around it, the bright window on its face

import AppKit
import CoreGraphics

let variants = ["cascade", "veil", "dimmer"]
let themes = ["light", "dark"]
let current = (variant: "cascade", theme: "dark")

let S: CGFloat = 1024
let cs = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: cs, components: [
        CGFloat((hex >> 16) & 0xFF) / 255, CGFloat((hex >> 8) & 0xFF) / 255, CGFloat(hex & 0xFF) / 255, a,
    ])!
}

func roundedRect(_ r: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

/// Rect of the given size centered at a point.
func rect(center c: CGPoint, _ w: CGFloat, _ h: CGFloat) -> CGRect {
    CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h)
}

// MARK: - Themes

struct Theme {
    var tileBase: UInt32
    var tileShadow: CGFloat
    var background: (UInt32, UInt32)          // plain background, top → bottom
    var wallpaper: (UInt32, UInt32)           // the "screen" under the veil, top → bottom
    var backWindow: UInt32
    var backTitle: UInt32
    var veil: (UInt32, CGFloat)
    var grain: (white: CGFloat, black: CGFloat)
    var windowGlow: CGFloat                   // warm glow around bright shapes
    var windowShadow: CGFloat                 // dark drop shadow under bright shapes (light theme)
    var scaleDim: (UInt32, CGFloat)           // dimmer scale, dim end
    var scaleBright: UInt32                   // dimmer scale, bright end
    var knob: (UInt32, UInt32)
}

let darkTheme = Theme(
    tileBase: 0x15171D, tileShadow: 0.35,
    background: (0x2E3340, 0x111318), wallpaper: (0x5A6478, 0x2A303C),
    backWindow: 0xC9CED8, backTitle: 0xAEB4C0, veil: (0x07080B, 0.72), grain: (0.06, 0.09),
    windowGlow: 0.5, windowShadow: 0,
    scaleDim: (0xFFF1DA, 0.18), scaleBright: 0xFFF1DA, knob: (0x434956, 0x1B1E24))

let lightTheme = Theme(
    tileBase: 0xE9EBF0, tileShadow: 0.22,
    background: (0xFBFBFD, 0xDCDFE6), wallpaper: (0xEEF0F4, 0xCDD2DB),
    backWindow: 0xFFFFFF, backTitle: 0xE2E5EB, veil: (0x3A4252, 0.30), grain: (0.10, 0.04),
    windowGlow: 0.25, windowShadow: 0.28,
    scaleDim: (0x8A909C, 0.35), scaleBright: 0xF0A03A, knob: (0xFFFFFF, 0xD3D7DF))

var T = darkTheme

// macOS icon grid: an 824×824 squircle with a 100 px inset.
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
var tilePath = roundedRect(tile, 185)
let center = CGPoint(x: tile.midX, y: tile.midY)

// MARK: - Shared pieces

func drawTileShadow(_ ctx: CGContext) {
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, T.tileShadow))
    ctx.addPath(tilePath); ctx.setFillColor(color(T.tileBase)); ctx.fillPath()
    ctx.restoreGState()
}

func drawGradient(_ ctx: CGContext, _ colors: (UInt32, UInt32), in r: CGRect = tile) {
    let g = CGGradient(colorsSpace: cs, colors: [color(colors.0), color(colors.1)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: r.maxY), end: CGPoint(x: 0, y: r.minY), options: [])
}

/// Seeded random numbers (SplitMix64), so the same icon always renders to the same pixels
/// and regenerating doesn't produce noise in git.
struct SeededRandom: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
var grainSeed = SeededRandom(state: 1)

/// Static grain inside the current clip, a nod to the grain effect.
func drawGrain(_ ctx: CGContext, count: Int = 28000) {
    var rng = grainSeed
    defer { grainSeed = rng }
    for _ in 0..<count {
        let x = CGFloat.random(in: tile.minX..<tile.maxX, using: &rng)
        let y = CGFloat.random(in: tile.minY..<tile.maxY, using: &rng)
        ctx.setFillColor(Bool.random(using: &rng) ? color(0xFFFFFF, T.grain.white) : color(0x000000, T.grain.black))
        ctx.fill(CGRect(x: x, y: y, width: 2, height: 2))
    }
}

/// Plain background with grain.
func drawPlainTile(_ ctx: CGContext) {
    drawTileShadow(ctx)
    ctx.saveGState()
    ctx.addPath(tilePath); ctx.clip()
    drawGradient(ctx, T.background)
    drawGrain(ctx)
    ctx.restoreGState()
}

/// A background window at full brightness (the veil dims it later).
func drawBackWindow(_ ctx: CGContext, _ r: CGRect, radius: CGFloat, shadow: Bool) {
    let p = roundedRect(r, radius)
    ctx.saveGState()
    if shadow { ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 24, color: color(0x000000, 0.45)) }
    ctx.addPath(p); ctx.setFillColor(color(T.backWindow)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(p); ctx.clip()
    ctx.setFillColor(color(T.backTitle))
    ctx.fill(CGRect(x: r.minX, y: r.maxY - radius * 1.6, width: r.width, height: radius * 1.6))
    ctx.restoreGState()
}

/// The single veil with grain: the whole tile except `hole` (if any).
func drawVeil(_ ctx: CGContext, hole: CGPath?) {
    let veil = CGMutablePath()
    veil.addPath(tilePath)
    if let hole { veil.addPath(hole) }
    ctx.addPath(veil); ctx.setFillColor(color(T.veil.0, T.veil.1)); ctx.fillPath(using: .evenOdd)
    ctx.saveGState()
    ctx.addPath(veil); ctx.clip(using: .evenOdd)
    drawGrain(ctx, count: 30000)
    ctx.restoreGState()
}

/// Draws `shape` lit: a drop shadow (light theme) and a warm glow, then `fill` clipped to the shape.
func drawLit(_ ctx: CGContext, _ shape: CGPath, fill: () -> Void) {
    ctx.saveGState()
    ctx.addPath(tilePath); ctx.clip()
    if T.windowShadow > 0 {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 40, color: color(0x000000, T.windowShadow))
        ctx.addPath(shape); ctx.setFillColor(color(0xFFFFFF)); ctx.fillPath()
        ctx.restoreGState()
    }
    ctx.setShadow(offset: .zero, blur: 100, color: color(0xFFE9C2, T.windowGlow))
    ctx.addPath(shape); ctx.setFillColor(color(0xF7F3EA)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(shape); ctx.clip()
    fill()
    ctx.restoreGState()
}

func drawWarmWhite(_ ctx: CGContext, in r: CGRect) {
    let lit = CGGradient(colorsSpace: cs, colors: [color(0xFFFFFF), color(0xEDE6D8)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(lit, start: CGPoint(x: 0, y: r.maxY), end: CGPoint(x: 0, y: r.minY), options: [])
}

/// The bright, focused window: glow, light gradient, three title bar dots.
func drawBrightWindow(_ ctx: CGContext, _ r: CGRect, radius: CGFloat) {
    drawLit(ctx, roundedRect(r, radius)) { drawWarmWhite(ctx, in: r) }
    let dot = r.height * 0.07, step = dot * 1.65
    for i in 0..<3 {
        let c = CGPoint(x: r.minX + radius * 1.25 + CGFloat(i) * step, y: r.maxY - radius * 1.1)
        ctx.addEllipse(in: CGRect(x: c.x - dot / 2, y: c.y - dot / 2, width: dot, height: dot))
    }
    ctx.setFillColor(color(0xC8C0B0)); ctx.fillPath()
}

// MARK: - Variants

/// An off-center cascade with one veil: a background window peeks out at the top left of the bright
/// active one, in the same proportions as the menu bar icon. The pair is centered in the tile.
func drawCascade(_ ctx: CGContext) {
    drawTileShadow(ctx)
    let w: CGFloat = 500, h: CGFloat = 375, step: CGFloat = 125, winR: CGFloat = 46
    let front = CGRect(x: center.x - (w + step) / 2 + step, y: center.y - (h + step) / 2, width: w, height: h)
    ctx.saveGState()
    ctx.addPath(tilePath); ctx.clip()
    drawGradient(ctx, T.wallpaper)
    drawBackWindow(ctx, front.offsetBy(dx: -step, dy: step), radius: winR, shadow: true)
    drawVeil(ctx, hole: roundedRect(front, winR))
    ctx.restoreGState()
    drawBrightWindow(ctx, front, radius: winR)
}

/// The active window centered; two background windows symmetric behind it, under one veil.
func drawVeilVariant(_ ctx: CGContext) {
    drawTileShadow(ctx)
    let winR: CGFloat = 40
    let front = rect(center: center, 500, 370)
    let off = CGPoint(x: 142, y: 153)
    ctx.saveGState()
    ctx.addPath(tilePath); ctx.clip()
    drawGradient(ctx, T.wallpaper)
    drawBackWindow(ctx, rect(center: CGPoint(x: center.x - off.x, y: center.y + off.y), 380, 290), radius: winR, shadow: false)
    drawBackWindow(ctx, rect(center: CGPoint(x: center.x + off.x, y: center.y - off.y), 380, 290), radius: winR, shadow: false)
    drawVeil(ctx, hole: roundedRect(front, winR))
    ctx.restoreGState()
    drawBrightWindow(ctx, front, radius: winR)
}

/// A rotary dimmer knob with a scale from dim to bright, and the bright window on its face.
func drawDimmer(_ ctx: CGContext) {
    drawPlainTile(ctx)

    // Scale: 9 dots on a 270° arc, from bottom left (dim, small) clockwise to bottom right (bright, large).
    let count = 9, arcR: CGFloat = 330
    let dim = color(T.scaleDim.0, T.scaleDim.1).components!, bright = color(T.scaleBright).components!
    for i in 0..<count {
        let t = CGFloat(i) / CGFloat(count - 1)
        let angle = (225 - 270 * t) * .pi / 180
        let c = CGPoint(x: center.x + cos(angle) * arcR, y: center.y + sin(angle) * arcR)
        let d = 16 + 18 * t
        ctx.saveGState()
        if t > 0.6 { ctx.setShadow(offset: .zero, blur: 30 * t, color: color(T.scaleBright, 0.7 * t)) }
        ctx.addEllipse(in: CGRect(x: c.x - d / 2, y: c.y - d / 2, width: d, height: d))
        ctx.setFillColor(CGColor(colorSpace: cs, components: (0..<4).map { dim[$0] + (bright[$0] - dim[$0]) * t })!)
        ctx.fillPath()
        ctx.restoreGState()
    }

    let knobR: CGFloat = 250
    let knob = CGRect(x: center.x - knobR, y: center.y - knobR, width: 2 * knobR, height: 2 * knobR)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 50, color: color(0x000000, T.windowShadow > 0 ? 0.25 : 0.6))
    ctx.addEllipse(in: knob); ctx.setFillColor(color(T.knob.1)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addEllipse(in: knob); ctx.clip()
    drawGradient(ctx, T.knob, in: knob)
    ctx.restoreGState()
    ctx.addEllipse(in: knob.insetBy(dx: 4, dy: 4)); ctx.setStrokeColor(color(0xFFFFFF, 0.1)); ctx.setLineWidth(4); ctx.strokePath()

    // Pointer at the bright end of the scale.
    let pAngle: CGFloat = -30 * .pi / 180
    let p = CGPoint(x: center.x + cos(pAngle) * (knobR - 40), y: center.y + sin(pAngle) * (knobR - 40))
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 20, color: color(T.scaleBright, 0.9))
    ctx.addEllipse(in: CGRect(x: p.x - 14, y: p.y - 14, width: 28, height: 28)); ctx.setFillColor(color(T.scaleBright)); ctx.fillPath()
    ctx.restoreGState()
    drawBrightWindow(ctx, rect(center: CGPoint(x: center.x, y: center.y + 20), 250, 185), radius: 26)
}

/// fullBleed: artwork for the Icon Composer format. The tile fills the whole canvas as a plain square
/// (macOS masks it to the icon shape), without our own rounded corners and shadow.
func render(_ variant: String, theme: String, fullBleed: Bool = false) -> CGImage {
    T = theme == "dark" ? darkTheme : lightTheme
    grainSeed = SeededRandom(state: 1)
    let ctx = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8, bytesPerRow: 0,
                        space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    tilePath = fullBleed ? CGPath(rect: tile, transform: nil) : roundedRect(tile, 185)
    if fullBleed {
        let k = S / tile.width
        ctx.scaleBy(x: k, y: k)
        ctx.translateBy(x: -tile.minX, y: -tile.minY)
    }
    switch variant {
    case "veil": drawVeilVariant(ctx)
    case "dimmer": drawDimmer(ctx)
    default: drawCascade(ctx)
    }
    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, px: Int, to url: URL) throws {
    let c = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                      space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.interpolationQuality = .high
    c.draw(image, in: CGRect(x: 0, y: 0, width: px, height: px))
    try NSBitmapImageRep(cgImage: c.makeImage()!).representation(using: .png, properties: [:])!.write(to: url)
}

// MARK: - Main

let fm = FileManager.default
let args = Array(CommandLine.arguments.dropFirst())
let root = URL(fileURLWithPath: args.first ?? fm.currentDirectoryPath)

if args.count >= 3, args[1] == "--preview" {
    let dir = URL(fileURLWithPath: args[2])
    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    for v in variants {
        for t in themes { try writePNG(render(v, theme: t), px: 512, to: dir.appendingPathComponent("\(v)-\(t).png")) }
    }
    print("Previews: \(dir.path)")
    exit(0)
}

let variant = args.count >= 2 ? args[1] : current.variant
let theme = args.count >= 3 ? args[2] : current.theme
guard variants.contains(variant), themes.contains(theme) else {
    print("Usage: make-icon.swift <root> [\(variants.joined(separator: "|"))] [\(themes.joined(separator: "|"))]")
    exit(1)
}
let resources = root.appendingPathComponent("Resources")

// Icon Composer icon, built the way the HIG asks for macOS 27: square, unmasked vector layers on a
// background fill, with no baked-in shadows, glows, blur or texture. The system adds Liquid Glass
// (specular highlights, refraction, translucency, shadows) and derives the clear and tinted looks.
//   back   the dimmed background window (lower opacity = the dim layer)
//   front  the bright active window, title bar dots cut out
// Both windows keep the cascade proportions of the menu bar icon: 4:3, offset by a quarter of the width.
let icon = resources.appendingPathComponent("AppIcon.icon")
try? fm.removeItem(at: icon)
try fm.createDirectory(at: icon.appendingPathComponent("Assets"), withIntermediateDirectories: true)

let winW = 584.0, winH = 438.0, step = 146.0, winR = 66.0
let groupX = 512 - (winW + step) / 2, groupY = 512 - (winH + step) / 2   // SVG: y grows downward
func svgRoundedRect(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ r: Double) -> String {
    "M\(x + r),\(y) H\(x + w - r) A\(r),\(r) 0 0 1 \(x + w),\(y + r) V\(y + h - r) A\(r),\(r) 0 0 1 \(x + w - r),\(y + h) "
        + "H\(x + r) A\(r),\(r) 0 0 1 \(x),\(y + h - r) V\(y + r) A\(r),\(r) 0 0 1 \(x + r),\(y) Z"
}
func svgCircle(_ cx: Double, _ cy: Double, _ r: Double) -> String {
    "M\(cx - r),\(cy) A\(r),\(r) 0 1 0 \(cx + r),\(cy) A\(r),\(r) 0 1 0 \(cx - r),\(cy) Z"
}
func svg(_ path: String, fill: String) -> String {
    """
    <svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
      <path fill="\(fill)" fill-rule="evenodd" d="\(path)"/>
    </svg>

    """
}
let back = svgRoundedRect(groupX, groupY, winW, winH, winR)
let fx = groupX + step, fy = groupY + step
let dotR = 19.0, dotY = fy + 62, dots = (0..<3).map { svgCircle(fx + 70 + Double($0) * 58, dotY, dotR) }.joined(separator: " ")
let front = svgRoundedRect(fx, fy, winW, winH, winR) + " " + dots
try svg(back, fill: "#C9CED8").write(to: icon.appendingPathComponent("Assets/back.svg"), atomically: true, encoding: .utf8)
try svg(front, fill: "#F7F3EA").write(to: icon.appendingPathComponent("Assets/front.svg"), atomically: true, encoding: .utf8)

func group(_ name: String, opacity: Double? = nil, translucency: Double) -> [String: Any] {
    var layer: [String: Any] = ["name": name, "image-name": "\(name.lowercased()).svg", "glass": true]
    if let opacity { layer["opacity"] = opacity }
    return [
        "name": name,
        "layers": [layer],
        "shadow": ["kind": "neutral", "opacity": 0.5],
        "translucency": ["enabled": true, "value": translucency],
    ]
}
let iconJSON: [String: Any] = [
    // Dark graphite: the shipped look is dark in every appearance.
    "fill": ["linear-gradient": ["srgb:0.21176,0.23137,0.27843,1.00000", "srgb:0.07059,0.07843,0.09412,1.00000"]],
    "groups": [group("Front", translucency: 0.15), group("Back", opacity: 0.55, translucency: 0.5)],
    "supported-platforms": ["squares": ["macOS"]],
]
try JSONSerialization.data(withJSONObject: iconJSON, options: [.prettyPrinted, .sortedKeys])
    .write(to: icon.appendingPathComponent("icon.json"))

// Fallback .icns for builds without Xcode: the system's own rendering of the layered icon when actool
// is available, otherwise the flat drawing of the variant.
let tmpOut = fm.temporaryDirectory.appendingPathComponent("AppIconCompiled")
try? fm.removeItem(at: tmpOut)
try fm.createDirectory(at: tmpOut, withIntermediateDirectories: true)
let actool = Process()
actool.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
actool.arguments = ["actool", "--compile", tmpOut.path, "--platform", "macosx", "--minimum-deployment-target", "26.0",
                    "--app-icon", "AppIcon", "--output-partial-info-plist", tmpOut.appendingPathComponent("p.plist").path, icon.path]
var env = ProcessInfo.processInfo.environment
if fm.fileExists(atPath: "/Applications/Xcode.app") { env["DEVELOPER_DIR"] = "/Applications/Xcode.app/Contents/Developer" }
actool.environment = env
actool.standardOutput = FileHandle.nullDevice
actool.standardError = FileHandle.nullDevice
try? actool.run(); actool.waitUntilExit()
let compiledIcns = tmpOut.appendingPathComponent("AppIcon.icns")
let icnsOut = resources.appendingPathComponent("AppIcon.icns")
if actool.terminationStatus == 0, fm.fileExists(atPath: compiledIcns.path) {
    try? fm.removeItem(at: icnsOut)
    try fm.copyItem(at: compiledIcns, to: icnsOut)
    print("Done (layered \(variant)): \(resources.path)")
    exit(0)
}
let master = render(variant, theme: theme)
let tmpset = fm.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? fm.removeItem(at: tmpset)
try fm.createDirectory(at: tmpset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try writePNG(master, px: base, to: tmpset.appendingPathComponent("icon_\(base)x\(base).png"))
    try writePNG(master, px: base * 2, to: tmpset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", tmpset.path, "-o", icnsOut.path]
try p.run(); p.waitUntilExit()
print(p.terminationStatus == 0 ? "Done (layered \(variant); flat .icns, no actool): \(resources.path)" : "iconutil failed")

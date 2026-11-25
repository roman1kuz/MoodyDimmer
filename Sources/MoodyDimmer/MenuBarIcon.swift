import AppKit

/// Menu bar icon styles, chosen in the menu. The same ideas as the app icon variants.
enum MenuBarIconStyle: Int, CaseIterable {
    /// A dimmed window behind the solid active one, offset diagonally (two windows read best at this size).
    case cascade = 4
    /// The bright active window alone, filling the icon (the veil around it is implied).
    case window = 1

    var title: String {
        switch self {
        case .cascade: L("Cascade")
        case .window: L("Window")
        }
    }
}

/// Menu bar icon color, named after the system appearance it suits.
/// `light` is a black icon, `dark` a white one; `auto` picks one from the current system appearance
/// (Light, Dark, or Auto by time of day). A template image isn't used for `auto`: macOS 26+ tints
/// templates for the wallpaper behind the menu bar, which made the icon washed out or the wrong color.
enum MenuBarIconTheme: Int, CaseIterable {
    case auto = 0
    case light = 1
    case dark = 2

    var title: String {
        switch self {
        case .auto: L("Match System")
        case .light: L("Light")
        case .dark: L("Dark")
        }
    }

    /// `light` or `dark` for the given appearance; pinned themes stay as they are.
    func resolved(for appearance: NSAppearance) -> MenuBarIconTheme {
        guard self == .auto else { return self }
        return appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light
    }
}

/// Menu bar icon images.
///
/// Sized like system SF Symbols in the menu bar (e.g. "macwindow"): 14 pt tall with about 12 pt
/// of visible content, 18 pt wide.
enum MenuBarIcon {
    static let size = NSSize(width: 18, height: 14)

    static func make(_ style: MenuBarIconStyle, theme: MenuBarIconTheme = .auto) -> NSImage {
        let shape = template(style)
        guard theme != .auto else { return shape }
        // Pinned color: fill the shape's alpha with black (light menu bar) or white (dark menu bar).
        let tint: NSColor = theme == .light ? .black : .white
        let image = NSImage(size: shape.size, flipped: false) { r in
            shape.draw(in: r)
            tint.set()
            r.fill(using: .sourceAtop)
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = shape.accessibilityDescription
        return image
    }

    private static func template(_ style: MenuBarIconStyle) -> NSImage {
        let image = NSImage(size: size, flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current else { return false }
            switch style {
            case .cascade: drawCascade(ctx)
            case .window: drawWindow(ctx)
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Moody Dimmer"
        return image
    }

    // MARK: - Styles

    private static func drawCascade(_ ctx: NSGraphicsContext) {
        // Two windows offset diagonally, filling the same 15×12 pt box as the window style.
        let step: CGFloat = 3, r: CGFloat = 2.5, gap: CGFloat = 0.75
        let front = NSRect(x: 1.5 + step, y: 1, width: 15 - step, height: 12 - step)
        let back = front.offsetBy(dx: -step, dy: step)
        fill(back, radius: r, alpha: 0.5)
        clear(front, radius: r, gap: gap, ctx: ctx)
        fill(front, radius: r, alpha: 1)
    }

    private static func drawWindow(_ ctx: NSGraphicsContext) {
        // A solid window filling the 15×12 pt content box, with three title bar dots cut out.
        let w = NSRect(x: 1.5, y: 1, width: 15, height: 12)
        fill(w, radius: 3, alpha: 1)
        ctx.compositingOperation = .clear
        for i in 0..<3 {
            let c = NSPoint(x: w.minX + 3 + CGFloat(i) * 2.4, y: w.maxY - 2.9)
            NSBezierPath(ovalIn: NSRect(x: c.x - 0.85, y: c.y - 0.85, width: 1.7, height: 1.7)).fill()
        }
        ctx.compositingOperation = .sourceOver
    }

    // MARK: - Helpers

    private static func fill(_ rect: NSRect, radius: CGFloat, alpha: CGFloat) {
        NSColor.black.withAlphaComponent(alpha).setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
    }

    /// Clears a transparent gap around a shape so overlapping parts read separately.
    private static func clear(_ rect: NSRect, radius: CGFloat, gap: CGFloat = 1, ctx: NSGraphicsContext) {
        ctx.compositingOperation = .clear
        NSBezierPath(roundedRect: rect.insetBy(dx: -gap, dy: -gap), xRadius: radius + gap, yRadius: radius + gap).fill()
        ctx.compositingOperation = .sourceOver
    }
}

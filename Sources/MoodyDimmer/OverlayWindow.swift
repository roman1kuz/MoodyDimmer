import AppKit

/// Transparent borderless window over the screen (optionally below the menu bar); clicks pass through.
final class OverlayWindow: NSWindow {
    let effectView: EffectView
    /// Whether the window should be visible once the animation ends.
    var wantVisible = false

    init(screen: NSScreen, coverMenuBar: Bool, hiddenFromCapture: Bool) {
        let frame = coverMenuBar ? screen.frame : Self.belowMenuBar(screen)
        effectView = EffectView(frame: NSRect(origin: .zero, size: frame.size))
        super.init(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: true)
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        level = .normal
        animationBehavior = .none
        isExcludedFromWindowsMenu = true
        // .fullScreenNone: WindowServer itself keeps the overlay out of full screen Spaces (video, players,
        // apps in full screen), even during the transition animation, so there is no flash.
        // With only .canJoinAllSpaces the window shows above the full screen window before any event arrives.
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        alphaValue = 0
        setHiddenFromCapture(hiddenFromCapture)
        contentView = effectView
        setFrame(frame, display: false)
    }

    /// The screen minus the menu bar. The menu bar is translucent in macOS 26+: dimmed wallpaper behind it
    /// would darken it while its icons stay dark for a light menu bar. visibleFrame's top is the menu bar's
    /// bottom (the Dock is at the bottom or sides, so only the top is taken from it); with an auto-hiding
    /// menu bar the two are equal and the whole screen is covered.
    static func belowMenuBar(_ screen: NSScreen) -> CGRect {
        var f = screen.frame
        f.size.height = screen.visibleFrame.maxY - f.minY
        return f
    }

    /// AppKit moves windows below the menu bar when they're shown or when displays change, which would shift the
    /// overlay (and every hole in its mask) down by the menu bar's height. It stays exactly where it's put.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }

    /// Left out of screenshots, screen recordings and screen sharing (Hide in Screenshots): WindowServer doesn't
    /// composite it into captured images, while it stays on screen.
    func setHiddenFromCapture(_ hidden: Bool) {
        sharingType = hidden ? .none : .readOnly
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

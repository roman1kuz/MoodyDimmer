import Foundation

/// What stays bright.
enum FocusMode: Int {
    /// Only the top window of the active app.
    case window = 0
    /// All visible windows of the active app (main window + dialogs/panels).
    case app = 1
}

/// Which setting changed: decides what needs recomputing.
enum SettingsChange {
    case enabled
    case focusMode
    case dragBehavior
    case menuBarCoverage
    case activeScreenOnly
    case tiling
    case pointerHighlight
    case quickToggle
    case haptics
    case strength     // sliders: applied instantly
    case animation
    case menuBarIcon
    case language
}

/// Settings in UserDefaults. Main thread only.
final class Settings {
    static let shared = Settings()

    var onChange: ((SettingsChange) -> Void)?

    private let d = UserDefaults.standard

    private enum Key {
        static let enabled = "enabled"
        static let focusMode = "focusMode"
        static let hideWhileDragging = "hideWhileDragging"
        static let dimMenuBar = "dimMenuBar"
        static let dimActiveScreenOnly = "dimActiveScreenOnly"
        static let keepTiledBright = "keepTiledBright"
        static let highlightUnderPointer = "highlightUnderPointer"
        static let shortcutKeyCode = "shortcutKeyCode"          // -1 = no shortcut
        static let shortcutModifiers = "shortcutModifiers"
        static let shortcutDisplay = "shortcutDisplay"
        static let shakeToToggle = "shakeToToggle"
        static let haptics = "haptics"
        static let legacyEffect = "effect"   // 0.x–1.0: dim / blur / both, before the sliders alone chose it
        static let dim = "dimStrength"
        static let blur = "blurStrength"
        static let grain = "grainStrength"
        static let animation = "animationMs"
        static let menuBarIcon = "menuBarIcon"
        static let menuBarIconTheme = "menuBarIconTheme"
        static let language = "language"
    }

    private init() {
        migrateEffectKind()  // before registering defaults: it checks which values were actually stored
        d.register(defaults: [
            Key.enabled: true,
            Key.focusMode: FocusMode.app.rawValue,
            Key.hideWhileDragging: true,
            Key.dimMenuBar: true,
            Key.dimActiveScreenOnly: false,
            Key.keepTiledBright: true,
            Key.highlightUnderPointer: false,
            Key.shortcutKeyCode: Int(Shortcut.default.keyCode),
            Key.shortcutModifiers: Int(Shortcut.default.modifiers),
            Key.shortcutDisplay: Shortcut.default.display,
            Key.shakeToToggle: true,
            Key.haptics: true,
            Key.dim: 0.5,
            Key.blur: 0.0,
            Key.grain: 0.0,
            Key.animation: 150.0,
            Key.menuBarIcon: MenuBarIconStyle.cascade.rawValue,
            Key.menuBarIconTheme: MenuBarIconTheme.auto.rawValue,
            Key.language: AppLanguage.auto.rawValue,
        ])
    }

    /// Up to 1.0 an effect kind picked dim, blur or both, and the strength of an unpicked effect was kept but
    /// unused. Now a slider at 0 means that effect is off, so zero the strength of whatever wasn't picked.
    private func migrateEffectKind() {
        guard d.object(forKey: Key.legacyEffect) != nil else { return }
        let kind = d.integer(forKey: Key.legacyEffect)   // 0 dim, 1 blur, 2 both
        // The old blur default (0.8) applied without being stored; the new default is 0.
        if kind != 0, d.object(forKey: Key.blur) == nil { d.set(0.8, forKey: Key.blur) }
        if kind == 0 { d.set(0.0, forKey: Key.blur) }
        if kind == 1 { d.set(0.0, forKey: Key.dim) }
        d.removeObject(forKey: Key.legacyEffect)
    }

    var enabled: Bool {
        get { d.bool(forKey: Key.enabled) }
        set { d.set(newValue, forKey: Key.enabled); onChange?(.enabled) }
    }

    var focusMode: FocusMode {
        get { FocusMode(rawValue: d.integer(forKey: Key.focusMode)) ?? .app }
        set { d.set(newValue.rawValue, forKey: Key.focusMode); onChange?(.focusMode) }
    }

    /// A drag has left the source app's windows: remove the effect until the mouse button is released.
    var hideWhileDragging: Bool {
        get { d.bool(forKey: Key.hideWhileDragging) }
        set { d.set(newValue, forKey: Key.hideWhileDragging); onChange?(.dragBehavior) }
    }

    /// Whether the effect also covers the menu bar. It's translucent in macOS 26+, so the effect behind it
    /// darkens it, while its icons may stay dark for a light menu bar; turning this off stops the effect below it.
    var dimMenuBar: Bool {
        get { d.bool(forKey: Key.dimMenuBar) }
        set { d.set(newValue, forKey: Key.dimMenuBar); onChange?(.menuBarCoverage) }
    }

    /// With several displays, only the one with the active window gets the effect; the others stay as they are.
    var dimActiveScreenOnly: Bool {
        get { d.bool(forKey: Key.dimActiveScreenOnly) }
        set { d.set(newValue, forKey: Key.dimActiveScreenOnly); onChange?(.activeScreenOnly) }
    }

    /// Windows laid out side by side with the active one (snapped to halves or quarters of the screen) stay bright
    /// with it.
    var keepTiledBright: Bool {
        get { d.bool(forKey: Key.keepTiledBright) }
        set { d.set(newValue, forKey: Key.keepTiledBright); onChange?(.tiling) }
    }

    /// A dimmed window the pointer rests on for a few seconds is shown bright, without becoming active.
    var highlightUnderPointer: Bool {
        get { d.bool(forKey: Key.highlightUnderPointer) }
        set { d.set(newValue, forKey: Key.highlightUnderPointer); onChange?(.pointerHighlight) }
    }

    /// Global shortcut that turns the effect on and off; nil = none.
    var shortcut: Shortcut? {
        get {
            let code = d.integer(forKey: Key.shortcutKeyCode)
            guard code >= 0, let display = d.string(forKey: Key.shortcutDisplay) else { return nil }
            return Shortcut(keyCode: UInt32(code), modifiers: UInt32(d.integer(forKey: Key.shortcutModifiers)), display: display)
        }
        set {
            d.set(newValue.map { Int($0.keyCode) } ?? -1, forKey: Key.shortcutKeyCode)
            d.set(Int(newValue?.modifiers ?? 0), forKey: Key.shortcutModifiers)
            d.set(newValue?.display ?? "", forKey: Key.shortcutDisplay)
            onChange?(.quickToggle)
        }
    }

    /// Shake the pointer left and right to turn the effect on and off.
    var shakeToToggle: Bool {
        get { d.bool(forKey: Key.shakeToToggle) }
        set { d.set(newValue, forKey: Key.shakeToToggle); onChange?(.quickToggle) }
    }

    /// Light trackpad taps while dragging the sliders and when shaking the pointer toggles the effect.
    var haptics: Bool {
        get { d.bool(forKey: Key.haptics) }
        set { d.set(newValue, forKey: Key.haptics); onChange?(.haptics) }
    }

    /// 0…1, 0 = off
    var dimStrength: Double {
        get { d.double(forKey: Key.dim) }
        set { d.set(newValue, forKey: Key.dim); onChange?(.strength) }
    }

    /// 0…1, 0 = off
    var blurStrength: Double {
        get { d.double(forKey: Key.blur) }
        set { d.set(newValue, forKey: Key.blur); onChange?(.strength) }
    }

    /// 0…1, 0 = off
    var grainStrength: Double {
        get { d.double(forKey: Key.grain) }
        set { d.set(newValue, forKey: Key.grain); onChange?(.strength) }
    }

    /// 0…400 ms, 0 = instant
    var animationMs: Double {
        get { d.double(forKey: Key.animation) }
        set { d.set(newValue, forKey: Key.animation); onChange?(.animation) }
    }

    var menuBarIcon: MenuBarIconStyle {
        get { MenuBarIconStyle(rawValue: d.integer(forKey: Key.menuBarIcon)) ?? .cascade }
        set { d.set(newValue.rawValue, forKey: Key.menuBarIcon); onChange?(.menuBarIcon) }
    }

    var menuBarIconTheme: MenuBarIconTheme {
        get { MenuBarIconTheme(rawValue: d.integer(forKey: Key.menuBarIconTheme)) ?? .auto }
        set { d.set(newValue.rawValue, forKey: Key.menuBarIconTheme); onChange?(.menuBarIcon) }
    }

    var language: AppLanguage {
        get { AppLanguage(rawValue: d.integer(forKey: Key.language)) ?? .auto }
        set { d.set(newValue.rawValue, forKey: Key.language); onChange?(.language) }
    }

    var animationDuration: TimeInterval { max(0, animationMs) / 1000 }
}

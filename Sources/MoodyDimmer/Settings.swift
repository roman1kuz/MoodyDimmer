import Foundation

/// What stays bright.
enum FocusMode: Int {
    /// Only the top window of the active app.
    case window = 0
    /// All visible windows of the active app (main window + dialogs/panels).
    case app = 1
}

/// Background effect kind.
enum EffectKind: Int {
    case dim = 0
    case blur = 1
    case both = 2

    var hasDim: Bool { self != .blur }
    var hasBlur: Bool { self != .dim }
}

/// Which setting changed: decides what needs recomputing.
enum SettingsChange {
    case enabled
    case focusMode
    case dragBehavior
    case menuBarCoverage
    case quickToggle
    case effect       // discrete change: animated
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
        static let shortcutKeyCode = "shortcutKeyCode"          // -1 = no shortcut
        static let shortcutModifiers = "shortcutModifiers"
        static let shortcutDisplay = "shortcutDisplay"
        static let shakeToToggle = "shakeToToggle"
        static let effect = "effect"
        static let dim = "dimStrength"
        static let blur = "blurStrength"
        static let grain = "grainStrength"
        static let animation = "animationMs"
        static let menuBarIcon = "menuBarIcon"
        static let menuBarIconTheme = "menuBarIconTheme"
        static let language = "language"
    }

    private init() {
        d.register(defaults: [
            Key.enabled: true,
            Key.focusMode: FocusMode.app.rawValue,
            Key.hideWhileDragging: true,
            Key.dimMenuBar: true,
            Key.shortcutKeyCode: Int(Shortcut.default.keyCode),
            Key.shortcutModifiers: Int(Shortcut.default.modifiers),
            Key.shortcutDisplay: Shortcut.default.display,
            Key.shakeToToggle: true,
            Key.effect: EffectKind.dim.rawValue,
            Key.dim: 0.5,
            Key.blur: 0.8,
            Key.grain: 0.0,
            Key.animation: 150.0,
            Key.menuBarIcon: MenuBarIconStyle.cascade.rawValue,
            Key.menuBarIconTheme: MenuBarIconTheme.auto.rawValue,
            Key.language: AppLanguage.auto.rawValue,
        ])
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

    var effect: EffectKind {
        get { EffectKind(rawValue: d.integer(forKey: Key.effect)) ?? .dim }
        set { d.set(newValue.rawValue, forKey: Key.effect); onChange?(.effect) }
    }

    /// 0…1
    var dimStrength: Double {
        get { d.double(forKey: Key.dim) }
        set { d.set(newValue, forKey: Key.dim); onChange?(.strength) }
    }

    /// 0…1
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

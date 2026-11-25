import AppKit
import ServiceManagement

/// Control Center style slider, like the system Sound and Display menus: a thick capsule track with no knob,
/// an accent-colored fill and an SF Symbol inside it on the left. Drawn by hand: a stock NSSlider in a menu renders as
/// inactive (the menu window never becomes key), and it has no Control Center look anyway.
private final class CapsuleSlider: NSView {
    var minValue: Double = 0, maxValue: Double = 1
    var doubleValue: Double = 0 { didSet { needsDisplay = true; updateAccessibility() } }
    var onChange: ((Double) -> Void)?
    /// The symbol rides at the end of the fill, like a knob, instead of staying on the left.
    static var symbolFollowsValue = true
    private let symbol: NSImage

    init(symbol name: String, label: String) {
        symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)!
            .withSymbolConfiguration(.init(pointSize: 11, weight: .semibold))!
        super.init(frame: NSRect(x: 0, y: 0, width: 100, height: 22))
        setAccessibilityElement(true)
        setAccessibilityRole(.slider)
        setAccessibilityLabel(label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private var fraction: CGFloat {
        maxValue > minValue ? CGFloat((doubleValue - minValue) / (maxValue - minValue)) : 0
    }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds, radius = r.height / 2
        // Accent fill with a white symbol, like the system Sound menu; follows the user's accent color.
        let fillColor = NSColor.controlAccentColor
        let symbolColor = NSColor.white
        let track = NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius)
        NSColor.labelColor.withAlphaComponent(0.12).setFill()
        track.fill()

        // The fill is at least a full circle, so the symbol always sits on it, like in Control Center;
        // its end circle moves linearly from the left end to the right end.
        let fillWidth = r.height + (r.width - r.height) * fraction
        NSGraphicsContext.saveGraphicsState()
        track.addClip()
        fillColor.setFill()
        NSBezierPath(roundedRect: NSRect(x: r.minX, y: r.minY, width: fillWidth, height: r.height),
                     xRadius: radius, yRadius: radius).fill()
        NSGraphicsContext.restoreGraphicsState()

        let size = symbol.size
        let tinted = NSImage(size: size, flipped: false) { rect in
            self.symbol.draw(in: rect)
            symbolColor.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        // Centered in the last circle of the fill (or the first one, when the symbol stays put).
        let circleX = Self.symbolFollowsValue ? r.minX + fillWidth - r.height : r.minX
        tinted.draw(in: NSRect(x: circleX + (r.height - size.width) / 2, y: r.midY - size.height / 2,
                               width: size.width, height: size.height))
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    // MARK: Input

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        set(fromX: convert(event.locationInWindow, from: nil).x)
        // Track the drag here: inside a menu the events come through the menu's tracking loop.
        while let e = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            set(fromX: convert(e.locationInWindow, from: nil).x)
            if e.type == .leftMouseUp { break }
        }
    }

    override func scrollWheel(with event: NSEvent) {
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaX - event.scrollingDeltaY
                                                    : (event.deltaX - event.deltaY) * 8
        setFraction(fraction + delta / max(bounds.width - bounds.height, 1))
    }

    private func set(fromX x: CGFloat) {
        // Inverse of the fill geometry, so the end circle (and the symbol in it) stays under the pointer.
        let h = bounds.height
        setFraction((x - h / 2) / max(bounds.width - h, 1))
    }

    private func setFraction(_ f: CGFloat) {
        let v = minValue + Double(min(max(f, 0), 1)) * (maxValue - minValue)
        guard v != doubleValue else { return }
        doubleValue = v
        onChange?(v)
    }

    // MARK: Accessibility

    private func updateAccessibility() {
        setAccessibilityValue(NSNumber(value: doubleValue))
        setAccessibilityMinValue(NSNumber(value: minValue))
        setAccessibilityMaxValue(NSNumber(value: maxValue))
    }

    override func accessibilityPerformIncrement() -> Bool { setFraction(fraction + 0.1); return true }
    override func accessibilityPerformDecrement() -> Bool { setFraction(fraction - 0.1); return true }
}

/// Menu row: title and value on one line, the capsule slider below.
private final class SliderRow: NSView {
    let slider: CapsuleSlider
    private let title: NSTextField
    private let value: NSTextField
    private let format: (Double) -> String
    var onChange: ((Double) -> Void)?

    /// Narrower than the text items: the longest item sets the menu width and the row stretches.
    private static let minWidth: CGFloat = 200
    static let leading: CGFloat = 30   // where menu item text starts
    static let trailing: CGFloat = 16  // right edge of the separators

    init(title text: String, symbol: String, range: ClosedRange<Double>, format: @escaping (Double) -> String) {
        self.format = format
        title = NSTextField(labelWithString: text)
        value = NSTextField(labelWithString: "")
        slider = CapsuleSlider(symbol: symbol, label: text)
        slider.minValue = range.lowerBound
        slider.maxValue = range.upperBound
        slider.doubleValue = range.lowerBound
        // Minimal width: NSMenu stretches the view to the menu width (autoresizingMask .width).
        super.init(frame: NSRect(x: 0, y: 0, width: Self.minWidth, height: 50))
        autoresizingMask = [.width]

        title.font = .menuFont(ofSize: 0)
        value.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        value.textColor = .secondaryLabelColor
        value.alignment = .right
        slider.onChange = { [weak self] v in
            guard let self else { return }
            self.value.stringValue = self.format(v)
            self.onChange?(v)
        }

        // Insets match the text of regular menu items (checkmark column on the left, separators on the right).
        let w = Self.minWidth, lead = Self.leading, trail = Self.trailing
        title.frame = NSRect(x: lead - 2, y: 29, width: w - lead - trail - 80, height: 17)
        title.autoresizingMask = [.width]
        value.frame = NSRect(x: w - trail - 80, y: 29, width: 80, height: 17)
        value.autoresizingMask = [.minXMargin]
        slider.frame = NSRect(x: lead - 2, y: 4, width: w - lead - trail + 2, height: 22)
        slider.autoresizingMask = [.width]
        [title, value, slider].forEach(addSubview)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func set(_ v: Double) {
        if abs(slider.doubleValue - v) > 0.0001 { slider.doubleValue = v }
        value.stringValue = format(v)
    }
}

/// On/off switch drawn by hand. A stock NSSwitch in a menu renders as inactive (grey even when on),
/// because the menu window never becomes key; this one always shows the real state, like Control Center.
/// A click slides the knob and blends the track color with a short ease-in-out, with no bounce or overshoot.
/// The animation is driven by a timer and redraws: menu windows don't run Core Animation transitions.
final class MenuSwitch: NSView {
    private(set) var isOn = false
    var onToggle: ((Bool) -> Void)?

    /// 0 = off, 1 = on; animated between the two.
    private var progress: CGFloat = 0
    private var animation: Timer?
    private static let duration: TimeInterval = 0.2

    init(label: String) {
        super.init(frame: NSRect(x: 0, y: 0, width: 32, height: 18))
        setAccessibilityElement(true)
        setAccessibilityRole(.checkBox)
        setAccessibilitySubrole(.switch)
        setAccessibilityLabel(label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// Sets the state without animation (e.g. when the menu opens).
    func setOn(_ on: Bool) {
        guard on != isOn else { return }
        isOn = on
        animation?.invalidate()
        progress = on ? 1 : 0
        needsDisplay = true
        setAccessibilityValue(on)
    }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds, radius = r.height / 2
        // Track: blend from the off color to the accent color.
        let off = NSColor.labelColor.withAlphaComponent(0.18), on = NSColor.controlAccentColor
        (off.blended(withFraction: progress, of: on) ?? on).setFill()
        NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius).fill()

        let inset: CGFloat = 1.5, d = r.height - 2 * inset
        let x = r.minX + inset + (r.width - 2 * inset - d) * progress
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
        shadow.shadowBlurRadius = 1.5
        shadow.shadowOffset = NSSize(width: 0, height: -0.5)
        shadow.set()
        NSColor.white.setFill()
        NSBezierPath(ovalIn: NSRect(x: x, y: r.minY + inset, width: d, height: d)).fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { toggle() }
    override func accessibilityPerformPress() -> Bool { toggle(); return true }

    private func toggle() {
        isOn.toggle()
        setAccessibilityValue(isOn)
        animate(to: isOn ? 1 : 0)
        onToggle?(isOn)
    }

    private func animate(to target: CGFloat) {
        animation?.invalidate()
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            progress = target
            needsDisplay = true
            return
        }
        let from = progress, start = CACurrentMediaTime()
        // Shorter when reversing mid-way, so the speed stays the same.
        let duration = Self.duration * Double(abs(target - from))
        let timer = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            let f = min(1, CGFloat((CACurrentMediaTime() - start) / max(duration, 0.001)))
            let eased = f < 0.5 ? 2 * f * f : 1 - pow(-2 * f + 2, 2) / 2  // ease-in-out, no overshoot
            self.progress = from + (target - from) * eased
            self.needsDisplay = true
            if f >= 1 { t.invalidate() }
        }
        // Common modes: the menu tracks events in its own run loop mode.
        RunLoop.main.add(timer, forMode: .common)
        animation = timer
    }
}

/// First menu row, like the system Wi-Fi and Bluetooth menus: the app name in bold and an on/off switch.
private final class HeaderRow: NSView {
    let toggle = MenuSwitch(label: L("Enabled"))

    init(title text: String) {
        super.init(frame: NSRect(x: 0, y: 0, width: 200, height: 30))
        autoresizingMask = [.width]
        let title = NSTextField(labelWithString: text)
        title.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        // Same text column and right edge as the rest of the menu.
        title.frame = NSRect(x: SliderRow.leading - 2, y: 6, width: 150, height: 18)
        toggle.frame.origin = NSPoint(x: bounds.width - SliderRow.trailing - toggle.frame.width,
                                      y: ((bounds.height - toggle.frame.height) / 2).rounded())
        toggle.autoresizingMask = [.minXMargin]
        [title, toggle].forEach(addSubview)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}

/// Section title in small caps with letter spacing, like sidebar section titles in macOS. The system section
/// header renders almost like a disabled item in a menu bar menu; the letterforms set this one apart from the
/// items, so it can stay readable without competing with them.
private final class SectionHeader: NSView {
    private let label = NSTextField(labelWithString: "")
    private let text: String

    init(title text: String) {
        self.text = text.uppercased(with: Localization.locale)
        super.init(frame: NSRect(x: 0, y: 0, width: 120, height: 22))
        autoresizingMask = [.width]
        updateText()
        label.frame = NSRect(x: SliderRow.leading - 2, y: 3, width: 120 - SliderRow.leading, height: 16)
        label.autoresizingMask = [.width]
        addSubview(label)
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // An attributed string keeps the color resolved for the appearance at the time it was set,
    // so it's rebuilt when Light/Dark changes.
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateText()
    }

    private func updateText() {
        label.attributedStringValue = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 10, weight: .semibold), .kern: 0.6,
            .foregroundColor: NSColor.labelColor.withAlphaComponent(0.5),
        ])
    }
}

final class StatusMenu: NSObject, NSMenuDelegate {
    var onMenuWillOpen: (() -> Void)?
    var onChangeShortcut: (() -> Void)?

    private let settings: Settings
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()

    // Items are (re)created in buildMenu(), so a language change just rebuilds the menu.
    private var headerRow: HeaderRow!
    private var modeWindowItem: NSMenuItem!
    private var modeAppItem: NSMenuItem!
    private var hideDragItem: NSMenuItem!
    private var menuBarItem: NSMenuItem!
    private var effectDimItem: NSMenuItem!
    private var effectBlurItem: NSMenuItem!
    private var effectBothItem: NSMenuItem!
    private var dimRowItem: NSMenuItem!
    private var blurRowItem: NSMenuItem!
    private var loginItem: NSMenuItem!
    private var shortcutItem: NSMenuItem!
    private var shakeItem: NSMenuItem!
    private var permissionItem: NSMenuItem!
    private var iconStyleItems: [NSMenuItem] = []
    private var iconThemeItems: [NSMenuItem] = []
    private var languageItems: [NSMenuItem] = []

    private var dimRow: SliderRow!
    private var blurRow: SliderRow!
    private var grainRow: SliderRow!
    private var animRow: SliderRow!

    init(settings: Settings) {
        self.settings = settings
        super.init()
        menu.delegate = self
        statusItem.menu = menu
        buildMenu()
        // Light/Dark can change at any time (including the Auto schedule); "Match System" follows it.
        appearanceObservation = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            DispatchQueue.main.async { self?.sync() }
        }
    }

    private var appearanceObservation: NSKeyValueObservation?

    /// Creates every item with titles in the current language.
    func buildMenu() {
        menu.removeAllItems()
        func item(_ title: String, _ action: Selector?, tag: Int = 0) -> NSMenuItem {
            let i = NSMenuItem(title: L(title), action: action, keyEquivalent: "")
            i.tag = tag
            if action != nil { i.target = self }
            return i
        }

        headerRow = HeaderRow(title: "Moody Dimmer")
        headerRow.toggle.onToggle = { [weak self] on in self?.settings.enabled = on }
        let headerItem = NSMenuItem()
        headerItem.view = headerRow
        permissionItem = item("Grant Accessibility Access…", #selector(openPermissions))
        modeWindowItem = item("Active Window Only", #selector(setModeWindow))
        modeAppItem = item("All App Windows", #selector(setModeApp))
        hideDragItem = item("Hide While Dragging", #selector(toggleHideDrag))
        menuBarItem = item("Dim Menu Bar", #selector(toggleMenuBar))
        effectDimItem = item("Dim", #selector(setEffect(_:)), tag: EffectKind.dim.rawValue)
        effectBlurItem = item("Blur", #selector(setEffect(_:)), tag: EffectKind.blur.rawValue)
        effectBothItem = item("Dim + Blur", #selector(setEffect(_:)), tag: EffectKind.both.rawValue)
        loginItem = item("Launch at Login", #selector(toggleLogin))
        shortcutItem = item("Keyboard Shortcut", #selector(changeShortcut))
        shakeItem = item("Shake Pointer to Toggle", #selector(toggleShake))

        let iconItem = item("Menu Bar Icon", nil)
        let iconMenu = NSMenu()
        iconStyleItems = MenuBarIconStyle.allCases.map { style in
            let i = NSMenuItem(title: style.title, action: #selector(setMenuBarIcon(_:)), keyEquivalent: "")
            i.image = MenuBarIcon.make(style)
            i.tag = style.rawValue
            i.target = self
            return i
        }
        iconThemeItems = MenuBarIconTheme.allCases.map { theme in
            let i = NSMenuItem(title: theme.title, action: #selector(setMenuBarIconTheme(_:)), keyEquivalent: "")
            i.tag = theme.rawValue
            i.target = self
            return i
        }
        (iconStyleItems + [.separator(), header(L("Theme"))] + iconThemeItems).forEach(iconMenu.addItem)
        iconItem.submenu = iconMenu

        let languageItem = item("Language", nil)
        let languageMenu = NSMenu()
        languageItems = AppLanguage.allCases.map { lang in
            let i = NSMenuItem(title: lang.title, action: #selector(setLanguage(_:)), keyEquivalent: "")
            i.tag = lang.rawValue
            i.target = self
            return i
        }
        languageItems.forEach(languageMenu.addItem)
        languageMenu.insertItem(.separator(), at: 1)
        languageItem.submenu = languageMenu

        dimRow = SliderRow(title: L("Dim"), symbol: "moon.fill", range: 0...1) { "\(Int(($0 * 100).rounded())) %" }
        blurRow = SliderRow(title: L("Blur"), symbol: "drop.fill", range: 0...1) { "\(Int(($0 * 100).rounded())) %" }
        grainRow = SliderRow(title: L("Grain"), symbol: "circle.grid.3x3.fill", range: 0...1) { $0 < 0.005 ? L("off") : "\(Int(($0 * 100).rounded())) %" }
        animRow = SliderRow(title: L("Animation"), symbol: "timer", range: 0...400) { $0 < 5 ? L("instant") : String(format: L("%d ms"), Int($0.rounded())) }
        dimRow.onChange = { [weak self] in self?.settings.dimStrength = $0 }
        blurRow.onChange = { [weak self] in self?.settings.blurStrength = $0 }
        grainRow.onChange = { [weak self] in self?.settings.grainStrength = $0 < 0.005 ? 0 : $0 }
        animRow.onChange = { [weak self] in self?.settings.animationMs = $0 < 5 ? 0 : $0.rounded() }
        dimRowItem = NSMenuItem(); dimRowItem.view = dimRow
        blurRowItem = NSMenuItem(); blurRowItem.view = blurRow
        let grainItem = NSMenuItem(); grainItem.view = grainRow
        let animItem = NSMenuItem(); animItem.view = animRow

        let items: [NSMenuItem] = [
            headerItem,
            permissionItem,
            .separator(),
            header(L("Keep Bright")),
            modeWindowItem, modeAppItem,
            .separator(),
            header(L("Behavior")),
            hideDragItem,
            menuBarItem,
            .separator(),
            header(L("Effect")),
            effectDimItem, effectBlurItem, effectBothItem,
            .separator(),
            dimRowItem, blurRowItem, grainItem, animItem,
            .separator(),
            header(L("Quick Toggle")),
            shortcutItem,
            shakeItem,
            .separator(),
            iconItem,
            languageItem,
            loginItem,
            // No ⌘Q: a shortcut reserves a column on the right for every item and widens the menu.
            NSMenuItem(title: L("Quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: ""),
        ]
        items.forEach(menu.addItem)
        permissionItem.isHidden = Permissions.isTrusted
        sync()
    }

    private func header(_ title: String) -> NSMenuItem {
        let item = NSMenuItem()
        item.view = SectionHeader(title: title)
        return item
    }

    /// Syncs menu item state from the settings.
    func sync() {
        headerRow.toggle.setOn(settings.enabled)
        let style = settings.menuBarIcon, theme = settings.menuBarIconTheme
        let color = theme.resolved(for: NSApp.effectiveAppearance)
        if shownIcon?.style != style || shownIcon?.theme != color {
            statusItem.button?.image = MenuBarIcon.make(style, theme: color)
            shownIcon = (style, color)
        }
        for item in iconStyleItems { item.state = item.tag == style.rawValue ? .on : .off }
        for item in iconThemeItems { item.state = item.tag == theme.rawValue ? .on : .off }
        let language = settings.language
        for item in languageItems { item.state = item.tag == language.rawValue ? .on : .off }
        statusItem.button?.appearsDisabled = !settings.enabled  // dimmed icon when the effect is off
        modeWindowItem.state = settings.focusMode == .window ? .on : .off
        modeAppItem.state = settings.focusMode == .app ? .on : .off
        hideDragItem.state = settings.hideWhileDragging ? .on : .off
        menuBarItem.state = settings.dimMenuBar ? .on : .off
        shortcutItem.title = "\(L("Keyboard Shortcut")): \(settings.shortcut?.display ?? L("None"))…"
        shakeItem.state = settings.shakeToToggle ? .on : .off
        let effect = settings.effect
        effectDimItem.state = effect == .dim ? .on : .off
        effectBlurItem.state = effect == .blur ? .on : .off
        effectBothItem.state = effect == .both ? .on : .off
        dimRowItem.isHidden = !effect.hasDim
        blurRowItem.isHidden = !effect.hasBlur
        dimRow.set(settings.dimStrength)
        blurRow.set(settings.blurStrength)
        grainRow.set(settings.grainStrength)
        animRow.set(settings.animationMs)
    }

    private var shownIcon: (style: MenuBarIconStyle, theme: MenuBarIconTheme)?

    func menuWillOpen(_ menu: NSMenu) {
        permissionItem.isHidden = Permissions.isTrusted
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        sync()
        onMenuWillOpen?()
    }

    // MARK: - Actions

    @objc private func setModeWindow() { settings.focusMode = .window }
    @objc private func setModeApp() { settings.focusMode = .app }
    @objc private func toggleHideDrag() { settings.hideWhileDragging.toggle() }
    @objc private func toggleMenuBar() { settings.dimMenuBar.toggle() }
    @objc private func toggleShake() { settings.shakeToToggle.toggle() }
    @objc private func changeShortcut() { onChangeShortcut?() }
    @objc private func setEffect(_ sender: NSMenuItem) {
        settings.effect = EffectKind(rawValue: sender.tag) ?? .dim
    }
    @objc private func setMenuBarIcon(_ sender: NSMenuItem) {
        settings.menuBarIcon = MenuBarIconStyle(rawValue: sender.tag) ?? .cascade
    }
    @objc private func setMenuBarIconTheme(_ sender: NSMenuItem) {
        settings.menuBarIconTheme = MenuBarIconTheme(rawValue: sender.tag) ?? .auto
    }
    @objc private func setLanguage(_ sender: NSMenuItem) {
        settings.language = AppLanguage(rawValue: sender.tag) ?? .auto
    }
    @objc private func openPermissions() { Permissions.openSettings() }

    @objc private func toggleLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled { try service.unregister() } else { try service.register() }
        } catch {
            let alert = NSAlert()
            alert.messageText = L("Couldn't change launch at login")
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }
}

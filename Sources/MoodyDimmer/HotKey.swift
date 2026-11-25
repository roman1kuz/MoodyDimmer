import AppKit
import Carbon.HIToolbox

/// A keyboard shortcut: virtual key code plus Carbon modifier flags, and how to show it.
struct Shortcut: Equatable {
    var keyCode: UInt32
    var modifiers: UInt32      // Carbon flags: cmdKey, optionKey, controlKey, shiftKey
    var display: String        // e.g. "⌃⌥⌘D"

    /// ⌃⌥⌘D: free in macOS and common apps (⌥⌘D, for example, hides the Dock).
    static let `default` = Shortcut(keyCode: UInt32(kVK_ANSI_D),
                                    modifiers: UInt32(controlKey | optionKey | cmdKey), display: "⌃⌥⌘D")

    /// Builds a shortcut from a key press; nil when it has no ⌘, ⌃ or ⌥ (a bare key would fire while typing).
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard !flags.intersection([.command, .control, .option]).isEmpty else { return nil }
        var carbon: UInt32 = 0, symbols = ""
        if flags.contains(.control) { carbon |= UInt32(controlKey); symbols += "⌃" }
        if flags.contains(.option) { carbon |= UInt32(optionKey); symbols += "⌥" }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey); symbols += "⇧" }
        if flags.contains(.command) { carbon |= UInt32(cmdKey); symbols += "⌘" }
        let key = Shortcut.keyName(event)
        guard !key.isEmpty else { return nil }
        self.init(keyCode: UInt32(event.keyCode), modifiers: carbon, display: symbols + key)
    }

    init(keyCode: UInt32, modifiers: UInt32, display: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.display = display
    }

    private static func keyName(_ event: NSEvent) -> String {
        switch Int(event.keyCode) {
        case kVK_Space: return "Space"
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        default: break
        }
        let fKeys: [Int: String] = [kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
                                    kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12"]
        if let f = fKeys[Int(event.keyCode)] { return f }
        return latinName(keyCode: event.keyCode) ?? (event.charactersIgnoringModifiers ?? "").uppercased()
    }

    /// The key's label in an ASCII-capable layout, so ⌃⌥⌘D shows as "D" even with a Cyrillic layout active.
    private static func latinName(keyCode: UInt16) -> String? {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
        var deadKeys: UInt32 = 0, length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        let status = data.withUnsafeBytes { buf -> OSStatus in
            UCKeyTranslate(buf.bindMemory(to: UCKeyboardLayout.self).baseAddress, keyCode, UInt16(kUCKeyActionDisplay),
                           0, UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, 4, &length, &chars)
        }
        guard status == noErr, length > 0 else { return nil }
        let s = String(utf16CodeUnits: chars, count: length).uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : s
    }
}

/// System-wide hotkey through the Carbon hotkey API: works in any app and needs no permission.
final class HotKey {
    var onPress: (() -> Void)?
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?

    func register(_ shortcut: Shortcut?) {
        unregister()
        guard let shortcut else { return }
        if handler == nil {
            var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let me = Unmanaged.passUnretained(self).toOpaque()
            InstallEventHandler(GetApplicationEventTarget(), { _, _, data in
                guard let data else { return noErr }
                Unmanaged<HotKey>.fromOpaque(data).takeUnretainedValue().onPress?()
                return noErr
            }, 1, &type, me, &handler)
        }
        let id = EventHotKeyID(signature: OSType(0x5044_494D), id: 1)  // "PDIM"
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, id, GetApplicationEventTarget(), 0, &ref)
        if status != noErr { log.error("couldn't register hotkey \(shortcut.display, privacy: .public): \(status)") }
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
    }
}

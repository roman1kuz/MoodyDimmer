import AppKit

/// Type of the current Space on each display. There is no public API, so we use SkyLight functions
/// that window managers (yabai, Amethyst, Hammerspoon) have relied on for years. They are loaded via dlsym:
/// if a future macOS drops them, the app won't crash and falls back to the AXFullScreen check.
enum Spaces {
    private typealias MainConnection = @convention(c) () -> Int32
    private typealias CopyDisplaySpaces = @convention(c) (Int32) -> Unmanaged<CFArray>?

    private static let handle = dlopen(nil, RTLD_NOW)
    private static let mainConnection: MainConnection? = load("CGSMainConnectionID")
    private static let copyDisplaySpaces: CopyDisplaySpaces? = load("CGSCopyManagedDisplaySpaces")

    private static func load<T>(_ name: String) -> T? {
        guard let sym = dlsym(handle, name) else { return nil }
        return unsafeBitCast(sym, to: T.self)
    }

    static var available: Bool { mainConnection != nil && copyDisplaySpaces != nil }

    /// Space type "full screen window".
    private static let fullscreenType = 4

    /// Frames (Cocoa) of the screens currently showing a full screen Space.
    static func fullscreenScreens() -> [CGRect] {
        guard let mainConnection, let copyDisplaySpaces,
              let displays = copyDisplaySpaces(mainConnection())?.takeRetainedValue() as? [[String: Any]]
        else { return [] }
        var result: [CGRect] = []
        for display in displays {
            guard let current = display["Current Space"] as? [String: Any],
                  (current["type"] as? Int) == fullscreenType else { continue }
            let id = display["Display Identifier"] as? String ?? ""
            // "Main" when "Displays have separate Spaces" is off: one Space shared by all screens.
            let matched = NSScreen.screens.filter { id == "Main" || uuid(of: $0) == id }
            result += matched.map(\.frame)
        }
        return result
    }

    private static func uuid(of screen: NSScreen) -> String? {
        guard let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let uuid = CGDisplayCreateUUIDFromDisplayID(num.uint32Value)?.takeRetainedValue()
        else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }
}

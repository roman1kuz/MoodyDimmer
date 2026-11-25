import CoreGraphics
import Foundation

/// WindowServer's own window events (SkyLight, private): `shown` when a window becomes visible, `destroyed` when
/// it's destroyed (a window that's only ordered out or minimized posts nothing). The payload carries the window
/// number. Registered once for the app's lifetime and shared by everyone who needs it; handlers run on the main thread.
enum WindowEvents {
    static let shown: UInt32 = 1325
    static let destroyed: UInt32 = 1326

    typealias Handler = (_ type: UInt32, _ window: CGWindowID) -> Void
    private static var handlers: [Handler] = []
    private static var registered: Bool?

    /// Adds a handler; false when SkyLight's notify API is unavailable (the handler is then never called).
    @discardableResult
    static func subscribe(_ handler: @escaping Handler) -> Bool {
        if registered == nil { registered = register() }
        guard registered == true else { return false }
        handlers.append(handler)
        return true
    }

    private typealias NotifyProc = @convention(c) (UInt32, UnsafeMutableRawPointer?, Int, UnsafeMutableRawPointer?) -> Void
    private typealias RegisterNotifyProc = @convention(c) (NotifyProc, UInt32, UnsafeMutableRawPointer?) -> Int32

    private static func register() -> Bool {
        guard let h = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW),
              let sym = dlsym(h, "SLSRegisterNotifyProc") else { return false }
        let register = unsafeBitCast(sym, to: RegisterNotifyProc.self)
        let proc: NotifyProc = { type, data, length, _ in
            // Payload: [UInt32 flags, UInt32 0, UInt32 window number].
            guard let data, length >= 12 else { return }
            let window = data.load(fromByteOffset: 8, as: UInt32.self)
            if Thread.isMainThread {
                WindowEvents.dispatch(type, window)
            } else {
                DispatchQueue.main.async { WindowEvents.dispatch(type, window) }
            }
        }
        return register(proc, shown, nil) == 0 && register(proc, destroyed, nil) == 0
    }

    private static func dispatch(_ type: UInt32, _ window: CGWindowID) {
        for h in handlers { h(type, window) }
    }
}

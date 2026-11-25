import Darwin
import OSLog

enum NativeSessionLock {
    // login.framework is private. Only claim the keyboard shortcut when this
    // Mac provides the native lock request. Keep its library loaded for as
    // long as the stored function pointer can be called.
    private typealias LockFunction = @convention(c) () -> Int32
    private static let lockScreen: LockFunction? = {
        let path = "/System/Library/PrivateFrameworks/login.framework/Versions/A/login"
        guard let library = dlopen(path, RTLD_LAZY | RTLD_LOCAL) else { return nil }
        guard let symbol = dlsym(library, "SACLockScreenImmediate") else {
            dlclose(library)
            return nil
        }
        return unsafeBitCast(symbol, to: LockFunction.self)
    }()

    static var isAvailable: Bool { lockScreen != nil }

    // A successful request is an acknowledgement. Only the OS session state
    // can confirm that the screen has actually locked.
    @discardableResult
    static func request() -> Bool {
        guard let lockScreen else { return false }
        let status = lockScreen()
        if status != 0 {
            Logger(subsystem: "local.verseglass.app", category: "lock-shortcut")
                .error("Native lock request failed, status \(status, privacy: .public)")
        }
        return status == 0
    }
}

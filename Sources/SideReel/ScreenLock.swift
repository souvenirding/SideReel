import Foundation

enum ScreenLock {
    private static let cgSessionPath =
        "/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession"

    static func lock() -> Bool {
        if FileManager.default.isExecutableFile(atPath: cgSessionPath) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: cgSessionPath)
            process.arguments = ["-suspend"]
            if (try? process.run()) != nil { return true }
        }
        return lockViaLoginFramework()
    }

    // macOS 27 移除了 CGSession 可执行文件，回退到 login.framework 私有 API
    private static func lockViaLoginFramework() -> Bool {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/login.framework/login", RTLD_NOW),
              let symbol = dlsym(handle, "SACLockScreenImmediate") else {
            NSLog("SideReel: 无法定位锁屏入口（CGSession / SACLockScreenImmediate）")
            return false
        }
        typealias LockFunction = @convention(c) () -> Void
        unsafeBitCast(symbol, to: LockFunction.self)()
        return true
    }
}
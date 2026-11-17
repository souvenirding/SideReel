import AppKit

ConfigKeys.registerDefaults()

// 单实例：先查同 bundle ID 的存活进程（覆盖旧版本），再用 flock 兜住并发启动的竞争窗口
let bundleID = Bundle.main.bundleIdentifier ?? "com.souvenirding.SideReel"
let selfPID = ProcessInfo.processInfo.processIdentifier
if let existing = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
    .first(where: { $0.processIdentifier != selfPID && !$0.isTerminated }) {
    existing.activate(options: [])
    exit(0)
}
let lockPath = NSTemporaryDirectory() + bundleID + ".lock"
let lockFD = open(lockPath, O_CREAT | O_RDWR, 0o644)
if lockFD != -1 && flock(lockFD, LOCK_EX | LOCK_NB) != 0 {
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
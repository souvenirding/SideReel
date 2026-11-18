import AppKit
import SlideshowKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    let slideshow = SlideshowController()
    private let idleMonitor = IdleMonitor()
    private var statusItem: StatusItemController?
    private var lockObserver: NSObjectProtocol?
    private var lockClosePending = false
    private var pendingTerminate = false
    private var scheduleTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()
        statusItem = StatusItemController(slideshow: slideshow)
        slideshow.onUserExit = { [weak self] in self?.handlePlaybackExit() }

        idleMonitor.onIdle = { [weak self] in
            guard let self, !self.slideshow.isRunning else { return }
            _ = self.startSlideshow()
        }
        applyIdleMonitor()
        applySchedule()
        let t = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.checkSchedule()
        }
        t.tolerance = 5
        scheduleTimer = t
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.checkSchedule()
        }

        if UserDefaults.standard.string(forKey: ConfigKeys.folderPath)?.isEmpty != false {
            // 状态栏在启动后需要短暂时间才能锚定 popover
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.statusItem?.showPanel()
            }
        }
    }

    func applyIdleMonitor() {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: ConfigKeys.idleEnabled) {
            let minutes = max(defaults.integer(forKey: ConfigKeys.idleMinutes), 1)
            idleMonitor.start(threshold: TimeInterval(minutes) * 60)
        } else {
            idleMonitor.stop()
        }
    }

    func applySchedule() {
        checkSchedule()
    }

    private func checkSchedule() {
        guard slideshow.isRunning, !TimeSchedule.isActive() else { return }
        NSLog("SideReel: outside active schedule, stopping playback")
        handlePlaybackExit()
    }

    func startSlideshow() -> String? {
        let defaults = UserDefaults.standard
        guard TimeSchedule.isActive() else { return "当前不在生效时间段内。" }
        let folderPath = defaults.string(forKey: ConfigKeys.folderPath) ?? ""
        guard !folderPath.isEmpty else { return "请先选择图片文件夹。" }

        let names = (defaults.string(forKey: ConfigKeys.screenNames) ?? "")
            .split(separator: "\n").map(String.init)
        let screens = ScreenUtils.selectedScreens(names: names)
        guard !screens.isEmpty else { return SlideshowError.noScreen.localizedDescription }

        do {
            try slideshow.start(
                folder: URL(fileURLWithPath: folderPath),
                screens: screens,
                interval: defaults.double(forKey: ConfigKeys.interval),
                order: defaults.bool(forKey: ConfigKeys.shuffle) ? .shuffle : .sequential,
                keepAwake: defaults.bool(forKey: ConfigKeys.keepAwake),
                mode: PlaybackMode(rawValue: defaults.string(forKey: ConfigKeys.playbackMode) ?? "") ?? .slideshow,
                driftSpeed: defaults.double(forKey: ConfigKeys.driftSpeed),
                tileCount: defaults.integer(forKey: ConfigKeys.tileCount)
            )
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func stopSlideshow() {
        handlePlaybackExit()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard slideshow.isRunning, lockArmed() else { return .terminateNow }
        pendingTerminate = true
        handlePlaybackExit()
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        slideshow.stop()
        idleMonitor.stop()
        scheduleTimer?.invalidate()
    }

    private func handlePlaybackExit() {
        guard slideshow.isRunning, !lockClosePending else { return }
        guard lockArmed() else {
            slideshow.stop()
            return
        }
        // 先锁屏、冻住画面，等锁屏界面升起后再在其遮挡下关窗，避免闪一下桌面
        lockClosePending = true
        slideshow.freeze()
        NSLog("SideReel: exit with lock, playback frozen")
        guard ScreenLock.lock() else {
            finishLockClose(reason: "lock unavailable")
            return
        }
        lockObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.finishLockClose(reason: "screen locked")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.finishLockClose(reason: "lock wait timeout")
        }
    }

    private func finishLockClose(reason: String) {
        guard lockClosePending else { return }
        lockClosePending = false
        if let lockObserver {
            DistributedNotificationCenter.default().removeObserver(lockObserver)
            self.lockObserver = nil
        }
        if !slideshow.isRunning {
            slideshow.closeWindows()
        }
        NSLog("SideReel: closing playback windows (\(reason))")
        if pendingTerminate {
            NSApp.reply(toApplicationShouldTerminate: true)
        }
    }

    private func lockArmed() -> Bool {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: ConfigKeys.lockOnExit) else { return false }
        // 退出时重判覆盖状态：播放中热插拔导致不再覆盖全部屏幕时不锁屏
        let names = (defaults.string(forKey: ConfigKeys.screenNames) ?? "")
            .split(separator: "\n").map(String.init)
        return ScreenUtils.coversAllScreens(ScreenUtils.selectedScreens(names: names))
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: "退出 SideReel",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appMenuItem.submenu = appMenu
        NSApp.mainMenu = mainMenu
    }
}
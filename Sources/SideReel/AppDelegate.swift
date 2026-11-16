import AppKit
import SlideshowKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    let slideshow = SlideshowController()
    private let idleMonitor = IdleMonitor()
    private var statusItem: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()
        statusItem = StatusItemController(slideshow: slideshow)

        idleMonitor.onIdle = { [weak self] in
            guard let self, !self.slideshow.isRunning else { return }
            _ = self.startSlideshow()
        }
        applyIdleMonitor()

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

    func startSlideshow() -> String? {
        let defaults = UserDefaults.standard
        let folderPath = defaults.string(forKey: ConfigKeys.folderPath) ?? ""
        guard !folderPath.isEmpty else { return "请先选择图片文件夹。" }

        let names = (defaults.string(forKey: ConfigKeys.screenNames) ?? "")
            .split(separator: "\n").map(String.init)
        let screens: [NSScreen]
        if names.isEmpty {
            guard let target = ScreenUtils.defaultTarget() else {
                return SlideshowError.noScreen.localizedDescription
            }
            screens = [target]
        } else {
            screens = ScreenUtils.screens(matching: names)
            guard !screens.isEmpty else { return SlideshowError.noScreen.localizedDescription }
        }

        do {
            try slideshow.start(
                folder: URL(fileURLWithPath: folderPath),
                screens: screens,
                interval: defaults.double(forKey: ConfigKeys.interval),
                order: defaults.bool(forKey: ConfigKeys.shuffle) ? .shuffle : .sequential,
                keepAwake: defaults.bool(forKey: ConfigKeys.keepAwake),
                mode: PlaybackMode(rawValue: defaults.string(forKey: ConfigKeys.playbackMode) ?? "") ?? .slideshow,
                driftSpeed: defaults.double(forKey: ConfigKeys.driftSpeed)
            )
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func stopSlideshow() {
        slideshow.stop()
    }

    func applicationWillTerminate(_ notification: Notification) {
        slideshow.stop()
        idleMonitor.stop()
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
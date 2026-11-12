import AppKit
import SlideshowKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    let slideshow = SlideshowController()
    private let idleMonitor = IdleMonitor()
    private var statusItem: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
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
        guard let screen = ScreenUtils.screen(named: defaults.string(forKey: ConfigKeys.screenName) ?? "") else {
            return SlideshowError.noScreen.localizedDescription
        }
        do {
            try slideshow.start(
                folder: URL(fileURLWithPath: folderPath),
                screen: screen,
                interval: defaults.double(forKey: ConfigKeys.interval),
                order: defaults.bool(forKey: ConfigKeys.shuffle) ? .shuffle : .sequential
            )
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func stopSlideshow() {
        slideshow.stop()
    }
}
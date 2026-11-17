import AppKit
import Combine

public enum SlideshowError: LocalizedError {
    case folderMissing
    case noImages
    case noScreen

    public var errorDescription: String? {
        switch self {
        case .folderMissing: return "图片文件夹不存在，请重新选择。"
        case .noImages: return "该文件夹里没有可播放的图片。"
        case .noScreen: return "找不到目标显示器。"
        }
    }
}

public enum PlaybackMode: String {
    case slideshow
    case collage
}

public final class SlideshowController: ObservableObject {
    @Published public private(set) var isRunning = false
    @Published public private(set) var currentURL: URL?

    /// 设置后用户点击/Esc 退出交由外部处理（外部负责 stop 或 freeze）；未设置时直接 stop。
    public var onUserExit: (() -> Void)?

    private struct Player {
        let window: SlideshowWindow
        let imageView: NSImageView?
        let collageView: CollageDriftView?
        let screenName: String
    }

    private var players: [Player] = []
    private var timer: Timer?
    private var sequence: PlaybackSequence?
    private var interval: TimeInterval = 10
    private var activity: NSObjectProtocol?
    private var screenObserver: NSObjectProtocol?
    private var loadGeneration = 0
    private var keepAwake = true

    public init() {}

    public func start(
        folder: URL,
        screens: [NSScreen],
        interval: TimeInterval,
        order: PlaybackOrder,
        keepAwake: Bool,
        mode: PlaybackMode = .slideshow,
        driftSpeed: Double = 20,
        tileCount: Int = 13
    ) throws {
        stop()

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw SlideshowError.folderMissing
        }
        let library = ImageLibrary(folder: folder)
        guard !library.urls.isEmpty else { throw SlideshowError.noImages }
        guard !screens.isEmpty else { throw SlideshowError.noScreen }

        self.interval = min(max(interval, 1), 3600)
        self.sequence = PlaybackSequence(urls: library.urls, order: order)

        for screen in screens {
            let win = SlideshowWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false,
                screen: screen
            )
            win.setFrame(screen.frame, display: true)
            win.level = .screenSaver
            win.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
            win.backgroundColor = .black
            win.isOpaque = true
            win.ignoresMouseEvents = false
            win.isReleasedWhenClosed = false

            let view = ClickExitView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.wantsLayer = true
            view.layer?.backgroundColor = NSColor.black.cgColor
            view.onExit = { [weak self] in self?.exitByUser() }

            var imageView: NSImageView?
            var collageView: CollageDriftView?
            if mode == .slideshow {
                let iv = NSImageView(frame: view.bounds)
                iv.autoresizingMask = [.width, .height]
                iv.imageScaling = .scaleProportionallyUpOrDown
                iv.wantsLayer = true
                iv.animates = false
                view.addSubview(iv)
                imageView = iv
            } else {
                let collage = CollageDriftView(
                    frame: view.bounds,
                    speed: driftSpeed,
                    tileCount: tileCount,
                    nextURL: { [weak self] in self?.sequence?.next() },
                    onImageShown: { [weak self] url in self?.currentURL = url }
                )
                collage.autoresizingMask = [.width, .height]
                view.addSubview(collage)
                collageView = collage
            }

            win.contentView = view
            win.makeKeyAndOrderFront(nil)
            collageView?.start()
            players.append(Player(window: win, imageView: imageView, collageView: collageView, screenName: screen.localizedName))
        }
        NSApp.activate()

        self.keepAwake = keepAwake
        if keepAwake {
            activity = ProcessInfo.processInfo.beginActivity(
                options: .idleDisplaySleepDisabled,
                reason: "SideReel 正在播放图片轮播"
            )
        }

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleScreenChange()
        }

        isRunning = true
        if mode == .slideshow {
            showNext()
            let t = Timer.scheduledTimer(withTimeInterval: self.interval, repeats: true) { [weak self] _ in
                self?.showNext()
            }
            t.tolerance = self.interval * 0.1
            timer = t
        }
        let names = screens.map { $0.localizedName }.joined(separator: ", ")
        NSLog("SideReel: started on \(names), \(library.urls.count) images, mode \(mode.rawValue), interval \(self.interval)s")
    }

    public func stop() {
        teardown()
        closeWindows()
    }

    /// 停止播放但保留窗口画面，等锁屏升起后再 closeWindows，避免露出桌面
    public func freeze() {
        teardown()
    }

    public func closeWindows() {
        for player in players {
            player.window.orderOut(nil)
            player.window.close()
        }
        players = []
    }

    public func exitByUser() {
        if let onUserExit { onUserExit() } else { stop() }
    }

    private func teardown() {
        loadGeneration += 1
        timer?.invalidate()
        timer = nil
        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
        }
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
        for player in players {
            player.collageView?.stop()
        }
        sequence = nil
        if isRunning {
            isRunning = false
            NSLog("SideReel: stopped")
        }
    }

    public func setKeepAwake(_ on: Bool) {
        keepAwake = on
        guard isRunning else { return }
        if on, activity == nil {
            activity = ProcessInfo.processInfo.beginActivity(
                options: .idleDisplaySleepDisabled,
                reason: "SideReel 正在播放图片轮播"
            )
        } else if !on, let activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
        }
    }

    private func handleScreenChange() {
        guard isRunning else { return }
        var kept: [Player] = []
        for player in players {
            if let screen = NSScreen.screens.first(where: { $0.localizedName == player.screenName }) {
                player.window.setFrame(screen.frame, display: true)
                kept.append(player)
            } else {
                player.window.orderOut(nil)
                player.window.close()
            }
        }
        players = kept
        if players.isEmpty {
            stop()
        }
    }

    private func showNext() {
        guard isRunning, let url = sequence?.next() else { return }
        loadGeneration += 1
        let generation = loadGeneration
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let image = NSImage(contentsOf: url)
            DispatchQueue.main.async {
                guard let self, self.isRunning, self.loadGeneration == generation else { return }
                guard let image else { return }
                for player in self.players {
                    guard let imageView = player.imageView else { continue }
                    let fade = CATransition()
                    fade.duration = 0.45
                    fade.type = .fade
                    fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    imageView.layer?.add(fade, forKey: kCATransition)
                    imageView.image = image
                }
                self.currentURL = url
            }
        }
    }
}
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

public final class SlideshowController: ObservableObject {
    @Published public private(set) var isRunning = false
    @Published public private(set) var currentURL: URL?

    private struct Player {
        let window: SlideshowWindow
        let imageView: NSImageView
        let screenName: String
    }

    private var players: [Player] = []
    private var timer: Timer?
    private var sequence: PlaybackSequence?
    private var interval: TimeInterval = 10
    private var activity: NSObjectProtocol?
    private var screenObserver: NSObjectProtocol?
    private var loadGeneration = 0

    public init() {}

    public func start(folder: URL, screens: [NSScreen], interval: TimeInterval, order: PlaybackOrder) throws {
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
            view.onExit = { [weak self] in self?.stop() }

            let imageView = NSImageView(frame: view.bounds)
            imageView.autoresizingMask = [.width, .height]
            imageView.imageScaling = .scaleProportionallyUpOrDown
            imageView.wantsLayer = true
            imageView.animates = false
            view.addSubview(imageView)

            win.contentView = view
            win.makeKeyAndOrderFront(nil)
            players.append(Player(window: win, imageView: imageView, screenName: screen.localizedName))
        }
        NSApp.activate()

        activity = ProcessInfo.processInfo.beginActivity(
            options: .idleDisplaySleepDisabled,
            reason: "SideReel 正在播放图片轮播"
        )

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleScreenChange()
        }

        isRunning = true
        showNext()
        let t = Timer.scheduledTimer(withTimeInterval: self.interval, repeats: true) { [weak self] _ in
            self?.showNext()
        }
        t.tolerance = self.interval * 0.1
        timer = t
        let names = screens.map { $0.localizedName }.joined(separator: ", ")
        NSLog("SideReel: started on \(names), \(library.urls.count) images, interval \(self.interval)s")
    }

    public func stop() {
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
            player.imageView.image = nil
            player.window.orderOut(nil)
            player.window.close()
        }
        players = []
        sequence = nil
        if isRunning {
            isRunning = false
            NSLog("SideReel: stopped")
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
                    let fade = CATransition()
                    fade.duration = 0.45
                    fade.type = .fade
                    fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    player.imageView.layer?.add(fade, forKey: kCATransition)
                    player.imageView.image = image
                }
                self.currentURL = url
            }
        }
    }
}
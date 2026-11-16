import AppKit
import SlideshowKit

var failures = 0

func check(_ condition: Bool, _ label: String) {
    print("\(condition ? "PASS" : "FAIL"): \(label)")
    if !condition { failures += 1 }
}

// MARK: - PlaybackSequence logic

let urls = (1...5).map { URL(fileURLWithPath: "/tmp/img\($0).jpg") }

var sequential = PlaybackSequence(urls: urls, order: .sequential)
let seqDraws = (0..<7).compactMap { _ in sequential.next() }
check(seqDraws == [urls[0], urls[1], urls[2], urls[3], urls[4], urls[0], urls[1]], "sequential cycles in order")

var shuffle = PlaybackSequence(urls: urls, order: .shuffle)
let firstRound = (0..<5).compactMap { _ in shuffle.next() }
check(Set(firstRound) == Set(urls), "shuffle round 1 covers all images without repeat")
let secondRound = (0..<5).compactMap { _ in shuffle.next() }
check(Set(secondRound) == Set(urls), "shuffle round 2 covers all images without repeat")
check(secondRound.first != firstRound.last, "shuffle round boundary does not repeat last image")
var restarted = PlaybackSequence(urls: urls, order: .shuffle)
check(restarted.next() != secondRound.last, "restart avoids most recently shown image")

var empty = PlaybackSequence(urls: [], order: .shuffle)
check(empty.next() == nil, "empty library returns nil")

// MARK: - ImageLibrary

let args = CommandLine.arguments
guard args.count >= 2 else {
    print("usage: SlideshowSelfTest <image-folder> [duration-seconds] [screen-name]")
    exit(2)
}
let folder = URL(fileURLWithPath: args[1])
let duration = args.count >= 3 ? Double(args[2]) ?? 6 : 6
let screenName = args.count >= 4 ? args[3] : ""

let library = ImageLibrary(folder: folder)
check(!library.urls.isEmpty, "library found \(library.urls.count) images in \(folder.path)")

// MARK: - Window engine

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

guard let screen = ScreenUtils.screen(named: screenName) else {
    print("FAIL: no target screen")
    exit(1)
}
print("target screen: \(screen.localizedName) frame=\(screen.frame)")

let controller = SlideshowController()
let pid = ProcessInfo.processInfo.processIdentifier

// CGWindowList 在无屏幕录制权限的新系统上会返回失真的占位条目，
// 窗口几何与可见性以进程内 NSApp.windows 为准。
func visibleEngineWindow() -> NSWindow? {
    NSApp.windows.first { $0.level == .screenSaver && $0.isVisible }
}

func dumpCGWindows() {
    guard ProcessInfo.processInfo.environment["SIDEREEL_DEBUG_WINDOWS"] != nil else { return }
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    for info in list where (info[kCGWindowOwnerPID as String] as? pid_t) == pid {
        print("DEBUG window: \(info)")
    }
}

do {
    try controller.start(folder: folder, screens: [screen], interval: 2, order: .shuffle, keepAwake: true)
    check(true, "slideshow started")
} catch {
    print("FAIL: start threw \(error.localizedDescription)")
    exit(1)
}

Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { _ in
    dumpCGWindows()
    if let window = visibleEngineWindow() {
        check(window.frame == screen.frame, "window covers target screen exactly (got \(window.frame), expected \(screen.frame))")
    } else {
        check(false, "slideshow window not visible")
    }
    check(controller.currentURL != nil, "first image loaded")
}

var firstURL: URL?
Timer.scheduledTimer(withTimeInterval: 3.5, repeats: false) { _ in
    firstURL = controller.currentURL
    check(firstURL != nil, "image still present at 3.5s")
}

Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { _ in
    if library.urls.count > 1 {
        check(controller.currentURL != nil && controller.currentURL != firstURL, "image advanced after interval")
    } else {
        check(controller.currentURL == firstURL, "single-image library keeps showing the only image")
    }
}

Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { _ in
    controller.stop()
    check(!controller.isRunning, "controller reports stopped")
    Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { _ in
        dumpCGWindows()
        check(visibleEngineWindow() == nil, "window removed after stop")
        startCollagePhase()
    }
}

func collageLayers() -> [CALayer] {
    let collage = visibleEngineWindow()?.contentView?.subviews.first { $0 is CollageDriftView }
    return collage?.layer?.sublayers ?? []
}

var collageStartPositions: [CGPoint] = []
func startCollagePhase() {
    do {
        try controller.start(
            folder: folder, screens: [screen], interval: 2, order: .shuffle,
            keepAwake: true, mode: .collage, driftSpeed: 60
        )
        check(true, "collage started")
    } catch {
        print("FAIL: collage start threw \(error.localizedDescription)")
        exit(1)
    }
    Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { _ in
        check(visibleEngineWindow()?.frame == screen.frame, "collage window covers screen")
        check(controller.currentURL != nil, "collage loaded first tile image")
        let layers = collageLayers()
        check(layers.count >= 8, "collage populated \(layers.count) tiles")
        check(layers.contains { $0.sublayers?.first?.contents != nil }, "collage tiles loading images")
        collageStartPositions = layers.map { $0.position }
    }
    Timer.scheduledTimer(withTimeInterval: 4.5, repeats: false) { _ in
        let layers = collageLayers()
        check(layers.allSatisfy { $0.sublayers?.first?.contents != nil }, "all collage tiles have images")
        let visible = layers.filter { $0.opacity > 0.5 }.count
        check(visible >= layers.count / 2, "most collage tiles visible (\(visible)/\(layers.count))")
        let moved = zip(collageStartPositions, layers.map { $0.position })
            .filter { abs($0.x - $1.x) > 20 || abs($0.y - $1.y) > 2 }
        check(!collageStartPositions.isEmpty && moved.count >= collageStartPositions.count / 2,
              "collage tiles drift over time (\(moved.count) moved)")
    }
    Timer.scheduledTimer(withTimeInterval: 6.0, repeats: false) { _ in
        controller.stop()
        check(!controller.isRunning, "collage reports stopped")
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { _ in
            dumpCGWindows()
            check(visibleEngineWindow() == nil, "collage window removed after stop")
            print(failures == 0 ? "ALL TESTS PASSED" : "\(failures) FAILURES")
            exit(failures == 0 ? 0 : 1)
        }
    }
}

app.run()
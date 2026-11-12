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

func engineWindow() -> [String: Any]? {
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    return list.first { info in
        (info[kCGWindowOwnerPID as String] as? pid_t) == pid
            && (info[kCGWindowLayer as String] as? Int) == Int(CGWindowLevelForKey(.screenSaverWindow))
    }
}

func cocoaToCG(_ rect: CGRect) -> CGRect {
    let primary = NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.screens[0]
    return CGRect(x: rect.minX, y: primary.frame.height - rect.maxY, width: rect.width, height: rect.height)
}

do {
    try controller.start(folder: folder, screens: [screen], interval: 2, order: .shuffle)
    check(true, "slideshow started")
} catch {
    print("FAIL: start threw \(error.localizedDescription)")
    exit(1)
}

Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { _ in
    if let info = engineWindow(),
       let dict = info[kCGWindowBounds as String] as? [String: Any],
       let bounds = CGRect(dictionaryRepresentation: dict as CFDictionary) {
        let expected = cocoaToCG(screen.frame)
        check(bounds == expected, "window covers target screen exactly (got \(bounds), expected \(expected))")
    } else {
        check(false, "slideshow window not found in window list")
    }
    check(controller.currentURL != nil, "first image loaded")
}

var firstURL: URL?
Timer.scheduledTimer(withTimeInterval: 3.5, repeats: false) { _ in
    firstURL = controller.currentURL
    check(firstURL != nil, "image still present at 3.5s")
}

Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { _ in
    check(controller.currentURL != nil && controller.currentURL != firstURL, "image advanced after interval")
}

Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { _ in
    controller.stop()
    check(!controller.isRunning, "controller reports stopped")
    Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { _ in
        check(engineWindow() == nil, "window removed after stop")
        print(failures == 0 ? "ALL TESTS PASSED" : "\(failures) FAILURES")
        exit(failures == 0 ? 0 : 1)
    }
}

app.run()
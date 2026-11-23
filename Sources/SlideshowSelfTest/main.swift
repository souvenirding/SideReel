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

func collageView() -> CollageDriftView? {
    visibleEngineWindow()?.contentView?.subviews.first { $0 is CollageDriftView } as? CollageDriftView
}

func collageLayers() -> [CALayer] {
    collageView()?.layer?.sublayers ?? []
}

let maxCollageTiles = 9
var collageStartFrames: [ObjectIdentifier: CGRect] = [:]
var implicitViolations = 0
var verticalViolations = 0
var overlapViolations = 0
var swapViolations = 0
var prematureExitViolations = 0
var rightwardViolations = 0
var lastContents: [ObjectIdentifier: AnyObject] = [:]
var lastFrames: [ObjectIdentifier: CGRect] = [:]
var opacitySampler: Timer?

func checkNoImplicitOpacity(_ layers: [CALayer], _ label: String) {
    let bad = layers.filter { !Set($0.animationKeys() ?? []).isSubset(of: ["appear"]) }
    check(bad.isEmpty, "no implicit opacity animations (\(label))")
}
func startCollagePhase() {
    do {
        try controller.start(
            folder: folder, screens: [screen], interval: 2, order: .shuffle,
            keepAwake: true, mode: .collage, driftSpeed: 60, tileCount: maxCollageTiles
        )
        check(true, "collage started")
    } catch {
        print("FAIL: collage start threw \(error.localizedDescription)")
        exit(1)
    }
    let sampler = Timer(timeInterval: 0.1, repeats: true) { _ in
        let layers = collageLayers()
        let bad = layers.filter { !Set($0.animationKeys() ?? []).isSubset(of: ["appear"]) }
        implicitViolations += bad.count
        if let view = collageView() {
            let h = view.bounds.height
            verticalViolations += layers.filter { $0.frame.minY < -0.5 || $0.frame.maxY > h + 0.5 }.count
            let frames = layers.map { $0.frame }
            for i in frames.indices {
                for j in (i + 1)..<frames.count where frames[i].intersects(frames[j]) { overlapViolations += 1 }
            }
            for layer in layers {
                let key = ObjectIdentifier(layer)
                let frame = layer.frame
                if let old = lastFrames[key], frame.minX > old.minX + 1 { rightwardViolations += 1 }
                let contents = layer.sublayers?.first?.contents as AnyObject?
                if let old = lastContents[key], let c = contents, old !== c { swapViolations += 1 }
                if let c = contents { lastContents[key] = c }
                lastFrames[key] = frame
            }
            let live = Set(layers.map { ObjectIdentifier($0) })
            let gone = lastFrames.keys.filter { !live.contains($0) }
            for key in gone {
                // 上一帧还整张在屏内就没了 = 原地消失
                if let f = lastFrames[key], f.minX > 2, f.maxX < view.bounds.width - 2 {
                    prematureExitViolations += 1
                }
                lastFrames[key] = nil
            }
        }
    }
    RunLoop.main.add(sampler, forMode: .common)
    opacitySampler = sampler
    Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { _ in
        check(visibleEngineWindow()?.frame == screen.frame, "collage window covers screen")
        check(controller.currentURL != nil, "collage loaded first tile image")
        let layers = collageLayers()
        check(layers.count > 0 && layers.count <= maxCollageTiles,
              "collage stays within configured tile cap (got \(layers.count), max \(maxCollageTiles))")
        check(layers.contains { $0.sublayers?.first?.contents != nil }, "collage tiles loading images")
        checkNoImplicitOpacity(layers, "2.5s")
        collageStartFrames = Dictionary(uniqueKeysWithValues: layers.map { (ObjectIdentifier($0), $0.frame) })
    }
    Timer.scheduledTimer(withTimeInterval: 4.5, repeats: false) { _ in
        let layers = collageLayers()
        check(layers.allSatisfy { $0.sublayers?.first?.contents != nil }, "all collage tiles have images")
        let base = min(screen.frame.width, screen.frame.height)
        let widths = layers.map { $0.bounds.width }
        let inRange = widths.allSatisfy { $0 >= base * 0.199 - 1 && $0 <= base * 0.32 + 1 }
        check(inRange, "tile widths within 20%~32% of short edge (min \(widths.min() ?? 0), max \(widths.max() ?? 0), base \(base))")
        checkNoImplicitOpacity(layers, "4.5s")
        let onScreen = layers.filter { $0.frame.maxX > 0 && $0.frame.minX < screen.frame.width }.count
        check(onScreen >= 4, "collage keeps photos on screen (\(onScreen) in view)")
        // 照片墙：横向区间相交的两张必然纵向错开（全局重叠检查已保证），说明不是单行排列
        let frames = layers.map { $0.frame }
        var staggered = 0
        for i in frames.indices {
            for j in (i + 1)..<frames.count
            where frames[i].minX < frames[j].maxX && frames[j].minX < frames[i].maxX { staggered += 1 }
        }
        check(staggered >= 2, "wall staggers photos vertically, not a single row (\(staggered) x-overlapping pairs)")
        var moved = 0
        var still = 0
        for layer in layers {
            guard let start = collageStartFrames[ObjectIdentifier(layer)] else { continue }
            still += 1
            if start.minX - layer.frame.minX > 20 { moved += 1 }
        }
        check(still > 0 && moved == still, "every tile drifts leftward (\(moved)/\(still))")
    }
    Timer.scheduledTimer(withTimeInterval: 5.3, repeats: false) { _ in
        checkNoImplicitOpacity(collageLayers(), "5.3s")
    }
    Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false) { _ in
        opacitySampler?.invalidate()
        check(implicitViolations == 0, "no implicit opacity flash across whole collage phase (\(implicitViolations) violations)")
        check(verticalViolations == 0, "tiles never clip top/bottom edges (\(verticalViolations) violations)")
        check(overlapViolations == 0, "photos never overlap (\(overlapViolations) violations)")
        check(swapViolations == 0, "a photo keeps its image until it leaves the screen (\(swapViolations) swaps)")
        check(prematureExitViolations == 0, "photos leave only by drifting off the left edge (\(prematureExitViolations) violations)")
        check(rightwardViolations == 0, "photos never move rightward (\(rightwardViolations) violations)")
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
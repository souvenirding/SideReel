import AppKit
import ImageIO

public final class CollageDriftView: NSView {
    private final class Tile {
        let layer = CALayer()
        let content = CALayer()
        let depth: CGFloat
        let slotWidth: CGFloat
        var size: CGSize
        var center: CGPoint
        let bobPhase: CGFloat
        let bobAmp: CGFloat
        var targetOpacity: Float
        var loading = false
        var retiring = false

        init(depth: CGFloat, slotWidth: CGFloat, center: CGPoint) {
            self.depth = depth
            self.slotWidth = slotWidth
            self.size = CGSize(width: slotWidth, height: slotWidth)
            self.center = center
            self.bobPhase = CGFloat.random(in: 0..<(2 * .pi))
            self.bobAmp = CGFloat.random(in: 5...14)
            self.targetOpacity = Float(0.72 + 0.28 * depth)
        }
    }

    private let speed: CGFloat
    private let tileCount: Int
    private let nextURL: () -> URL?
    private let onImageShown: ((URL) -> Void)?

    private var tiles: [Tile] = []
    private var tickTimer: Timer?
    private var replaceTimer: Timer?
    private var lastTick: CFTimeInterval = 0
    private var generation = 0

    public init(
        frame: NSRect,
        speed: Double,
        tileCount: Int = 13,
        nextURL: @escaping () -> URL?,
        onImageShown: ((URL) -> Void)? = nil
    ) {
        self.speed = CGFloat(min(max(speed, 4), 120))
        self.tileCount = min(max(tileCount, 4), 30)
        self.nextURL = nextURL
        self.onImageShown = onImageShown
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.masksToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    public func start() {
        stop()
        generation += 1
        buildTiles()
        lastTick = CACurrentMediaTime()
        let tick = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        tick.tolerance = 0.005
        RunLoop.main.add(tick, forMode: .common)
        tickTimer = tick
        scheduleReplacement()
    }

    public func stop() {
        generation += 1
        tickTimer?.invalidate()
        tickTimer = nil
        replaceTimer?.invalidate()
        replaceTimer = nil
        for tile in tiles { tile.layer.removeFromSuperlayer() }
        tiles = []
    }

    private func buildTiles() {
        let area = bounds.width * bounds.height
        let base = min(bounds.width, bounds.height)
        guard area > 0, base > 0 else { return }
        let count = tileCount
        let scale = window?.backingScaleFactor ?? 2

        var newTiles: [Tile] = []
        for _ in 0..<count {
            let depth = CGFloat.random(in: 0.6...1.0)
            // 景深主要影响速度与亮度，尺寸只轻微缩放，避免远处照片小到看不清
            let width = base * CGFloat.random(in: 0.26...0.38) * (0.8 + 0.2 * depth)
            let center = CGPoint(
                x: CGFloat.random(in: 0...bounds.width),
                y: CGFloat.random(in: 0...bounds.height)
            )
            newTiles.append(Tile(depth: depth, slotWidth: width, center: center))
        }
        newTiles.sort { $0.depth < $1.depth }

        for (index, tile) in newTiles.enumerated() {
            let layer = tile.layer
            layer.bounds = CGRect(origin: .zero, size: tile.size)
            layer.position = tile.center
            layer.shadowColor = NSColor.black.cgColor
            layer.shadowOpacity = 0.55
            layer.shadowRadius = 18
            layer.shadowOffset = CGSize(width: 0, height: -8)
            layer.shouldRasterize = true
            layer.rasterizationScale = scale
            layer.opacity = 0

            let content = tile.content
            content.frame = layer.bounds
            content.cornerRadius = 12
            content.masksToBounds = true
            content.contentsGravity = .resizeAspect
            content.backgroundColor = NSColor(white: 1, alpha: 0.04).cgColor
            content.borderWidth = 1
            content.borderColor = NSColor(white: 1, alpha: 0.10).cgColor
            layer.addSublayer(content)
            self.layer?.addSublayer(layer)
            tiles.append(tile)
            loadImage(for: tile, fadeInDelay: Double(index) * 0.08)
        }
    }

    private func tick() {
        let now = CACurrentMediaTime()
        let dt = min(now - lastTick, 0.1)
        lastTick = now
        guard dt > 0 else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for tile in tiles {
            tile.center.x -= speed * tile.depth * CGFloat(dt)
            let halfW = tile.size.width / 2
            if tile.center.x + halfW < -40 {
                tile.center.x = bounds.width + halfW + 40
                tile.center.y = CGFloat.random(in: 0...bounds.height)
                if !tile.loading && !tile.retiring {
                    tile.layer.removeAllAnimations()
                    tile.layer.opacity = 0
                    loadImage(for: tile, fadeInDelay: 0)
                }
            }
            let bob = sin(CGFloat(now) * 0.25 + tile.bobPhase) * tile.bobAmp
            tile.layer.position = CGPoint(x: tile.center.x, y: tile.center.y + bob)
        }
        CATransaction.commit()
    }

    private func scheduleReplacement() {
        let t = Timer(timeInterval: Double.random(in: 3.5...6.5), repeats: false) { [weak self] _ in
            self?.replaceOneTile()
            self?.scheduleReplacement()
        }
        t.tolerance = 0.5
        RunLoop.main.add(t, forMode: .common)
        replaceTimer = t
    }

    private func replaceOneTile() {
        let candidates = tiles.filter { tile in
            !tile.loading && !tile.retiring
                && tile.center.x - tile.size.width / 2 > 0
                && tile.center.x + tile.size.width / 2 < bounds.width
                && tile.center.y - tile.size.height / 2 > 0
                && tile.center.y + tile.size.height / 2 < bounds.height
        }
        guard let tile = candidates.randomElement() else { return }
        tile.retiring = true
        let fadeOut = CABasicAnimation(keyPath: "opacity")
        fadeOut.fromValue = tile.layer.opacity
        fadeOut.toValue = 0
        fadeOut.duration = 0.9
        fadeOut.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        fadeOut.fillMode = .forwards
        fadeOut.isRemovedOnCompletion = false
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self, weak tile] in
            guard let self, let tile, tile.retiring else { return }
            // 必须禁用隐式动画：否则 removeAllAnimations 后设置 opacity=0
            // 会触发 0.25s 的隐式淡出，表现为照片闪回全亮再变暗
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            tile.layer.removeAllAnimations()
            tile.layer.opacity = 0
            CATransaction.commit()
            tile.retiring = false
            self.loadImage(for: tile, fadeInDelay: 0)
        }
        tile.layer.add(fadeOut, forKey: "retire")
        CATransaction.commit()
    }

    private func loadImage(for tile: Tile, fadeInDelay: Double) {
        guard let url = nextURL() else { return }
        tile.loading = true
        let gen = generation
        let maxPixel = Int(max(tile.slotWidth, tile.slotWidth * 1.7) * 2)
        DispatchQueue.global(qos: .userInitiated).async { [weak self, weak tile] in
            let image = Self.downsample(url: url, maxPixel: maxPixel)
            DispatchQueue.main.async {
                guard let self, let tile, self.generation == gen else { return }
                tile.loading = false
                guard let image else { return }
                let aspect = min(max(CGFloat(image.height) / CGFloat(image.width), 0.6), 1.7)
                tile.size = CGSize(width: tile.slotWidth, height: tile.slotWidth * aspect)

                // 换图与淡入在同一事务内原子提交，避免新图以旧不透明度闪现一帧
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                tile.layer.bounds = CGRect(origin: .zero, size: tile.size)
                tile.content.frame = tile.layer.bounds
                tile.content.contents = image
                let fadeIn = CABasicAnimation(keyPath: "opacity")
                fadeIn.fromValue = 0
                fadeIn.toValue = tile.targetOpacity
                fadeIn.duration = 1.1
                fadeIn.beginTime = CACurrentMediaTime() + fadeInDelay
                fadeIn.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                fadeIn.fillMode = .backwards
                tile.layer.opacity = tile.targetOpacity
                tile.layer.add(fadeIn, forKey: "appear")
                CATransaction.commit()
                self.onImageShown?(url)
            }
        }
    }

    private static func downsample(url: URL, maxPixel: Int) -> CGImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return nil }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(maxPixel, 64),
        ] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options)
    }
}
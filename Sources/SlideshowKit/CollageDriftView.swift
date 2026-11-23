import AppKit
import ImageIO

/// 照片墙式漂移：照片以随机位置铺成一面墙，整墙同速向左。
/// 排布时按"占位矩形"互斥挑选位置，又因为所有照片速度一致、相对位置恒定，
/// 一旦落位不重叠就永远不重叠；新照片只在屏幕右边缘之外找空位，
/// 因此只会从右侧滑入、左侧滑出，中途不换图、不淡出，允许留白。
public final class CollageDriftView: NSView {
    private final class Tile {
        let layer = CALayer()
        let content = CALayer()
        let depth: CGFloat
        let size: CGSize
        var center: CGPoint
        let bobPhase: CGFloat
        let bobAmp: CGFloat
        let targetOpacity: Float
        var released = false

        init(depth: CGFloat, size: CGSize, center: CGPoint) {
            self.depth = depth
            self.size = size
            self.center = center
            self.bobPhase = CGFloat.random(in: 0..<(2 * .pi))
            self.bobAmp = CGFloat.random(in: 4...9)
            self.targetOpacity = Float(0.72 + 0.28 * depth)
        }

        var rect: CGRect {
            CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2,
                   width: size.width, height: size.height)
        }

        // 投影横向扩散 + 上下浮动都算进占位，视觉上照片之间始终隔出一条缝
        var reservedRect: CGRect {
            rect.insetBy(dx: -Tile.shadowPad, dy: -(bobAmp + Tile.shadowPad))
        }

        static let shadowPad: CGFloat = 20
    }

    private let speed: CGFloat
    private let maxTiles: Int
    private let nextURL: () -> URL?
    private let onImageShown: ((URL) -> Void)?

    private var tiles: [Tile] = []
    private var tickTimer: Timer?
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
        self.maxTiles = min(max(tileCount, 4), 30)
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
        seedWall()
        lastTick = CACurrentMediaTime()
        let tick = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        tick.tolerance = 0.005
        RunLoop.main.add(tick, forMode: .common)
        tickTimer = tick
    }

    public func stop() {
        generation += 1
        tickTimer?.invalidate()
        tickTimer = nil
        for tile in tiles {
            tile.released = true
            tile.layer.removeAllAnimations()
            tile.layer.removeFromSuperlayer()
        }
        tiles = []
    }

    private var shortEdge: CGFloat { min(bounds.width, bounds.height) }

    // 上下各留出的余量：浮动幅度上限 9 + 投影纵向扩散
    private var verticalPad: CGFloat { 9 + Tile.shadowPad }

    // 一张照片的可摆放纵向区间（底边原点）
    private func verticalRange(for size: CGSize) -> ClosedRange<CGFloat>? {
        let lo = verticalPad
        let hi = bounds.height - verticalPad - size.height
        return lo <= hi ? lo...hi : nil
    }

    private func photoXRange(for size: CGSize) -> ClosedRange<CGFloat>? {
        let lo = bounds.width
        let hi = bounds.width + max(0, shortEdge * 0.9 - size.width)
        return lo <= hi ? lo...hi : nil
    }

    /// 先定尺寸再找位置：尺寸取自图片真实宽高比，占位才算得准
    private func nextPhotoSize() -> (url: URL, size: CGSize)? {
        for _ in 0..<4 {
            guard let url = nextURL() else { return nil }
            let width = shortEdge * CGFloat.random(in: 0.20...0.32)
            let height = width * Self.aspect(of: url)
            guard height <= bounds.height - 2 * verticalPad, width <= bounds.width else { continue }
            return (url, CGSize(width: width, height: height))
        }
        return nil
    }

    /// 在给定横向区间内随机采样，取最靠左的空位（靠左即最快滑进画面，墙才铺得满）
    private func findFreeSpot(for size: CGSize, xRange: ClosedRange<CGFloat>) -> CGPoint? {
        guard let yRange = verticalRange(for: size) else { return nil }
        var best: (leftEdge: CGFloat, center: CGPoint)?
        for _ in 0..<48 {
            let leftEdge = CGFloat.random(in: xRange)
            let bottom = CGFloat.random(in: yRange)
            // 候选位按最大浮动量占位（落位后本张的浮动只会更小），占位互斥才成立
            let candidate = CGRect(x: leftEdge - Tile.shadowPad, y: bottom - verticalPad,
                                   width: size.width + 2 * Tile.shadowPad,
                                   height: size.height + 2 * verticalPad)
            let hit = tiles.contains { $0.reservedRect.intersects(candidate) }
            if hit { continue }
            let center = CGPoint(x: leftEdge + size.width / 2, y: bottom + size.height / 2)
            if best == nil || leftEdge < best!.leftEdge { best = (leftEdge, center) }
        }
        return best?.center
    }

    private func install(_ url: URL, size: CGSize, center: CGPoint) {
        let tile = Tile(depth: CGFloat.random(in: 0.6...1.0), size: size, center: center)
        let layer = tile.layer
        layer.bounds = CGRect(origin: .zero, size: size)
        layer.position = center
        layer.shadowColor = NSColor.black.cgColor
        layer.shadowOpacity = 0.5
        layer.shadowRadius = 12
        layer.shadowOffset = CGSize(width: 0, height: -6)
        layer.shouldRasterize = true
        layer.rasterizationScale = window?.backingScaleFactor ?? 2
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
        loadImage(url, for: tile)
    }

    // 起始画面：在可见区域内随机撒满一整面墙，每张都完整在屏内
    private func seedWall() {
        guard bounds.width > 0, shortEdge > 0 else { return }
        var misses = 0
        while tiles.count < maxTiles, misses < maxTiles * 2 {
            guard let (url, size) = nextPhotoSize() else { return }
            let xLo: CGFloat = 0
            let xHi = max(xLo, bounds.width - size.width)
            guard let center = findFreeSpot(for: size, xRange: xLo...xHi) else {
                misses += 1
                continue
            }
            install(url, size: size, center: center)
        }
    }

    private func tick() {
        let now = CACurrentMediaTime()
        let dt = min(now - lastTick, 0.1)
        lastTick = now
        guard dt > 0 else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let dx = speed * CGFloat(dt)
        for tile in tiles { tile.center.x -= dx }
        pruneExitedTiles()
        feedWall()
        for tile in tiles {
            let bob = sin(now * 0.25 + tile.bobPhase) * tile.bobAmp
            tile.layer.position = CGPoint(x: tile.center.x, y: tile.center.y + bob)
        }
        CATransaction.commit()
    }

    private func pruneExitedTiles() {
        var kept: [Tile] = []
        kept.reserveCapacity(tiles.count)
        for tile in tiles {
            if tile.center.x + tile.size.width / 2 <= 0 {
                tile.released = true
                tile.layer.removeAllAnimations()
                tile.layer.removeFromSuperlayer()
            } else {
                kept.append(tile)
            }
        }
        tiles = kept
    }

    // 右侧续图：只在屏幕右边缘之外找空位，滑进来即开始可见；找不到就下个 tick 再试
    private func feedWall() {
        guard bounds.width > 0, shortEdge > 0 else { return }
        if tiles.isEmpty {
            seedWall()
            return
        }
        while tiles.count < maxTiles {
            guard let (url, size) = nextPhotoSize() else { return }
            guard let xRange = photoXRange(for: size),
                  let center = findFreeSpot(for: size, xRange: xRange) else { return }
            install(url, size: size, center: center)
        }
    }

    private func loadImage(_ url: URL, for tile: Tile) {
        let gen = generation
        let maxPixel = Int(max(tile.size.width, tile.size.height) * 2)
        DispatchQueue.global(qos: .userInitiated).async { [weak self, weak tile] in
            let image = Self.downsample(url: url, maxPixel: maxPixel)
            DispatchQueue.main.async {
                guard let self, let tile, self.generation == gen, !tile.released else { return }
                guard let image else { return }

                CATransaction.begin()
                CATransaction.setDisableActions(true)
                tile.content.contents = image
                let bob = sin(CGFloat(CACurrentMediaTime()) * 0.25 + tile.bobPhase) * tile.bobAmp
                tile.layer.position = CGPoint(x: tile.center.x, y: tile.center.y + bob)
                // 图片到位前保持空白槽位，到屏后直接亮起，不做淡出换图
                let fadeIn = CABasicAnimation(keyPath: "opacity")
                fadeIn.fromValue = 0
                fadeIn.toValue = tile.targetOpacity
                fadeIn.duration = 0.35
                fadeIn.timingFunction = CAMediaTimingFunction(name: .easeOut)
                fadeIn.fillMode = .backwards
                tile.layer.opacity = tile.targetOpacity
                tile.layer.add(fadeIn, forKey: "appear")
                CATransaction.commit()
                self.onImageShown?(url)
            }
        }
    }

    /// 只读文件头拿宽高比：落位前就要确定整张尺寸，占位才算得准
    private static func aspect(of url: URL) -> CGFloat {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let pixelWidth = props[kCGImagePropertyPixelWidth] as? NSNumber,
              let pixelHeight = props[kCGImagePropertyPixelHeight] as? NSNumber,
              pixelWidth.doubleValue > 0, pixelHeight.doubleValue > 0
        else { return 1 }
        var ratio = pixelHeight.doubleValue / pixelWidth.doubleValue
        let orientation = (props[kCGImagePropertyOrientation] as? NSNumber)?.uint32Value ?? 1
        if orientation >= 5 { ratio = 1 / ratio }
        return min(max(CGFloat(ratio), 0.6), 1.7)
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

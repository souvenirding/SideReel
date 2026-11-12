import Foundation

public enum PlaybackOrder {
    case sequential
    case shuffle
}

public struct PlaybackSequence {
    private static let historyKey = "SlideshowKit.shuffleRecentHistory"

    private let urls: [URL]
    private let order: PlaybackOrder
    private var bag: [URL] = []
    private var index = 0
    private var lastDrawn: URL?
    private var recent: [URL] = []
    private let recentLimit: Int

    public init(urls: [URL], order: PlaybackOrder) {
        self.urls = urls
        self.order = order
        self.recentLimit = min(max(urls.count - 1, 0), 100)
        if order == .shuffle {
            let byPath = Dictionary(urls.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
            let paths = UserDefaults.standard.stringArray(forKey: Self.historyKey) ?? []
            recent = paths.compactMap { byPath[$0] }
        }
    }

    public mutating func next() -> URL? {
        guard !urls.isEmpty else { return nil }
        switch order {
        case .sequential:
            defer { index += 1 }
            return urls[index % urls.count]
        case .shuffle:
            if bag.isEmpty { refill() }
            let url = bag.removeLast()
            lastDrawn = url
            recent.removeAll { $0 == url }
            recent.append(url)
            if recent.count > recentLimit {
                recent.removeFirst(recent.count - recentLimit)
            }
            UserDefaults.standard.set(recent.map { $0.path }, forKey: Self.historyKey)
            return url
        }
    }

    private mutating func refill() {
        let recentSet = Set(recent)
        let fresh = urls.filter { !recentSet.contains($0) }
        let stale = urls.filter { recentSet.contains($0) }
        bag = stale.shuffled() + fresh.shuffled()
        if let last = lastDrawn, bag.count > 1, bag.last == last {
            bag.swapAt(bag.count - 1, Int.random(in: 0..<(bag.count - 1)))
        }
    }
}
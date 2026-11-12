import Foundation

public enum PlaybackOrder {
    case sequential
    case shuffle
}

public struct PlaybackSequence {
    private let urls: [URL]
    private let order: PlaybackOrder
    private var bag: [URL] = []
    private var index = 0

    public init(urls: [URL], order: PlaybackOrder) {
        self.urls = urls
        self.order = order
    }

    public mutating func next() -> URL? {
        guard !urls.isEmpty else { return nil }
        switch order {
        case .sequential:
            defer { index += 1 }
            return urls[index % urls.count]
        case .shuffle:
            if bag.isEmpty { bag = urls.shuffled() }
            return bag.removeLast()
        }
    }
}
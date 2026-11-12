import Foundation
import SlideshowKit

final class FolderImageCounter: ObservableObject {
    @Published private(set) var count: Int?

    private var source: DispatchSourceFileSystemObject?
    private var pending: DispatchWorkItem?
    private let queue = DispatchQueue(label: "com.souvenirding.SideReel.imagecount")

    func setFolder(_ path: String) {
        queue.async { [weak self] in
            guard let self else { return }
            self.source?.cancel()
            self.source = nil
            self.pending?.cancel()
            self.pending = nil
            guard !path.isEmpty else {
                DispatchQueue.main.async { self.count = nil }
                return
            }
            let url = URL(fileURLWithPath: path)
            self.recompute(url)
            let fd = open(url.path, O_EVTONLY)
            guard fd >= 0 else { return }
            let src = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: [.write, .extend, .rename, .delete, .attrib],
                queue: self.queue
            )
            src.setEventHandler { [weak self] in self?.scheduleRecompute(url) }
            src.setCancelHandler { close(fd) }
            src.resume()
            self.source = src
        }
    }

    private func scheduleRecompute(_ url: URL) {
        pending?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.recompute(url) }
        pending = item
        queue.asyncAfter(deadline: .now() + 0.5, execute: item)
    }

    private func recompute(_ url: URL) {
        let n = ImageLibrary(folder: url).urls.count
        DispatchQueue.main.async { [weak self] in self?.count = n }
    }

    deinit {
        source?.cancel()
    }
}
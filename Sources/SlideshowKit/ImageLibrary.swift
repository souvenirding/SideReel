import Foundation
import UniformTypeIdentifiers

public struct ImageLibrary {
    public let urls: [URL]

    public init(folder: URL) {
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentTypeKey]
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else {
            urls = []
            return
        }
        urls = files.filter { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true,
                  let type = values.contentType else { return false }
            return type.conforms(to: .image)
        }.sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }
    }
}
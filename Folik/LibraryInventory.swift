import CoreGraphics
import Foundation

nonisolated struct LibraryInventorySnapshot: Sendable {
    let documents: [LibraryDocument]
    let parsedPDFCount: Int
}

nonisolated enum LibraryInventory {
    static func read(directory: URL, previous: [LibraryDocument]) throws -> LibraryInventorySnapshot {
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
        let cached = Dictionary(uniqueKeysWithValues: previous.map { ($0.url.standardizedFileURL, $0) })
        var documents: [LibraryDocument] = []
        var parsed = 0
        for url in try manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]) {
            try Task.checkCancellation()
            guard url.pathExtension.lowercased() == "pdf" else { continue }
            let values = try url.resourceValues(forKeys: keys)
            guard values.isRegularFile == true else { continue }
            let size = Int64(values.fileSize ?? 0)
            let modified = values.contentModificationDate ?? .distantPast
            let old = cached[url.standardizedFileURL]
            if let old, old.fileSize == size, old.modifiedAt == modified {
                documents.append(old)
                continue
            }
            parsed += 1
            guard let provider = CGDataProvider(url: url as CFURL), let pdf = CGPDFDocument(provider) else { continue }
            documents.append(LibraryDocument(id: old?.id ?? UUID(), url: url, pageCount: pdf.numberOfPages, fileSize: size, modifiedAt: modified))
        }
        return LibraryInventorySnapshot(documents: documents.sorted { $0.modifiedAt > $1.modifiedAt }, parsedPDFCount: parsed)
    }
}

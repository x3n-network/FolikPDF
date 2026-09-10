import Foundation
import PDFKit

actor LibrarySearchIndex {
    private struct Archive: Codable {
        var version = 1
        var records: [String: Record] = [:]
    }

    private struct Record: Codable {
        let fileSize: Int64
        let modifiedAt: TimeInterval
        let textBytes: Int
        let pages: [String]

        func matches(_ document: LibraryDocument) -> Bool {
            fileSize == document.fileSize
                && abs(modifiedAt - document.modifiedAt.timeIntervalSinceReferenceDate) < 0.001
        }
    }

    private static let maximumCachedTextBytes = 8 * 1024 * 1024
    private static let maximumArchiveTextBytes = 48 * 1024 * 1024
    private let documentCacheLimit: Int
    private let archiveCacheLimit: Int
    private(set) var peakRetainedDocumentTextBytes = 0
    private let cacheURL: URL
    private var inMemoryArchive: Archive?

    init(cacheURL: URL? = nil, documentCacheLimit: Int = 8 * 1024 * 1024, archiveCacheLimit: Int = 48 * 1024 * 1024) {
        self.documentCacheLimit = max(0, min(documentCacheLimit, Self.maximumCachedTextBytes))
        self.archiveCacheLimit = max(0, min(archiveCacheLimit, Self.maximumArchiveTextBytes))
        if let cacheURL {
            self.cacheURL = cacheURL
        } else {
            let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Folik", isDirectory: true)
            self.cacheURL = root.appendingPathComponent("library-search-v1.json")
        }
    }

    func search(_ query: String, documents: [LibraryDocument]) throws -> LibrarySearchResult {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return LibrarySearchResult() }
        try Task.checkCancellation()
        peakRetainedDocumentTextBytes = 0
        var archive = inMemoryArchive ?? load()
        let validKeys = Set(documents.map { key(for: $0) })
        let originalKeys = Set(archive.records.keys)
        archive.records = archive.records.filter { validKeys.contains($0.key) }
        var changed = originalKeys != Set(archive.records.keys)
        var totalCachedBytes = archive.records.values.reduce(0) { $0 + $1.textBytes }
        var result = LibrarySearchResult()

        for document in documents {
            try Task.checkCancellation()
            let recordKey = key(for: document)
            guard document.fileSize <= PDFProcessing.maximumBytes, document.pageCount <= 500 else {
                result.skipped += 1
                if let removed = archive.records.removeValue(forKey: recordKey) {
                    totalCachedBytes -= removed.textBytes
                    changed = true
                }
                continue
            }
            if let cached = archive.records[recordKey], cached.matches(document) {
                var matches = LibrarySearch.DocumentMatches(query: query)
                for (index, text) in cached.pages.enumerated() {
                    try Task.checkCancellation()
                    matches.consume(text, page: index + 1)
                }
                matches.append(document: document, to: &result)
                continue
            }

            if let removed = archive.records.removeValue(forKey: recordKey) { totalCachedBytes -= removed.textBytes }
            changed = true
            // Each uncached document is matched as it is read. Only cache-eligible text is retained.
            try autoreleasepool {
                guard let pdf = PDFDocument(url: document.url), !pdf.isLocked, pdf.pageCount <= 500 else {
                    result.skipped += 1
                    return
                }
                let budget = min(documentCacheLimit, max(0, archiveCacheLimit - totalCachedBytes))
                var pages: [String] = []
                var retainedBytes = 0
                var canCache = budget > 0
                var matches = LibrarySearch.DocumentMatches(query: query)
                for pageIndex in 0..<pdf.pageCount {
                    try Task.checkCancellation()
                    try autoreleasepool {
                        let text = pdf.page(at: pageIndex)?.string ?? ""
                        try Task.checkCancellation()
                        matches.consume(text, page: pageIndex + 1)
                        guard canCache else { return }
                        let size = text.utf8.count
                        if size <= budget - retainedBytes {
                            pages.append(text)
                            retainedBytes += size
                            peakRetainedDocumentTextBytes = max(peakRetainedDocumentTextBytes, retainedBytes)
                        } else {
                            canCache = false
                            pages.removeAll(keepingCapacity: false)
                            retainedBytes = 0
                        }
                    }
                }
                matches.append(document: document, to: &result)
                if canCache {
                    archive.records[recordKey] = Record(fileSize: document.fileSize, modifiedAt: document.modifiedAt.timeIntervalSinceReferenceDate, textBytes: retainedBytes, pages: pages)
                    totalCachedBytes += retainedBytes
                }
            }
        }
        try Task.checkCancellation()
        inMemoryArchive = archive
        if changed { try? save(archive) }
        return result
    }

    /// Discard only the disposable in-memory archive; the on-disk index is reusable.
    func releaseMemory() { inMemoryArchive = nil }
    var retainedTextBytes: Int { inMemoryArchive?.records.values.reduce(0) { $0 + $1.textBytes } ?? 0 }

    func removeAll() throws {
        inMemoryArchive = Archive()
        guard FileManager.default.fileExists(atPath: cacheURL.path) else { return }
        try FileManager.default.removeItem(at: cacheURL)
    }

    private func key(for document: LibraryDocument) -> String {
        document.url.standardizedFileURL.path
    }

    private func load() -> Archive {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: cacheURL.path),
              let size = attributes[.size] as? NSNumber, size.int64Value <= 64 * 1024 * 1024,
              let data = try? Data(contentsOf: cacheURL),
              data.count <= 64 * 1024 * 1024,
              let archive = try? JSONDecoder().decode(Archive.self, from: data),
              archive.version == 1,
              archive.records.values.allSatisfy({
                  $0.fileSize >= 0
                      && $0.textBytes >= 0
                      && $0.textBytes <= Self.maximumCachedTextBytes
                      && $0.pages.count <= 500
              }),
              archive.records.values.reduce(0, { $0 + $1.textBytes }) <= Self.maximumArchiveTextBytes else {
            return Archive()
        }
        return archive
    }

    private func save(_ archive: Archive) throws {
        let directory = cacheURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(archive).write(
            to: cacheURL,
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
    }
}

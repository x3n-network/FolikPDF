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
    private let cacheURL: URL
    private var inMemoryArchive: Archive?

    init(cacheURL: URL? = nil) {
        if let cacheURL {
            self.cacheURL = cacheURL
        } else {
            let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Folik", isDirectory: true)
            self.cacheURL = root.appendingPathComponent("library-search-v1.json")
        }
    }

    func search(_ query: String, documents: [LibraryDocument]) throws -> LibrarySearchResult {
        var archive = inMemoryArchive ?? load()
        let validKeys = Set(documents.map { key(for: $0) })
        let originalKeys = Set(archive.records.keys)
        archive.records = archive.records.filter { validKeys.contains($0.key) }
        var changed = originalKeys != Set(archive.records.keys)
        var indexed: [(document: LibraryDocument, pages: [String])] = []
        var skipped = 0

        for document in documents {
            try Task.checkCancellation()
            guard document.fileSize <= PDFProcessing.maximumBytes,
                  document.pageCount <= 500 else {
                skipped += 1
                continue
            }

            let recordKey = key(for: document)
            if let cached = archive.records[recordKey], cached.matches(document) {
                indexed.append((document, cached.pages))
                continue
            }

            guard let pdf = PDFDocument(url: document.url), !pdf.isLocked else {
                skipped += 1
                archive.records.removeValue(forKey: recordKey)
                changed = true
                continue
            }

            var pages: [String] = []
            var cachedBytes = 0
            for index in 0..<pdf.pageCount {
                try Task.checkCancellation()
                let text = pdf.page(at: index)?.string ?? ""
                cachedBytes += text.utf8.count
                pages.append(text)
            }
            indexed.append((document, pages))

            if cachedBytes <= Self.maximumCachedTextBytes {
                let previousBytes = archive.records[recordKey]?.textBytes ?? 0
                let archiveBytes = archive.records.values.reduce(0) { $0 + $1.textBytes } - previousBytes
                if archiveBytes + cachedBytes <= Self.maximumArchiveTextBytes {
                    archive.records[recordKey] = Record(
                        fileSize: document.fileSize,
                        modifiedAt: document.modifiedAt.timeIntervalSinceReferenceDate,
                        textBytes: cachedBytes,
                        pages: pages
                    )
                } else {
                    archive.records.removeValue(forKey: recordKey)
                }
            } else {
                archive.records.removeValue(forKey: recordKey)
            }
            changed = true
        }

        // The index is disposable. A cache write failure must never make search itself fail.
        inMemoryArchive = archive
        if changed { try? save(archive) }
        return try LibrarySearch.search(query, indexedPages: indexed, skipped: skipped)
    }

    func removeAll() throws {
        inMemoryArchive = Archive()
        guard FileManager.default.fileExists(atPath: cacheURL.path) else { return }
        try FileManager.default.removeItem(at: cacheURL)
    }

    private func key(for document: LibraryDocument) -> String {
        document.url.standardizedFileURL.path
    }

    private func load() -> Archive {
        guard let data = try? Data(contentsOf: cacheURL),
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

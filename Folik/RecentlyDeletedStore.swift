import Foundation

struct DeletedDocument: Codable, Equatable, Identifiable {
    let id: UUID
    let originalFilename: String
    let deletedAt: Date
    let metadata: LibraryMetadata
    let bookmarks: [Int]
    let readerState: ReaderStateStore.StoredReaderState?
    var displayName: String { URL(fileURLWithPath: originalFilename).deletingPathExtension().lastPathComponent }
}

struct RecentlyDeletedStore {
    let root: URL
    private let manager = FileManager.default
    func package(_ id: UUID) -> URL { root.appendingPathComponent(id.uuidString, isDirectory: true) }
    func pdf(_ id: UUID) -> URL { package(id).appendingPathComponent("document.pdf") }

    func read(_ id: UUID) throws -> DeletedDocument {
        let data = try Data(contentsOf: package(id).appendingPathComponent("record.json"))
        guard data.count <= 2 * 1024 * 1024 else { throw CocoaError(.fileReadCorruptFile) }
        let record = try JSONDecoder().decode(DeletedDocument.self, from: data)
        guard record.id == id, record.originalFilename == URL(fileURLWithPath: record.originalFilename).lastPathComponent,
              record.originalFilename.lowercased().hasSuffix(".pdf") else { throw CocoaError(.fileReadCorruptFile) }
        return record
    }

    func inventory() throws -> (documents: [DeletedDocument], unreadable: Int) {
        guard manager.fileExists(atPath: root.path) else { return ([], 0) }
        var documents: [DeletedDocument] = []
        var unreadable = 0
        for url in try manager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
            guard let id = UUID(uuidString: url.lastPathComponent) else { unreadable += 1; continue }
            // A manifest without a PDF is an interrupted archive or a completed restore.
            guard manager.fileExists(atPath: pdf(id).path) else { continue }
            do { documents.append(try read(id)) } catch { unreadable += 1 }
        }
        return (documents.sorted { $0.deletedAt > $1.deletedAt }, unreadable)
    }

    func archive(_ record: DeletedDocument, from source: URL) throws {
        let directory = package(record.id)
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            try JSONEncoder().encode(record).write(to: directory.appendingPathComponent("record.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            try manager.moveItem(at: source, to: pdf(record.id))
        } catch {
            if !manager.fileExists(atPath: pdf(record.id).path) { try? manager.removeItem(at: directory) }
            throw error
        }
    }

    func remove(_ id: UUID) throws {
        _ = try read(id)
        try manager.removeItem(at: package(id))
    }
}

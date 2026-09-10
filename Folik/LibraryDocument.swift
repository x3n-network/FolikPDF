import Foundation

nonisolated struct LibraryDocument: Identifiable, Hashable, Sendable {
    let id: UUID
    let url: URL
    let pageCount: Int
    let fileSize: Int64
    let modifiedAt: Date

    init(id: UUID = UUID(), url: URL, pageCount: Int, fileSize: Int64, modifiedAt: Date) {
        self.id = id
        self.url = url
        self.pageCount = pageCount
        self.fileSize = fileSize
        self.modifiedAt = modifiedAt
    }

    var displayName: String { url.deletingPathExtension().lastPathComponent }
    var pageDescription: String { pageCount == 1 ? "1 page" : "\(pageCount) pages" }
    var fileSizeDescription: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
}

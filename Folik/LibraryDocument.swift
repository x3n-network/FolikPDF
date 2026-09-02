import Foundation

struct LibraryDocument: Identifiable, Hashable, Sendable {
    let url: URL
    let pageCount: Int
    let fileSize: Int64
    let modifiedAt: Date

    var id: URL { url }
    var displayName: String { url.deletingPathExtension().lastPathComponent }
    var pageDescription: String { pageCount == 1 ? "1 page" : "\(pageCount) pages" }
    var fileSizeDescription: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
}

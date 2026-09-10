import CoreTransferable
import Foundation
import UniformTypeIdentifiers

nonisolated struct PDFTransferItem: Transferable, Sendable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .pdf) { item in
            SentTransferredFile(item.url)
        } importing: { received in
            try temporaryCopy(of: received.file)
        }
    }

    static func temporaryCopy(of source: URL, fileManager: FileManager = .default) throws -> PDFTransferItem {
        try Task.checkCancellation()
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("Folik Drop-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            let destination = directory.appendingPathComponent(filename(for: source))
            try fileManager.copyItem(at: source, to: destination)
            try Task.checkCancellation()
            return PDFTransferItem(url: destination)
        } catch {
            try? fileManager.removeItem(at: directory)
            throw error
        }
    }

    static func removeTemporaryCopies(_ items: [PDFTransferItem]) {
        let fileManager = FileManager.default
        for directory in Set(items.map { $0.url.deletingLastPathComponent() })
            where directory.lastPathComponent.hasPrefix("Folik Drop-") {
            try? fileManager.removeItem(at: directory)
        }
    }

    private static func filename(for source: URL) -> String {
        let stem = source.deletingPathExtension().lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stem.isEmpty else { return "Dropped PDF.pdf" }
        return String(stem.unicodeScalars.prefix(60)) + ".pdf"
    }
}

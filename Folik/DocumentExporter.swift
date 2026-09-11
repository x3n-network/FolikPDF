import CoreGraphics
import Foundation
import PDFKit

enum DocumentExportMode: String, Sendable {
    case original
    case editable
    case flattened

    nonisolated var fileSuffix: String {
        switch self {
        case .original: ""
        case .editable: ""
        case .flattened: " - Flattened Copy"
        }
    }
}

enum DocumentExporter {
    nonisolated static var exportRoot: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("Folik Exports", isDirectory: true)
    }

    nonisolated static func export(sourceURL: URL, mode: DocumentExportMode, root: URL = exportRoot) throws -> URL {
        try Task.checkCancellation()
        guard mode != .original else { return sourceURL }
        let manager = FileManager.default
        let directory = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try manager.createDirectory(at: directory, withIntermediateDirectories: true,
                                    attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        let filename = sourceURL.deletingPathExtension().lastPathComponent + mode.fileSuffix + ".pdf"
        let destination = directory.appendingPathComponent(filename)
        do {
            switch mode {
            case .original: return sourceURL
            case .editable: try manager.copyItem(at: sourceURL, to: destination)
            case .flattened: try flatten(sourceURL: sourceURL, to: destination)
            }
            try Task.checkCancellation()
            return destination
        } catch {
            try? manager.removeItem(at: directory)
            throw error
        }
    }

    nonisolated static func removeExport(at url: URL, root: URL = exportRoot) {
        let directory = url.deletingLastPathComponent().standardizedFileURL
        guard UUID(uuidString: directory.lastPathComponent) != nil,
              directory.deletingLastPathComponent() == root.standardizedFileURL,
              (try? directory.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else { return }
        try? FileManager.default.removeItem(at: directory)
    }

    /// Called once at launch; current-process shares have not been created yet.
    nonisolated static func cleanupExpired(in root: URL = exportRoot, now: Date = Date()) {
        let manager = FileManager.default
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
        guard let urls = try? manager.contentsOfDirectory(at: root, includingPropertiesForKeys: Array(keys)) else { return }
        for url in urls {
            guard let values = try? url.resourceValues(forKeys: keys), values.isSymbolicLink != true,
                  let modified = values.contentModificationDate, now.timeIntervalSince(modified) > 24 * 60 * 60 else { continue }
            let ownedDirectory = values.isDirectory == true && UUID(uuidString: url.lastPathComponent) != nil
            let legacyExport = values.isRegularFile == true && url.pathExtension.lowercased() == "pdf"
            if ownedDirectory || legacyExport { try? manager.removeItem(at: url) }
        }
    }

    nonisolated private static func flatten(sourceURL: URL, to destinationURL: URL) throws {
        guard let document = PDFDocument(url: sourceURL), document.pageCount > 0 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        guard let consumer = CGDataConsumer(url: destinationURL as CFURL) else {
            throw CocoaError(.fileWriteUnknown)
        }
        guard let context = CGContext(consumer: consumer, mediaBox: nil, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        defer { context.closePDF() }

        for pageIndex in 0..<document.pageCount {
            try Task.checkCancellation()
            guard let page = document.page(at: pageIndex) else { continue }
            let crop = page.bounds(for: .cropBox)
            let rotated = page.rotation % 180 != 0
            var outputBounds = CGRect(origin: .zero, size: rotated
                ? CGSize(width: crop.height, height: crop.width) : crop.size)
            let boundsData = NSData(bytes: &outputBounds, length: MemoryLayout<CGRect>.size)
            context.beginPDFPage([kCGPDFContextMediaBox as String: boundsData] as CFDictionary)
            // PDFPage applies crop offsets and rotation, and draws visible annotations once.
            page.draw(with: .cropBox, to: context)
            context.endPDFPage()
        }
    }

}

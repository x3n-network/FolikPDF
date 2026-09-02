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
        case .editable: " - Editable Copy"
        case .flattened: " - Flattened Copy"
        }
    }
}

enum DocumentExporter {
    nonisolated static func export(sourceURL: URL, mode: DocumentExportMode) throws -> URL {
        guard mode != .original else { return sourceURL }

        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory.appendingPathComponent("Folik Exports", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = uniqueDestination(for: sourceURL, mode: mode, in: directory, fileManager: fileManager)

        switch mode {
        case .original:
            return sourceURL
        case .editable:
            try fileManager.copyItem(at: sourceURL, to: destination)
        case .flattened:
            try flatten(sourceURL: sourceURL, to: destination)
        }
        return destination
    }

    nonisolated private static func flatten(sourceURL: URL, to destinationURL: URL) throws {
        guard let document = PDFDocument(url: sourceURL), document.pageCount > 0 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        guard let consumer = CGDataConsumer(url: destinationURL as CFURL) else {
            throw CocoaError(.fileWriteUnknown)
        }
        var firstPageBounds = document.page(at: 0)?.bounds(for: .mediaBox) ?? CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(consumer: consumer, mediaBox: &firstPageBounds, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }

        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            let pageBounds = page.bounds(for: .mediaBox)
            context.beginPDFPage([kCGPDFContextMediaBox as String: pageBounds] as CFDictionary)
            context.saveGState()
            context.translateBy(x: -pageBounds.minX, y: -pageBounds.minY)
            page.draw(with: .mediaBox, to: context)
            for annotation in page.annotations {
                annotation.draw(with: .mediaBox, in: context)
            }
            context.restoreGState()
            context.endPDFPage()
        }
        context.closePDF()
    }

    nonisolated private static func uniqueDestination(
        for sourceURL: URL,
        mode: DocumentExportMode,
        in directory: URL,
        fileManager: FileManager
    ) -> URL {
        let stem = sourceURL.deletingPathExtension().lastPathComponent
        let baseName = stem + mode.fileSuffix
        var candidate = directory.appendingPathComponent(baseName).appendingPathExtension("pdf")
        var copyNumber = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(baseName) \(copyNumber)").appendingPathExtension("pdf")
            copyNumber += 1
        }
        return candidate
    }
}

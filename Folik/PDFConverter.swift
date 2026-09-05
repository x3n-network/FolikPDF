import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UIKit

nonisolated enum PDFConversionError: LocalizedError {
    case invalidImage, tooLarge, unsupportedDocument, invalidText, emptyText, unsupportedLayout, invalidName, busy

    var errorDescription: String? {
        switch self {
        case .invalidImage: "That image couldn’t be read. Choose a JPEG, PNG, or HEIC image."
        case .tooLarge: "Choose up to 30 images, at most 20 MB each and 100 MB total, or a text document up to 5 MB."
        case .unsupportedDocument: "Choose a TXT or RTF document."
        case .invalidText: "That document couldn’t be read. Save plain text as UTF-8 or UTF-16, or choose a valid RTF file."
        case .emptyText: "That document has no text to convert."
        case .unsupportedLayout: "This document contains an attachment or formatting that can’t fit on a PDF page. Export it to PDF from its original app."
        case .invalidName: "Enter a filename of up to 120 characters without slashes or colons."
        case .busy: "Another document is being imported. Please try again when it finishes."
        }
    }
}

nonisolated enum PDFConversionInput: Sendable {
    case images([Data])
    case preparedPDF(Data)
    case text(Data, extensionName: String)
}

nonisolated enum PDFConverter {
    static let maximumImages = 30
    static let maximumImageBytes = 20 * 1024 * 1024
    static let maximumTotalImageBytes = 100 * 1024 * 1024
    static let maximumTextBytes = 5 * 1024 * 1024

    static func fileName(_ name: String) throws -> String {
        var stem = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if stem.lowercased().hasSuffix(".pdf") { stem.removeLast(4) }
        stem = stem.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stem.isEmpty, stem.count <= 120, !stem.hasPrefix("."),
              stem.rangeOfCharacter(from: CharacterSet(charactersIn: "/:\\").union(.controlCharacters)) == nil else {
            throw PDFConversionError.invalidName
        }
        return stem + ".pdf"
    }

    static func readFile(_ url: URL, maximumBytes: Int) throws -> Data {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        var coordinationError: NSError?
        var result: Result<Data, Error>?
        NSFileCoordinator().coordinate(readingItemAt: url, options: .withoutChanges, error: &coordinationError) { readableURL in
            result = Result {
                let handle = try FileHandle(forReadingFrom: readableURL)
                defer { try? handle.close() }
                let data = try handle.read(upToCount: maximumBytes + 1) ?? Data()
                guard data.count <= maximumBytes else { throw PDFConversionError.tooLarge }
                return data
            }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw CocoaError(.fileReadUnknown) }
        return try result.get()
    }

    static func image(_ data: Data, maximumPixelSize: Int = 3000) throws -> CGImage {
        guard data.count <= maximumImageBytes else { throw PDFConversionError.tooLarge }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { throw PDFConversionError.invalidImage }
        return image
    }

    static func write(_ input: PDFConversionInput, to url: URL) async throws {
        switch input {
        case .preparedPDF(let data):
            guard data.count <= 50 * 1024 * 1024 else { throw OfficeConversionError.tooLarge }
            try data.write(to: url)
        case .images(let pages):
            guard !pages.isEmpty else { throw PDFConversionError.invalidImage }
            guard pages.count <= maximumImages,
                  pages.reduce(0, { $0 + $1.count }) <= maximumTotalImageBytes,
                  pages.allSatisfy({ $0.count <= maximumImageBytes }) else { throw PDFConversionError.tooLarge }
            try await ScannedPDFWriter.write(pageImageData: pages, to: url)
        case .text(let data, let extensionName):
            try writeText(data, extensionName: extensionName, to: url)
        }
    }

    static func writeText(_ data: Data, extensionName: String, to url: URL) throws {
        guard data.count <= maximumTextBytes else { throw PDFConversionError.tooLarge }
        let text: NSAttributedString
        switch extensionName.lowercased() {
        case "txt":
            let encoding: String.Encoding = data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) ? .utf16 : .utf8
            guard let string = String(data: data, encoding: encoding) else { throw PDFConversionError.invalidText }
            text = NSAttributedString(string: string, attributes: [
                .font: CTFontCreateWithName("Helvetica" as CFString, 12, nil),
                .foregroundColor: CGColor(gray: 0, alpha: 1)
            ])
        case "rtf":
            guard data.starts(with: Array("{\\rtf".utf8)) else { throw PDFConversionError.invalidText }
            do {
                text = try NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil)
            } catch { throw PDFConversionError.invalidText }
        default: throw PDFConversionError.unsupportedDocument
        }
        guard !text.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw PDFConversionError.emptyText }
        var hasAttachments = false
        text.enumerateAttribute(.attachment, in: NSRange(location: 0, length: text.length)) { value, _, _ in
            if value != nil { hasAttachments = true }
        }
        guard !hasAttachments else { throw PDFConversionError.unsupportedLayout }
        var bounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(url as CFURL, mediaBox: &bounds, nil) else { throw CocoaError(.fileWriteUnknown) }
        defer { context.closePDF() }
        let framesetter = CTFramesetterCreateWithAttributedString(text)
        let path = CGPath(rect: bounds.insetBy(dx: 48, dy: 48), transform: nil)
        var location = 0
        var pageCount = 0
        while location < text.length {
            try Task.checkCancellation()
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: location, length: 0), path, nil)
            let visible = CTFrameGetVisibleStringRange(frame)
            guard visible.length > 0, pageCount < 1000 else { throw PDFConversionError.unsupportedLayout }
            context.beginPDFPage(nil)
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(bounds)
            context.textMatrix = .identity
            CTFrameDraw(frame, context)
            context.endPDFPage()
            location += visible.length
            pageCount += 1
        }
    }
}

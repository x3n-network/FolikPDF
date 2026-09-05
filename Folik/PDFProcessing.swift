import CoreGraphics
import Foundation
import PDFKit

nonisolated enum PDFProcessingError: LocalizedError {
    case invalid, protected, tooLarge, nothingToRecognize
    var errorDescription: String? {
        switch self {
        case .invalid: "This PDF could not be processed. Try another copy."
        case .protected: "Use an unprotected PDF copy for this operation."
        case .tooLarge: "Choose a PDF up to 100 MB and 500 pages with standard page dimensions."
        case .nothingToRecognize: "No new text was recognized. Pages with existing text or annotations were preserved."
        }
    }
}

nonisolated enum PDFProcessing {
    static let maximumBytes = 100 * 1024 * 1024
    static func document(_ data: Data) throws -> PDFDocument {
        try Task.checkCancellation()
        guard data.count <= maximumBytes else { throw PDFProcessingError.tooLarge }
        guard let pdf = PDFDocument(data: data), pdf.pageCount > 0 else { throw PDFProcessingError.invalid }
        guard !pdf.isEncrypted else { throw PDFProcessingError.protected }
        guard pdf.pageCount <= 500 else { throw PDFProcessingError.tooLarge }
        return pdf
    }
    static func bounds(_ page: CGPDFPage) throws -> CGRect {
        let box = page.getBoxRect(.cropBox)
        guard box.width.isFinite, box.height.isFinite, box.width >= 1, box.height >= 1,
              box.width <= 2880, box.height <= 2880 else { throw PDFProcessingError.tooLarge }
        let rotated = abs(page.rotationAngle % 180) == 90
        return CGRect(x: 0, y: 0, width: rotated ? box.height : box.width, height: rotated ? box.width : box.height)
    }
    static func draw(_ page: CGPDFPage, in context: CGContext, bounds: CGRect) {
        context.saveGState()
        context.clip(to: bounds)
        context.concatenate(page.getDrawingTransform(.cropBox, rect: bounds, rotate: 0, preserveAspectRatio: true))
        context.drawPDFPage(page)
        context.restoreGState()
    }
    static func bitmap(_ page: CGPDFPage, dpi: CGFloat = 200) throws -> CGImage {
        let bounds = try bounds(page)
        let scale = min(dpi / 72, 3500 / max(bounds.width, bounds.height))
        let width = max(1, Int(ceil(bounds.width * scale)))
        let height = max(1, Int(ceil(bounds.height * scale)))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { throw PDFProcessingError.invalid }
        context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: CGFloat(width) / bounds.width, y: CGFloat(height) / bounds.height)
        draw(page, in: context, bounds: bounds)
        guard let image = context.makeImage() else { throw PDFProcessingError.invalid }
        return image
    }
    static func searchable(_ data: Data, progress: @Sendable (Int, Int) async -> Void = { _, _ in }) async throws -> OfficePreview {
        let pdf = try document(data)
        var recognized = 0; var annotated = 0; var existing = 0; var empty = 0
        for index in 0..<pdf.pageCount {
            try Task.checkCancellation()
            await progress(index + 1, pdf.pageCount)
            guard let page = pdf.page(at: index), let ref = page.pageRef else { throw PDFProcessingError.invalid }
            if !(page.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { existing += 1; continue }
            if !page.annotations.isEmpty { annotated += 1; continue }
            let bounds = try bounds(ref)
            let lines = try await ScannedPDFWriter.recognizeText(in: bitmap(ref))
            try Task.checkCancellation()
            if lines.isEmpty { empty += 1; continue }
            let output = NSMutableData()
            var media = bounds
            guard let consumer = CGDataConsumer(data: output as CFMutableData),
                  let context = CGContext(consumer: consumer, mediaBox: &media, nil) else { throw PDFProcessingError.invalid }
            context.beginPDFPage(nil)
            draw(ref, in: context, bounds: bounds)
            ScannedPDFWriter.drawSearchableText(lines, imageRect: bounds, in: context)
            context.endPDFPage(); context.closePDF()
            guard let replacement = PDFDocument(data: output as Data)?.page(at: 0) else { throw PDFProcessingError.invalid }
            pdf.removePage(at: index); pdf.insert(replacement, at: index); recognized += 1
        }
        guard recognized > 0 else { throw PDFProcessingError.nothingToRecognize }
        guard let output = pdf.dataRepresentation(), output.count <= maximumBytes else { throw PDFProcessingError.tooLarge }
        return OfficePreview(data: output, warnings: ["Added text to \(recognized) pages. Preserved \(existing) pages with text and \(annotated) pages with annotations. No text recognized on \(empty) pages.", "OCR can make mistakes. Review the searchable copy. Page destinations and document outlines may change."], pageCount: pdf.pageCount,
                             recoveryNotice: "Searchable copy. Your source PDF is unchanged.")
    }
}

import CoreGraphics
import Foundation
import PDFKit

nonisolated struct RedactionArea: Identifiable, Sendable {
    let id = UUID()
    let page: Int
    /// Normalized display coordinates, origin at the top left of the rotated crop box.
    let rect: CGRect
}
nonisolated enum PDFRedactionError: LocalizedError {
    case invalidAreas
    var errorDescription: String? { "Mark at least one valid area inside a page. Up to 500 areas are supported." }
}

nonisolated enum PDFRedaction {
    static func validate(_ areas: [RedactionArea], pages: Int) throws {
        guard !areas.isEmpty, areas.count <= 500, areas.allSatisfy({ area in
            let r = area.rect
            return (0..<pages).contains(area.page) && [r.minX, r.minY, r.width, r.height].allSatisfy(\.isFinite) &&
                r.minX >= 0 && r.minY >= 0 && r.width > 0 && r.height > 0 && r.maxX <= 1 && r.maxY <= 1
        }) else { throw PDFRedactionError.invalidAreas }
    }
    static func bitmap(_ page: PDFPage, areas: [RedactionArea] = []) throws -> CGImage {
        guard let ref = page.pageRef else { throw PDFProcessingError.invalid }
        let bounds = try PDFProcessing.bounds(ref)
        let scale = min(200 / 72.0, 3500 / max(bounds.width, bounds.height))
        let width = max(1, Int(ceil(bounds.width * scale))); let height = max(1, Int(ceil(bounds.height * scale)))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { throw PDFProcessingError.invalid }
        context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.saveGState()
        context.scaleBy(x: CGFloat(width) / bounds.width, y: CGFloat(height) / bounds.height)
        context.clip(to: bounds)
        context.concatenate(ref.getDrawingTransform(.cropBox, rect: bounds, rotate: 0, preserveAspectRatio: true))
        context.drawPDFPage(ref)
        for annotation in page.annotations where annotation.shouldDisplay { annotation.draw(with: .cropBox, in: context) }
        context.restoreGState()
        // Paint in the bitmap itself, before creating any output PDF objects.
        // Expand to cover edge pixels; no original text/streams are copied.
        context.setShouldAntialias(false)
        context.setBlendMode(.copy)
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        for area in areas {
            let r = area.rect
            let pixels = CGRect(x: r.minX * CGFloat(width), y: (1 - r.maxY) * CGFloat(height),
                                width: r.width * CGFloat(width), height: r.height * CGFloat(height)).insetBy(dx: -2, dy: -2).integral
            context.fill(pixels)
        }
        guard let image = context.makeImage() else { throw PDFProcessingError.invalid }
        return image
    }
    static func redact(_ data: Data, areas: [RedactionArea], progress: @Sendable (Int, Int) async -> Void = { _, _ in }) async throws -> OfficePreview {
        let pdf = try PDFProcessing.document(data)
        try validate(areas, pages: pdf.pageCount)
        let output = NSMutableData()
        var bounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let consumer = CGDataConsumer(data: output as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &bounds, nil) else { throw PDFProcessingError.invalid }
        var closed = false
        defer { if !closed { context.closePDF() } }
        for index in 0..<pdf.pageCount {
            try Task.checkCancellation(); await progress(index + 1, pdf.pageCount)
            try autoreleasepool {
                guard let page = pdf.page(at: index), let ref = page.pageRef else { throw PDFProcessingError.invalid }
                var pageBounds = try PDFProcessing.bounds(ref)
                let image = try bitmap(page, areas: areas.filter { $0.page == index })
                let box = Data(bytes: &pageBounds, count: MemoryLayout<CGRect>.size)
                context.beginPDFPage([kCGPDFContextMediaBox as String: box] as CFDictionary)
                context.draw(image, in: pageBounds)
                context.endPDFPage()
            }
            guard output.length <= PDFProcessing.maximumBytes else { throw PDFProcessingError.tooLarge }
        }
        context.closePDF(); closed = true
        try Task.checkCancellation()
        guard output.length <= PDFProcessing.maximumBytes,
              let verified = PDFDocument(data: output as Data), verified.pageCount == pdf.pageCount else { throw PDFProcessingError.invalid }
        return OfficePreview(data: output as Data,
                             warnings: ["Marked areas were removed from rendered pixels. Every output page contains only a newly rendered image; source text, metadata, links, outlines, attachments, and editable form/annotation objects are not copied.", "Visible annotation appearances are flattened where supported. Rendering is limited to 200 dpi and 3,500 pixels per side. Review every page, including unmarked pages, before sharing."],
                             pageCount: verified.pageCount,
                             recoveryNotice: "Redacted image-only copy. Text selection and interactive features are removed. Your original still contains its original information.")
    }
}

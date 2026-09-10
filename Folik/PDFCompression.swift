import Foundation
import PDFKit

nonisolated enum PDFCompressionPreset: String, CaseIterable, Identifiable, Sendable {
    case originalResolution = "Keep Resolution"
    case screen = "Screen Optimized"
    case smaller = "Smaller File"
    var id: Self { self }
    var detail: String {
        switch self {
        case .originalResolution: "Re-encode images as JPEG without requesting downsampling."
        case .screen: "Downsample images for screen viewing."
        case .smaller: "Downsample images and use JPEG encoding. Best for sharing image-heavy PDFs."
        }
    }
}

nonisolated enum PDFCompression {
    static func compress(_ data: Data, preset: PDFCompressionPreset) throws -> OfficePreview {
        let pdf = try PDFProcessing.document(data)
        let options: [PDFDocumentWriteOption: Any] = [
            .saveImagesAsJPEGOption: preset != .screen,
            .optimizeImagesForScreenOption: preset != .originalResolution
        ]
        guard let candidate = pdf.dataRepresentation(options: options) else { throw PDFProcessingError.invalid }
        try Task.checkCancellation()
        // Never present a larger file as successful compression.
        let output = candidate.count < data.count ? candidate : data
        guard let verified = PDFDocument(data: output), verified.pageCount == pdf.pageCount else { throw PDFProcessingError.invalid }
        let before = ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
        let after = ByteCountFormatter.string(fromByteCount: Int64(output.count), countStyle: .file)
        let percent = Int((1 - Double(output.count) / Double(data.count)) * 100)
        let notice = output.count < data.count ? "\(before) → \(after) · \(percent)% smaller" : "\(before) → \(after) · Already optimized; original bytes retained."
        return OfficePreview(data: output, warnings: ["\(preset.rawValue): \(preset.detail)", "Image quality may change. Text and annotations are not intentionally flattened. Review the new copy before saving."], pageCount: verified.pageCount,
                             recoveryNotice: "Review image quality before saving. Your source PDF stays unchanged.",
                             previewTitle: "Compressed Copy", notesTitle: "Compression details", resultSummary: notice)
    }
}

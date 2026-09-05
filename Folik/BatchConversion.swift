import Foundation
import PDFKit

nonisolated struct BatchSource: Identifiable, Sendable {
    let id = UUID()
    var name: String
    let extensionName: String
    let data: Data
}
nonisolated struct BatchPDFOutput: Identifiable, Sendable {
    let id = UUID()
    let name: String
    let preview: OfficePreview
}
nonisolated enum BatchConversion {
    static let extensions = ["pdf", "docx", "odt", "doc", "pages", "txt", "rtf", "jpg", "jpeg", "png", "heic"]
    static func prepare(_ sources: [BatchSource], combined: Bool, name: String = "Combined Documents",
                        progress: @Sendable (Int, Int) async -> Void = { _, _ in }) async throws -> [BatchPDFOutput] {
        guard !sources.isEmpty, sources.count <= 20,
              sources.reduce(0, { $0 + $1.data.count }) <= PDFProcessing.maximumBytes else { throw PDFProcessingError.tooLarge }
        var outputs: [BatchPDFOutput] = []
        var total = 0
        for (index, source) in sources.enumerated() {
            try Task.checkCancellation(); await progress(index + 1, sources.count)
            _ = try PDFConverter.fileName(source.name)
            let preview = try await convert(source)
            total += preview.data.count
            guard total <= PDFProcessing.maximumBytes else { throw PDFProcessingError.tooLarge }
            outputs.append(BatchPDFOutput(name: source.name, preview: preview))
        }
        if !combined { return outputs }
        _ = try PDFConverter.fileName(name)
        let joined = PDFDocument()
        var warnings: Set<String> = ["Documents are combined in the displayed order. Document outlines and cross-document destinations may change."]
        for output in outputs {
            try Task.checkCancellation()
            let pdf = try PDFProcessing.document(output.preview.data)
            guard joined.pageCount + pdf.pageCount <= 500 else { throw PDFProcessingError.tooLarge }
            for index in 0..<pdf.pageCount {
                try Task.checkCancellation()
                guard let page = pdf.page(at: index)?.copy() as? PDFPage else { throw PDFProcessingError.invalid }
                joined.insert(page, at: joined.pageCount)
            }
            for warning in output.preview.warnings { warnings.insert(output.name + ": " + warning) }
            if let notice = output.preview.recoveryNotice { warnings.insert(output.name + ": " + notice) }
        }
        guard let data = joined.dataRepresentation(), data.count <= PDFProcessing.maximumBytes else { throw PDFProcessingError.tooLarge }
        return [BatchPDFOutput(name: name, preview: OfficePreview(data: data, warnings: warnings.sorted(), pageCount: joined.pageCount,
                                                                recoveryNotice: "Combined copy. Review conversion notes for every source document."))]
    }
    private static func convert(_ source: BatchSource) async throws -> OfficePreview {
        let ext = source.extensionName.lowercased()
        switch ext {
        case "docx", "odt", "doc", "pages": return try await OfficeDocumentEngine.preview(source.data, extensionName: ext)
        case "pdf":
            let pdf = try PDFProcessing.document(source.data)
            return OfficePreview(data: source.data, warnings: [], pageCount: pdf.pageCount)
        case "txt", "rtf", "jpg", "jpeg", "png", "heic":
            let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
            defer { try? FileManager.default.removeItem(at: file) }
            let input: PDFConversionInput = ["txt", "rtf"].contains(ext) ? .text(source.data, extensionName: ext) : .images([source.data])
            try await PDFConverter.write(input, to: file)
            let data = try Data(contentsOf: file)
            let pdf = try PDFProcessing.document(data)
            return OfficePreview(data: data, warnings: [], pageCount: pdf.pageCount)
        default: throw PDFConversionError.unsupportedDocument
        }
    }
}

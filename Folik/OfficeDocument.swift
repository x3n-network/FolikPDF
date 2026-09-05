import Foundation
import CoreGraphics

nonisolated struct OfficeTextStyle: Sendable {
    var font = "Helvetica"
    var size: CGFloat = 12
    var bold = false
    var italic = false
    var underline = false
    var strikethrough = false
    var scriptPosition = 0 // -1: subscript, 0: baseline, 1: superscript
    var link: String?
    var color = "000000"
}
nonisolated struct OfficeRun: Sendable {
    var text: String
    var style = OfficeTextStyle()
}
nonisolated struct OfficeParagraph: Sendable {
    var runs: [OfficeRun] = []
    var alignment = "left"
    var indent: CGFloat = 0
    var before: CGFloat = 0
    var after: CGFloat = 6
    var breakBefore = false
    var keepWithNext = false
}
nonisolated struct OfficeImage: Sendable {
    let data: Data
    var width: CGFloat = 0
    var height: CGFloat = 0
}
nonisolated struct OfficeCell: Sendable {
    var blocks: [OfficeBlock]
    var columnSpan = 1
}
nonisolated struct OfficeTable: Sendable {
    var rows: [[OfficeCell]]
    var columnWidths: [CGFloat] = []
}
nonisolated struct OfficeMargins: Sendable {
    var top: CGFloat = 48
    var bottom: CGFloat = 48
    var left: CGFloat = 48
    var right: CGFloat = 48
    func isValid(for size: CGSize) -> Bool {
        [top, bottom, left, right].allSatisfy { $0.isFinite && $0 >= 0 } &&
        size.width - left - right >= 100 && size.height - top - bottom >= 100
    }
}
nonisolated enum OfficeBlock: Sendable {
    case paragraph(OfficeParagraph)
    case image(OfficeImage)
    case table(OfficeTable)
    case pageBreak
}
nonisolated struct OfficeDocument: Sendable {
    var blocks: [OfficeBlock] = []
    var warnings: Set<String> = []
    var pageSize = CGSize(width: 612, height: 792)
    var margins = OfficeMargins()
}
nonisolated struct OfficePreview: Identifiable, Sendable {
    let id = UUID()
    let data: Data
    let warnings: [String]
    let pageCount: Int
    var recoveryNotice: String? = nil
}

nonisolated enum OfficeDocumentEngine {
    static func read(_ data: Data, extensionName: String) throws -> OfficeDocument {
        let document: OfficeDocument
        switch extensionName.lowercased() {
        case "docx": document = try DOCXReader(package: OfficePackage(data: data)).read()
        case "odt": document = try ODTReader(package: OfficePackage(data: data)).read()
        case "doc": document = try LegacyDOCReader.read(data)
        default: throw OfficeConversionError.unsupportedPackage
        }
        guard !document.blocks.isEmpty else { throw OfficeConversionError.emptyDocument }
        var characters = 0
        var cells = 0
        var imageBytes = 0
        func validate(_ blocks: [OfficeBlock]) throws {
            for block in blocks {
                try Task.checkCancellation()
                switch block {
                case .paragraph(let p): characters += p.runs.reduce(0) { $0 + $1.text.utf8.count }
                case .image(let image): imageBytes += image.data.count
                case .table(let rows):
                    for row in rows.rows {
                        cells += row.count
                        guard cells <= 10_000 else { throw OfficeConversionError.tooLarge }
                        for cell in row { try validate(cell.blocks) }
                    }
                case .pageBreak: break
                }
                guard characters <= 2_000_000, imageBytes <= 50 * 1024 * 1024 else { throw OfficeConversionError.tooLarge }
            }
        }
        try validate(document.blocks)
        return document
    }

    static func preview(_ data: Data, extensionName: String) async throws -> OfficePreview {
        let worker = Task.detached(priority: .userInitiated) {
            if extensionName.lowercased() == "pages" { return try PagesPDFReader.preview(data) }
            let document = try read(data, extensionName: extensionName)
            var preview = try OfficePDFRenderer.render(document)
            if extensionName.lowercased() == "doc" { preview.recoveryNotice = "Text recovery only. Original formatting and images are not included; tracked deletions may appear." }
            return preview
        }
        return try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
    }
}

import CoreGraphics
import Foundation
import PDFKit

nonisolated struct PDFPrivacyMetadata: Identifiable, Equatable, Sendable {
    let name: String
    let value: String
    var id: String { name }
}

nonisolated struct PDFPrivacyReport: Equatable, Sendable {
    let pageCount: Int
    let fileSize: Int
    let metadata: [PDFPrivacyMetadata]
    let searchablePageCount: Int
    let annotationCount: Int
    let formFieldCount: Int
    let filledFormFieldCount: Int
    let linkCount: Int
    let attachmentCount: Int
    let signatureFieldCount: Int
    let outlineItemCount: Int
    let hasEmbeddedFiles: Bool
    let hasScriptsOrAutomaticActions: Bool

    var itemCount: Int {
        metadata.count + annotationCount + formFieldCount + linkCount + attachmentCount
            + signatureFieldCount + outlineItemCount
            + (hasEmbeddedFiles ? 1 : 0) + (hasScriptsOrAutomaticActions ? 1 : 0)
    }
}

nonisolated enum PDFPrivacy {
    static func inspect(_ data: Data) throws -> PDFPrivacyReport {
        let pdf = try PDFProcessing.document(data)
        var searchablePages = 0
        var annotations = 0
        var formFields = 0
        var filledFields = 0
        var links = 0
        var attachments = 0
        var signatures = 0

        for pageIndex in 0..<pdf.pageCount {
            try Task.checkCancellation()
            guard let page = pdf.page(at: pageIndex) else { continue }
            if !(page.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                searchablePages += 1
            }
            for annotation in page.annotations {
                switch annotation.type {
                case "Widget":
                    formFields += 1
                    if annotation.widgetFieldType == .signature { signatures += 1 }
                    if let value = annotation.widgetStringValue,
                       !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        filledFields += 1
                    }
                case "Link":
                    links += 1
                case "FileAttachment":
                    attachments += 1
                case "Popup":
                    break
                default:
                    annotations += 1
                }
            }
        }

        let catalog = catalogFlags(data)
        return PDFPrivacyReport(
            pageCount: pdf.pageCount,
            fileSize: data.count,
            metadata: metadata(in: pdf),
            searchablePageCount: searchablePages,
            annotationCount: annotations,
            formFieldCount: formFields,
            filledFormFieldCount: filledFields,
            linkCount: links,
            attachmentCount: attachments,
            signatureFieldCount: signatures,
            outlineItemCount: outlineCount(pdf.outlineRoot),
            hasEmbeddedFiles: catalog.embeddedFiles || attachments > 0,
            hasScriptsOrAutomaticActions: catalog.scriptsOrActions
        )
    }

    static func sanitize(
        _ data: Data,
        progress: @Sendable (Int, Int) async -> Void = { _, _ in }
    ) async throws -> OfficePreview {
        let pdf = try PDFProcessing.document(data)
        let output = NSMutableData()
        var bounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let consumer = CGDataConsumer(data: output as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &bounds, nil) else {
            throw PDFProcessingError.invalid
        }
        var closed = false
        defer { if !closed { context.closePDF() } }

        for index in 0..<pdf.pageCount {
            try Task.checkCancellation()
            await progress(index + 1, pdf.pageCount)
            try autoreleasepool {
                guard let page = pdf.page(at: index), let reference = page.pageRef else {
                    throw PDFProcessingError.invalid
                }
                var pageBounds = try PDFProcessing.bounds(reference)
                let image = try PDFRedaction.bitmap(page)
                let mediaBox = Data(bytes: &pageBounds, count: MemoryLayout<CGRect>.size)
                context.beginPDFPage([kCGPDFContextMediaBox as String: mediaBox] as CFDictionary)
                context.draw(image, in: pageBounds)
                context.endPDFPage()
            }
            guard output.length <= PDFProcessing.maximumBytes else { throw PDFProcessingError.tooLarge }
        }

        context.closePDF()
        closed = true
        try Task.checkCancellation()
        guard output.length <= PDFProcessing.maximumBytes,
              let verified = PDFDocument(data: output as Data),
              verified.pageCount == pdf.pageCount else {
            throw PDFProcessingError.invalid
        }
        return OfficePreview(
            data: output as Data,
            warnings: [
                "Every page is rebuilt as a new image. Document metadata, selectable or hidden text, links, outlines, attachments, scripts, and editable form or annotation objects are not copied.",
                "Visible form values, signatures, and annotations are flattened where PDFKit can display them. Existing digital signatures are no longer valid in the new copy.",
                "Text selection, search, links, form editing, and accessibility text are removed. Rendering is limited to 200 dpi and 3,500 pixels per side; review every page before sharing."
            ],
            pageCount: verified.pageCount,
            recoveryNotice: "Sanitized image-only copy. Your original is unchanged and still contains its original information."
        )
    }

    private static func metadata(in pdf: PDFDocument) -> [PDFPrivacyMetadata] {
        let attributes = pdf.documentAttributes ?? [:]
        let fields: [(PDFDocumentAttribute, String)] = [
            (.titleAttribute, "Title"),
            (.authorAttribute, "Author"),
            (.subjectAttribute, "Subject"),
            (.keywordsAttribute, "Keywords"),
            (.creatorAttribute, "Creator"),
            (.producerAttribute, "Producer"),
            (.creationDateAttribute, "Created"),
            (.modificationDateAttribute, "Modified")
        ]
        return fields.compactMap { key, name in
            guard let rawValue = attributes[key] else { return nil }
            let value: String
            if let date = rawValue as? Date {
                value = date.formatted(date: .abbreviated, time: .shortened)
            } else if let values = rawValue as? [String] {
                value = values.joined(separator: ", ")
            } else {
                value = String(describing: rawValue)
            }
            guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return PDFPrivacyMetadata(name: name, value: value)
        }
    }

    private static func outlineCount(_ root: PDFOutline?) -> Int {
        guard let root else { return 0 }
        var count = 0
        var pending = (0..<root.numberOfChildren).compactMap { root.child(at: $0) }
        while let item = pending.popLast(), count < 10_000 {
            count += 1
            pending.append(contentsOf: (0..<item.numberOfChildren).compactMap { item.child(at: $0) })
        }
        return count
    }

    private static func catalogFlags(_ data: Data) -> (embeddedFiles: Bool, scriptsOrActions: Bool) {
        guard let provider = CGDataProvider(data: data as CFData),
              let document = CGPDFDocument(provider),
              let catalog = document.catalog else {
            return (false, false)
        }
        var names: CGPDFDictionaryRef?
        let hasNames = CGPDFDictionaryGetDictionary(catalog, "Names", &names)
        let embedded = hasObject(catalog, key: "AF")
            || (hasNames && names.map { hasObject($0, key: "EmbeddedFiles") } == true)
        let scripts = hasObject(catalog, key: "OpenAction")
            || hasObject(catalog, key: "AA")
            || (hasNames && names.map { hasObject($0, key: "JavaScript") } == true)
        return (embedded, scripts)
    }

    private static func hasObject(_ dictionary: CGPDFDictionaryRef, key: String) -> Bool {
        var object: CGPDFObjectRef?
        return CGPDFDictionaryGetObject(dictionary, key, &object)
    }
}

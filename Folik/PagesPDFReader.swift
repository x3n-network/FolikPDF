import CoreGraphics
import Foundation

/// Some older Pages packages contain a saved, full PDF preview. Thumbnail images
/// are intentionally not accepted: they cannot establish the full page count.
nonisolated enum PagesPDFReader {
    static func preview(_ data: Data) throws -> OfficePreview {
        let pdfData: Data
        if data.starts(with: Data("%PDF-".utf8)) { pdfData = data }
        else {
            let package = try OfficePackage(data: data)
            guard package.names.contains("QuickLook/Preview.pdf") else { throw OfficeConversionError.pagesNeedsExport }
            pdfData = try package.read("QuickLook/Preview.pdf")
        }
        try Task.checkCancellation()
        guard pdfData.count <= OfficePackage.maximumFileBytes,
              let provider = CGDataProvider(data: pdfData as CFData),
              let pdf = CGPDFDocument(provider), !pdf.isEncrypted,
              pdf.numberOfPages > 0, pdf.numberOfPages <= 500 else { throw OfficeConversionError.pagesNeedsExport }
        for index in 1...pdf.numberOfPages {
            try Task.checkCancellation()
            guard let page = pdf.page(at: index) else { throw OfficeConversionError.invalidPackage }
            let bounds = page.getBoxRect(.mediaBox)
            guard bounds.width.isFinite, bounds.height.isFinite, bounds.width > 0, bounds.height > 0,
                  bounds.width <= 14_400, bounds.height <= 14_400 else { throw OfficeConversionError.cannotLayout }
        }
        return OfficePreview(data: pdfData,
                             warnings: ["This is the PDF preview saved inside the Pages file. It may be outdated or incomplete; compare every page with the current document in Pages before saving. Pages files without a saved PDF preview must be exported from Pages."],
                             pageCount: pdf.numberOfPages,
                             recoveryNotice: "Saved Pages preview. It may be outdated or incomplete. Compare it with the current document in Pages.")
    }

    static func readFile(_ url: URL) throws -> Data {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        var coordinationError: NSError?
        var result: Result<Data, Error>?
        NSFileCoordinator().coordinate(readingItemAt: url, options: .withoutChanges, error: &coordinationError) { readable in
            result = Result {
                let properties = try readable.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard properties.isSymbolicLink != true else { throw OfficeConversionError.pagesNeedsExport }
                var source = readable
                if properties.isDirectory == true {
                    for name in ["QuickLook", "Preview.pdf"] {
                        source.appendPathComponent(name)
                        guard (try? source.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == false else { throw OfficeConversionError.pagesNeedsExport }
                    }
                }
                let handle = try FileHandle(forReadingFrom: source)
                defer { try? handle.close() }
                let data = try handle.read(upToCount: OfficePackage.maximumFileBytes + 1) ?? Data()
                guard data.count <= OfficePackage.maximumFileBytes else { throw OfficeConversionError.tooLarge }
                return data
            }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw OfficeConversionError.pagesNeedsExport }
        return try result.get()
    }
}

import PDFKit

@MainActor
enum PDFDocumentPersistence {
    static func save(_ document: PDFDocument, to url: URL) throws {
        try save(document, to: url) { original, temporary in
            _ = try FileManager.default.replaceItemAt(original, withItemAt: temporary, options: .usingNewMetadataOnly)
        }
    }

    static func save(_ document: PDFDocument, to url: URL, replace: (URL, URL) throws -> Void) throws {
        let manager = FileManager.default
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".folik-save-\(UUID().uuidString).pdf")
        defer { try? manager.removeItem(at: temporary) }
        guard document.write(to: temporary) else { throw CocoaError(.fileWriteUnknown) }
        let serialized = try Data(contentsOf: temporary)
        let repaired = PDFAcroFormRepair.repair(serialized)
        if repaired != serialized { try repaired.write(to: temporary) }
        if manager.fileExists(atPath: url.path) {
            if let protection = try manager.attributesOfItem(atPath: url.path)[.protectionKey] {
                try manager.setAttributes([.protectionKey: protection], ofItemAtPath: temporary.path)
            }
            try replace(url, temporary)
        } else {
            try manager.moveItem(at: temporary, to: url)
        }
    }
}

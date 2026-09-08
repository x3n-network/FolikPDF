import CoreGraphics
import Combine
import Foundation
#if DEBUG
import UIKit
import PDFKit
#endif

@MainActor
final class DocumentLibrary: ObservableObject {
    @Published private(set) var documents: [LibraryDocument] = []
    @Published private(set) var isImporting = false
    @Published private(set) var importStatus: String?
    @Published private(set) var organization: [String: LibraryMetadata] = [:]
    @Published private(set) var readingResume: LibraryResume?
    @Published var errorMessage: String?

    private let fileManager: FileManager
    private let documentsDirectory: URL
    private let bookmarkStore: BookmarkStore
    private let readerStateStore: ReaderStateStore

    init(
        fileManager: FileManager = .default,
        bookmarkStore: BookmarkStore? = nil,
        readerStateStore: ReaderStateStore? = nil
    ) {
        self.fileManager = fileManager
        self.bookmarkStore = bookmarkStore ?? BookmarkStore()
        self.readerStateStore = readerStateStore ?? ReaderStateStore()
        documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        refresh()
    }

    init(
        documentsDirectory: URL,
        fileManager: FileManager = .default,
        bookmarkStore: BookmarkStore? = nil,
        readerStateStore: ReaderStateStore? = nil
    ) {
        self.fileManager = fileManager
        self.documentsDirectory = documentsDirectory
        self.bookmarkStore = bookmarkStore ?? BookmarkStore()
        self.readerStateStore = readerStateStore ?? ReaderStateStore()
        refresh()
    }

    init(previewDocuments: [LibraryDocument]) {
        fileManager = .default
        bookmarkStore = BookmarkStore()
        readerStateStore = ReaderStateStore()
        documentsDirectory = URL(fileURLWithPath: "/tmp/FolikPreview", isDirectory: true)
        documents = previewDocuments
    }

    @discardableResult
    func importDocuments(at sourceURLs: [URL]) async -> [LibraryDocument] {
        guard !sourceURLs.isEmpty, !isImporting else { return [] }
        isImporting = true
        importStatus = sourceURLs.count == 1 ? "Importing PDF…" : "Importing PDFs…"
        defer {
            isImporting = false
            importStatus = nil
        }

        do {
            let destinationDirectory = documentsDirectory
            let importedURLs = try await Task.detached(priority: .userInitiated) {
                try Self.copyPDFs(sourceURLs, to: destinationDirectory)
            }.value
            refresh()
            let importedPaths = Set(importedURLs.map(\.standardizedFileURL))
            return documents.filter { importedPaths.contains($0.url.standardizedFileURL) }
        } catch {
            errorMessage = error.localizedDescription
            return []
        }
    }

    @discardableResult
    func importScannedPages(_ pageImageData: [Data], createdAt: Date = Date()) async -> LibraryDocument? {
        guard !isImporting else { return nil }
        guard !pageImageData.isEmpty else {
            errorMessage = ScannedPDFError.noPages.localizedDescription
            return nil
        }
        isImporting = true
        importStatus = "Recognizing text and creating PDF…"
        defer {
            isImporting = false
            importStatus = nil
        }

        let destinationDirectory = documentsDirectory
        let fileName = Self.scanFileName(for: createdAt)
        do {
            let destination = try await Task.detached(priority: .userInitiated) {
                let fileManager = FileManager.default
                let finalURL = Self.uniqueDestination(
                    named: fileName,
                    in: destinationDirectory,
                    fileManager: fileManager
                )
                let temporaryURL = finalURL
                    .deletingPathExtension()
                    .appendingPathExtension("partial.pdf")
                defer { try? fileManager.removeItem(at: temporaryURL) }
                try await ScannedPDFWriter.write(pageImageData: pageImageData, to: temporaryURL)
                try fileManager.moveItem(at: temporaryURL, to: finalURL)
                return finalURL
            }.value
            refresh()
            return documents.first { $0.url.standardizedFileURL == destination.standardizedFileURL }
        } catch {
            errorMessage = "Folik couldn’t create that scan. \(error.localizedDescription)"
            return nil
        }
    }

    func importConvertedPDF(_ input: PDFConversionInput, named name: String) async throws -> LibraryDocument {
        guard !isImporting else { throw PDFConversionError.busy }
        let fileName = try PDFConverter.fileName(name)
        isImporting = true
        importStatus = "Creating PDF…"
        defer {
            isImporting = false
            importStatus = nil
        }
        let directory = documentsDirectory
        let destination = try await Task.detached(priority: .userInitiated) {
            let manager = FileManager.default
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
            let destination = Self.uniqueDestination(named: fileName, in: directory, fileManager: manager)
            let temporary = directory.appendingPathComponent(".conversion-\(UUID().uuidString).pdf")
            defer { try? manager.removeItem(at: temporary) }
            try await PDFConverter.write(input, to: temporary)
            guard let provider = CGDataProvider(url: temporary as CFURL),
                  let pdf = CGPDFDocument(provider), pdf.numberOfPages > 0 else {
                throw CocoaError(.fileWriteUnknown)
            }
            try manager.moveItem(at: temporary, to: destination)
            return destination
        }.value
        refresh()
        guard let document = documents.first(where: { $0.url.standardizedFileURL == destination.standardizedFileURL }) else {
            throw CocoaError(.fileReadUnknown)
        }
        return document
    }

    func importBatchPDFs(_ outputs: [BatchPDFOutput]) async throws -> [LibraryDocument] {
        guard !isImporting else { throw PDFConversionError.busy }
        guard !outputs.isEmpty, outputs.count <= 20,
              outputs.reduce(0, { $0 + $1.preview.data.count }) <= PDFProcessing.maximumBytes else { throw PDFProcessingError.tooLarge }
        isImporting = true; importStatus = "Saving PDFs…"
        defer { isImporting = false; importStatus = nil; refresh() }
        let directory = documentsDirectory
        let worker = Task.detached {
            let manager = FileManager.default
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
            let staging = directory.appendingPathComponent(".batch-" + UUID().uuidString)
            try manager.createDirectory(at: staging, withIntermediateDirectories: true)
            defer { try? manager.removeItem(at: staging) }
            var reserved: Set<URL> = []; var moves: [(URL, URL)] = []; var created: [URL] = []
            do {
                for output in outputs {
                    try Task.checkCancellation()
                    _ = try PDFProcessing.document(output.preview.data)
                    let filename = try PDFConverter.fileName(output.name)
                    let destination = Self.uniqueDestination(named: filename, in: directory, fileManager: manager, reserved: reserved)
                    reserved.insert(destination)
                    let temporary = staging.appendingPathComponent(UUID().uuidString + ".pdf")
                    try output.preview.data.write(to: temporary, options: .atomic)
                    moves.append((temporary, destination))
                }
                for (temporary, destination) in moves {
                    try Task.checkCancellation()
                    try manager.moveItem(at: temporary, to: destination); created.append(destination)
                }
                try Task.checkCancellation()
                return created
            } catch {
                for url in created { try? manager.removeItem(at: url) }
                throw error
            }
        }
        let urls = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
        refresh()
        return urls.compactMap { url in documents.first { $0.url == url } }
    }

    private var organizationURL: URL { documentsDirectory.appendingPathComponent(".folik-library.json") }
    var folders: [String] { Array(Set(documents.map { metadata(for: $0).folder }.filter { !$0.isEmpty })).sorted() }
    var tags: [String] { Array(Set(documents.flatMap { metadata(for: $0).tags })).sorted() }
    func metadata(for document: LibraryDocument) -> LibraryMetadata { organization[document.url.lastPathComponent] ?? LibraryMetadata() }
    func organize(_ document: LibraryDocument, folder: String, tags: [String]) throws {
        try organize([document], folder: folder, tags: tags)
    }
    func organize(_ documents: [LibraryDocument], folder: String, tags: [String]) throws {
        guard !documents.isEmpty,
              documents.allSatisfy({ item in self.documents.contains(where: { $0.url == item.url }) }) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let validated = try LibraryMetadata.validated(folder: folder, tags: tags)
        var records = try LibraryOrganization.load(from: organizationURL)
        for document in documents {
            var updated = validated
            updated.isFavorite = records[document.url.lastPathComponent]?.isFavorite ?? false
            records[document.url.lastPathComponent] = updated
        }
        try LibraryOrganization.save(records, to: organizationURL)
        organization = records
    }

    func setFavorite(_ isFavorite: Bool, for documents: [LibraryDocument]) throws {
        guard !documents.isEmpty else { return }
        var records = try LibraryOrganization.load(from: organizationURL)
        for document in documents {
            guard self.documents.contains(where: { $0.url == document.url }) else { throw CocoaError(.fileNoSuchFile) }
            var metadata = records[document.url.lastPathComponent] ?? LibraryMetadata()
            metadata.isFavorite = isFavorite
            records[document.url.lastPathComponent] = metadata
        }
        try LibraryOrganization.save(records, to: organizationURL)
        organization = records
    }

    @discardableResult
    func rename(_ document: LibraryDocument, to proposedName: String) throws -> LibraryDocument {
        guard documents.contains(where: { $0.url == document.url }) else { throw CocoaError(.fileNoSuchFile) }
        let fileName = try PDFConverter.fileName(proposedName)
        let destination = documentsDirectory.appendingPathComponent(fileName)
        if destination.standardizedFileURL == document.url.standardizedFileURL { return document }
        guard !fileManager.fileExists(atPath: destination.path) else { throw LibraryOrganizationError.nameAlreadyExists }

        var records = try LibraryOrganization.load(from: organizationURL)
        let metadata = records.removeValue(forKey: document.url.lastPathComponent)
        if let metadata { records[fileName] = metadata }

        try fileManager.moveItem(at: document.url, to: destination)
        do {
            if metadata != nil { try LibraryOrganization.save(records, to: organizationURL) }
        } catch {
            try? fileManager.moveItem(at: destination, to: document.url)
            throw error
        }
        bookmarkStore.moveBookmarks(from: document.url, to: destination)
        readerStateStore.moveState(from: document.url, to: destination)
        refresh()
        guard let renamed = documents.first(where: { $0.url.standardizedFileURL == destination.standardizedFileURL }) else {
            throw CocoaError(.fileReadUnknown)
        }
        return renamed
    }

    func delete(_ document: LibraryDocument) {
        defer { refresh() }
        do {
            try fileManager.removeItem(at: document.url)
            bookmarkStore.removeBookmarks(for: document.url)
            readerStateStore.removeState(for: document.url)
            var records = try LibraryOrganization.load(from: organizationURL)
            records.removeValue(forKey: document.url.lastPathComponent)
            try LibraryOrganization.save(records, to: organizationURL)
        } catch {
            errorMessage = "Folik couldn’t remove \(document.displayName). \(error.localizedDescription)"
        }
    }

    func delete(_ documents: [LibraryDocument]) {
        for document in documents { delete(document) }
    }

    func dismissReadingResume() {
        if let readingResume { readerStateStore.dismissResume(for: readingResume.document.url) }
        readingResume = nil
    }

    func refresh() {
        do {
            try fileManager.createDirectory(at: documentsDirectory, withIntermediateDirectories: true)
            let keys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
            documents = try fileManager.contentsOfDirectory(
                at: documentsDirectory,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles]
            )
            .filter { $0.pathExtension.localizedCaseInsensitiveCompare("pdf") == .orderedSame }
            .compactMap { url in
                let values = try? url.resourceValues(forKeys: keys)
                guard values?.isRegularFile != false,
                      let provider = CGDataProvider(url: url as CFURL),
                      let pdf = CGPDFDocument(provider) else { return nil }
                return LibraryDocument(
                    url: url,
                    pageCount: pdf.numberOfPages,
                    fileSize: Int64(values?.fileSize ?? 0),
                    modifiedAt: values?.contentModificationDate ?? .distantPast
                )
            }
            .sorted { $0.modifiedAt > $1.modifiedAt }
            organization = try LibraryOrganization.load(from: organizationURL)
            readingResume = readerStateStore.mostRecent(in: documents)
        } catch {
            errorMessage = "Folik couldn’t load your library. \(error.localizedDescription)"
        }
    }

    #if DEBUG
    func prepareUITestFixture() {
        do {
            try fileManager.createDirectory(at: documentsDirectory, withIntermediateDirectories: true)
            for url in try fileManager.contentsOfDirectory(
                at: documentsDirectory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) where url.pathExtension.localizedCaseInsensitiveCompare("pdf") == .orderedSame {
                try fileManager.removeItem(at: url)
            }

            try? fileManager.removeItem(at: organizationURL)
            let fixtureURL = documentsDirectory.appendingPathComponent("Folik UI Test.pdf")
            bookmarkStore.removeBookmarks(for: fixtureURL)
            readerStateStore.removeState(for: fixtureURL)
            let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))
            try renderer.writePDF(to: fixtureURL) { context in
                for pageNumber in 1...2 {
                    context.beginPage()
                    NSString(string: "Folik searchable test page \(pageNumber)").draw(
                        at: CGPoint(x: 72, y: 96),
                        withAttributes: [.font: UIFont.systemFont(ofSize: 24, weight: .semibold)]
                    )
                }
            }
            if let document = PDFDocument(url: fixtureURL), let page = document.page(at: 0) {
                let field = PDFAnnotation(
                    bounds: CGRect(x: 72, y: 590, width: 320, height: 40),
                    forType: .widget,
                    withProperties: nil
                )
                field.widgetFieldType = .text
                field.fieldName = "Full name"
                field.widgetStringValue = ""
                field.setValue(NSNumber(value: 1 << 1), forAnnotationKey: .widgetFieldFlags)
                field.font = UIFont.systemFont(ofSize: 16)
                field.backgroundColor = .white
                field.color = .systemBlue
                let border = PDFBorder()
                border.lineWidth = 1.5
                field.border = border
                page.addAnnotation(field)
                let highlight = PDFAnnotation(
                    bounds: CGRect(x: 68, y: 680, width: 330, height: 34),
                    forType: .highlight,
                    withProperties: nil
                )
                highlight.color = FolikTheme.annotationYellow
                highlight.contents = "Searchable heading"
                page.addAnnotation(highlight)
                guard document.write(to: fixtureURL) else {
                    throw CocoaError(.fileWriteUnknown)
                }
            }
            if ProcessInfo.processInfo.arguments.contains("--ui-test-image-only") {
                let scanURL = documentsDirectory.appendingPathComponent("Scan.pdf")
                let image = UIGraphicsImageRenderer(size: CGSize(width: 612, height: 792)).image { context in
                    UIColor.white.setFill()
                    context.fill(CGRect(x: 0, y: 0, width: 612, height: 792))
                    NSString(string: "Paper invoice 4827").draw(at: CGPoint(x: 72, y: 96), withAttributes: [.font: UIFont.systemFont(ofSize: 28)])
                }
                try UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792)).writePDF(to: scanURL) { context in
                    context.beginPage()
                    image.draw(in: CGRect(x: 0, y: 0, width: 612, height: 792))
                }
            }
            if ProcessInfo.processInfo.arguments.contains("--ui-test-library-pair") {
                let secondURL = documentsDirectory.appendingPathComponent("Second.pdf")
                bookmarkStore.removeBookmarks(for: secondURL)
                readerStateStore.removeState(for: secondURL)
                try UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792)).writePDF(to: secondURL) { context in
                    context.beginPage()
                    NSString(string: "SECOND LIBRARY DOCUMENT").draw(at: CGPoint(x: 72, y: 96), withAttributes: [.font: UIFont.systemFont(ofSize: 24)])
                }
            }
            refresh()
        } catch {
            errorMessage = "Folik couldn’t prepare its UI test document. \(error.localizedDescription)"
        }
    }

    func prepareUITestScanFixture() async -> LibraryDocument? {
        let pages = [
            (CGSize(width: 600, height: 900), UIColor.systemYellow, "Scanned portrait page"),
            (CGSize(width: 900, height: 600), UIColor.systemBlue, "Scanned landscape page")
        ].map { size, color, title in
            UIGraphicsImageRenderer(size: size).jpegData(withCompressionQuality: 0.92) { context in
                color.setFill()
                context.fill(CGRect(origin: .zero, size: size))
                NSString(string: title).draw(
                    at: CGPoint(x: 48, y: 72),
                    withAttributes: [
                        .font: UIFont.systemFont(ofSize: 34, weight: .bold),
                        .foregroundColor: UIColor.black
                    ]
                )
            }
        }
        return await importScannedPages(pages, createdAt: Date(timeIntervalSince1970: 1_700_000_000))
    }
    #endif

    nonisolated private static func copyPDFs(_ sourceURLs: [URL], to directory: URL) throws -> [URL] {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        return try sourceURLs.compactMap { sourceURL in
            guard sourceURL.pathExtension.localizedCaseInsensitiveCompare("pdf") == .orderedSame else {
                return nil
            }
            let didAccess = sourceURL.startAccessingSecurityScopedResource()
            defer { if didAccess { sourceURL.stopAccessingSecurityScopedResource() } }

            if sourceURL.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL {
                return sourceURL
            }
            let destination = uniqueDestination(
                named: sourceURL.lastPathComponent,
                in: directory,
                fileManager: fileManager
            )
            try fileManager.copyItem(at: sourceURL, to: destination)
            return destination
        }
    }

    nonisolated private static func uniqueDestination(
        named fileName: String,
        in directory: URL,
        fileManager: FileManager,
        reserved: Set<URL> = []
    ) -> URL {
        let original = directory.appendingPathComponent(fileName)
        guard fileManager.fileExists(atPath: original.path) || reserved.contains(original) else { return original }

        let source = URL(fileURLWithPath: fileName)
        let stem = source.deletingPathExtension().lastPathComponent
        let ext = source.pathExtension
        var copyNumber = 2
        while true {
            let candidateName = ext.isEmpty ? "\(stem) \(copyNumber)" : "\(stem) \(copyNumber).\(ext)"
            let candidate = directory.appendingPathComponent(candidateName)
            if !fileManager.fileExists(atPath: candidate.path) && !reserved.contains(candidate) { return candidate }
            copyNumber += 1
        }
    }

    nonisolated private static func scanFileName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "Scan \(formatter.string(from: date)).pdf"
    }
}

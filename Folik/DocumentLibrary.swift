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
    @Published private(set) var recentlyDeleted: [DeletedDocument] = []
    @Published private(set) var unreadableDeletedCount = 0
    private var trash: RecentlyDeletedStore { RecentlyDeletedStore(root: documentsDirectory.appendingPathComponent(".folik-trash", isDirectory: true)) }
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
    func importSharedInbox(
        from inboxDirectory: URL? = SharedPDFInbox.defaultInboxDirectory()
    ) async -> [LibraryDocument] {
        guard let inboxDirectory, !isImporting else { return [] }
        let pending = (try? SharedPDFInbox.pendingFiles(in: inboxDirectory, fileManager: fileManager)) ?? []
        guard !pending.isEmpty else { return [] }
        isImporting = true
        importStatus = pending.count == 1 ? "Adding shared PDF…" : "Adding shared PDFs…"
        defer {
            isImporting = false
            importStatus = nil
        }

        do {
            let destinationDirectory = documentsDirectory
            let result = try await Task.detached(priority: .userInitiated) {
                try SharedPDFInbox.consume(from: inboxDirectory, into: destinationDirectory)
            }.value
            refresh()
            if !result.failedFilenames.isEmpty {
                let count = result.failedFilenames.count
                errorMessage = "Folik couldn’t add \(count) shared PDF\(count == 1 ? "" : "s"). The original shared file\(count == 1 ? " is" : "s are") still available to retry."
            }
            let importedPaths = Set(result.importedURLs.map(\.standardizedFileURL))
            return documents.filter { importedPaths.contains($0.url.standardizedFileURL) }
        } catch is CancellationError {
            return []
        } catch {
            errorMessage = "Folik couldn’t add the shared PDFs. \(error.localizedDescription)"
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
    func document(id: UUID) -> LibraryDocument? { documents.first { $0.id == id } }
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
            let existing = records[document.url.lastPathComponent]
            updated.isFavorite = existing?.isFavorite ?? false
            updated.documentID = existing?.documentID ?? document.id
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
            metadata.documentID = metadata.documentID ?? document.id
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
        var metadata = records.removeValue(forKey: document.url.lastPathComponent) ?? LibraryMetadata()
        metadata.documentID = metadata.documentID ?? document.id
        records[fileName] = metadata

        try fileManager.moveItem(at: document.url, to: destination)
        do {
            try LibraryOrganization.save(records, to: organizationURL)
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

    @discardableResult
    func duplicate(_ document: LibraryDocument) throws -> LibraryDocument {
        guard documents.contains(where: { $0.url == document.url }) else { throw CocoaError(.fileNoSuchFile) }
        let destination = Self.uniqueDestination(
            named: document.displayName + " Copy.pdf",
            in: documentsDirectory,
            fileManager: fileManager
        )
        var records = try LibraryOrganization.load(from: organizationURL)
        var metadata = records[document.url.lastPathComponent] ?? LibraryMetadata()
        metadata.documentID = UUID()
        try fileManager.copyItem(at: document.url, to: destination)
        do {
            records[destination.lastPathComponent] = metadata
            try LibraryOrganization.save(records, to: organizationURL)
        } catch {
            try? fileManager.removeItem(at: destination)
            throw error
        }
        refresh()
        guard let copy = documents.first(where: { $0.url.standardizedFileURL == destination.standardizedFileURL }) else {
            try? fileManager.removeItem(at: destination)
            throw CocoaError(.fileReadUnknown)
        }
        return copy
    }

    func delete(_ document: LibraryDocument) {
        defer { refresh() }
        do {
            let previous = try LibraryOrganization.load(from: organizationURL)
            var metadata = previous[document.url.lastPathComponent] ?? LibraryMetadata()
            metadata.documentID = metadata.documentID ?? document.id
            let record = DeletedDocument(id: UUID(), originalFilename: document.url.lastPathComponent,
                deletedAt: Date(), metadata: metadata,
                bookmarks: Array(bookmarkStore.bookmarks(for: document.url, pageCount: document.pageCount)),
                readerState: readerStateStore.snapshot(for: document.url))
            try trash.archive(record, from: document.url)
            var records = previous
            records.removeValue(forKey: record.originalFilename)
            do { try LibraryOrganization.save(records, to: organizationURL) }
            catch {
                try fileManager.moveItem(at: trash.pdf(record.id), to: document.url)
                try? trash.remove(record.id)
                throw error
            }
            bookmarkStore.removeBookmarks(for: document.url)
            readerStateStore.removeState(for: document.url)
        } catch {
            errorMessage = "Folik couldn’t move \(document.displayName) to Recently Deleted. \(error.localizedDescription)"
        }
    }

    @discardableResult
    func restoreDeleted(_ item: DeletedDocument) throws -> URL {
        defer { refresh() }
        let record = try trash.read(item.id)
        let destination = Self.uniqueDestination(named: record.originalFilename, in: documentsDirectory, fileManager: fileManager)
        let previous = try LibraryOrganization.load(from: organizationURL)
        var records = previous
        var metadata = record.metadata
        metadata.documentID = metadata.documentID ?? UUID()
        records[destination.lastPathComponent] = metadata
        // Save metadata first: an interruption after moving the PDF cannot lose its organization.
        try LibraryOrganization.save(records, to: organizationURL)
        let oldState = readerStateStore.snapshot(for: destination)
        let oldBookmarks = bookmarkStore.bookmarks(for: destination, pageCount: Int.max)
        readerStateStore.restore(record.readerState, for: destination)
        bookmarkStore.save(Set(record.bookmarks), for: destination)
        do { try fileManager.moveItem(at: trash.pdf(record.id), to: destination) }
        catch {
            readerStateStore.restore(oldState, for: destination)
            bookmarkStore.save(oldBookmarks, for: destination)
            try LibraryOrganization.save(previous, to: organizationURL)
            throw error
        }
        try? trash.remove(record.id)
        return destination
    }

    func permanentlyDelete(_ item: DeletedDocument) throws {
        defer { refresh() }
        try trash.remove(item.id)
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
            let previousIDs = Dictionary(uniqueKeysWithValues: documents.map { ($0.url.standardizedFileURL, $0.id) })
            let discovered: [LibraryDocument] = try fileManager.contentsOfDirectory(
                at: documentsDirectory,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles]
            )
            .filter { $0.pathExtension.localizedCaseInsensitiveCompare("pdf") == .orderedSame }
            .compactMap { url -> LibraryDocument? in
                let values = try? url.resourceValues(forKeys: keys)
                guard values?.isRegularFile != false,
                      let provider = CGDataProvider(url: url as CFURL),
                      let pdf = CGPDFDocument(provider) else { return nil }
                return LibraryDocument(
                    id: previousIDs[url.standardizedFileURL] ?? UUID(),
                    url: url,
                    pageCount: pdf.numberOfPages,
                    fileSize: Int64(values?.fileSize ?? 0),
                    modifiedAt: values?.contentModificationDate ?? .distantPast
                )
            }
            .sorted { $0.modifiedAt > $1.modifiedAt }
            documents = discovered
            let inventory = try trash.inventory()
            recentlyDeleted = inventory.documents
            unreadableDeletedCount = inventory.unreadable
            var records = try LibraryOrganization.load(from: organizationURL)
            let previous = records
            for archived in recentlyDeleted {
                let source = documentsDirectory.appendingPathComponent(archived.originalFilename)
                if !fileManager.fileExists(atPath: source.path) {
                    records.removeValue(forKey: archived.originalFilename)
                    bookmarkStore.removeBookmarks(for: source)
                    readerStateStore.removeState(for: source)
                }
            }
            var usedIDs: Set<UUID> = []
            documents = discovered.map { document in
                let filename = document.url.lastPathComponent
                var metadata = records[filename] ?? LibraryMetadata()
                let identifier: UUID
                if let existing = metadata.documentID, usedIDs.insert(existing).inserted {
                    identifier = existing
                } else {
                    identifier = UUID()
                    metadata.documentID = identifier
                    usedIDs.insert(identifier)
                }
                records[filename] = metadata
                return LibraryDocument(
                    id: identifier,
                    url: document.url,
                    pageCount: document.pageCount,
                    fileSize: document.fileSize,
                    modifiedAt: document.modifiedAt
                )
            }
            if records != previous { try LibraryOrganization.save(records, to: organizationURL) }
            organization = records
            readingResume = readerStateStore.mostRecent(in: documents)
        } catch {
            errorMessage = "Folik couldn’t load your library. \(error.localizedDescription)"
        }
    }

    #if DEBUG
    func prepareUITestFixture() {
        if ProcessInfo.processInfo.arguments.contains("--store-screenshots-102") {
            do { try prepareStoreScreenshots102() } catch { errorMessage = error.localizedDescription }
            return
        }
        UserDefaults.standard.set(false, forKey: "folik.libraryGridLayout")
        do {
            try fileManager.createDirectory(at: documentsDirectory, withIntermediateDirectories: true)
            for url in try fileManager.contentsOfDirectory(
                at: documentsDirectory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) where url.pathExtension.localizedCaseInsensitiveCompare("pdf") == .orderedSame {
                try fileManager.removeItem(at: url)
            }

            try? fileManager.removeItem(at: trash.root)
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
            if ProcessInfo.processInfo.arguments.contains("--ui-test-shared-inbox") {
                try prepareSharedInboxUITestFixture()
            }
            refresh()
        } catch {
            errorMessage = "Folik couldn’t prepare its UI test document. \(error.localizedDescription)"
        }
    }

    private func prepareSharedInboxUITestFixture() throws {
        guard let inbox = SharedPDFInbox.defaultInboxDirectory(fileManager: fileManager) else {
            throw SharedPDFInboxError.unavailable
        }
        try fileManager.createDirectory(at: inbox, withIntermediateDirectories: true)
        for url in try SharedPDFInbox.pendingFiles(in: inbox, fileManager: fileManager) {
            try fileManager.removeItem(at: url)
        }
        let sharedPDF = inbox.appendingPathComponent("Shared from Files.pdf")
        try UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792)).writePDF(to: sharedPDF) { context in
            context.beginPage()
            NSString(string: "Shared privately with Folik").draw(
                at: CGPoint(x: 72, y: 96),
                withAttributes: [.font: UIFont.systemFont(ofSize: 24, weight: .semibold)]
            )
        }
    }

    private func prepareStoreScreenshots102() throws {
        try fileManager.createDirectory(at: documentsDirectory, withIntermediateDirectories: true)
        for url in try fileManager.contentsOfDirectory(at: documentsDirectory, includingPropertiesForKeys: nil)
            where url.pathExtension.lowercased() == "pdf" { try fileManager.removeItem(at: url) }
        try? fileManager.removeItem(at: trash.root)
        UserDefaults.standard.set(false, forKey: "folik.libraryGridLayout")
        UserDefaults.standard.set("name", forKey: "folik.librarySortOrder")
        let samples: [(String, String, UIColor, Int)] = [
            ("Project Brief", "A considered space for creative work.", UIColor(red: 0.12, green: 0.24, blue: 0.56, alpha: 1), 4),
            ("Meeting Notes", "Good ideas. Clear next steps.", UIColor(red: 0.18, green: 0.40, blue: 0.35, alpha: 1), 2),
            ("Travel Plans", "A few days somewhere new.", UIColor(red: 0.68, green: 0.34, blue: 0.20, alpha: 1), 3),
            ("Studio Invoice", "Thoughtful work, simply documented.", UIColor(red: 0.43, green: 0.27, blue: 0.51, alpha: 1), 1)
        ]
        var metadata: [String: LibraryMetadata] = [:]
        for (name, subtitle, color, pages) in samples {
            let url = documentsDirectory.appendingPathComponent(name + ".pdf")
            bookmarkStore.removeBookmarks(for: url)
            readerStateStore.removeState(for: url)
            try UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792)).writePDF(to: url) { context in
                for page in 0..<pages {
                    context.beginPage()
                    UIColor(red: 0.97, green: 0.96, blue: 0.93, alpha: 1).setFill()
                    context.fill(CGRect(x: 0, y: 0, width: 612, height: 792))
                    color.setFill(); context.fill(CGRect(x: 0, y: 0, width: 612, height: 310))
                    func text(_ value: String, _ y: CGFloat, _ size: CGFloat, _ ink: UIColor, bold: Bool = false) {
                        (value as NSString).draw(in: CGRect(x: 48, y: y, width: 520, height: 90), withAttributes: [.font: bold ? UIFont.boldSystemFont(ofSize: size) : UIFont.systemFont(ofSize: size), .foregroundColor: ink])
                    }
                    text("HARBOR STUDIO   /   SEPTEMBER 2026", 42, 13, .white)
                    text(name, 120, 46, .white, bold: true)
                    text(subtitle, 235, 19, .white)
                    text(page == 0 ? "Overview" : "The details", 355, 25, color, bold: true)
                    text("A little planning makes room for great work.", 401, 18, .darkGray)
                    text("01    Gather inspiration and define the direction.", 471, 17, .darkGray)
                    text("02    Bring the details together in one place.", 518, 17, .darkGray)
                    text("03    Review, refine, and share the next steps.", 565, 17, .darkGray)
                    text("SAMPLE DOCUMENT                                      \(page + 1) / \(pages)", 729, 11, color)
                }
            }
            metadata[url.lastPathComponent] = LibraryMetadata(folder: name == "Travel Plans" ? "Personal" : "Studio", tags: name == "Project Brief" ? ["Planning"] : [], isFavorite: name == "Project Brief")
        }
        try LibraryOrganization.save(metadata, to: organizationURL)
        let recent = documentsDirectory.appendingPathComponent("Project Brief.pdf")
        readerStateStore.save(ReaderState(pageIndex: 1, layout: .continuous), for: recent)
        readerStateStore.markOpened(recent)
        refresh()
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

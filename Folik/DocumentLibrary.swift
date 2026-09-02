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
    @Published var errorMessage: String?

    private let fileManager: FileManager
    private let documentsDirectory: URL
    private let bookmarkStore: BookmarkStore

    init(fileManager: FileManager = .default, bookmarkStore: BookmarkStore? = nil) {
        self.fileManager = fileManager
        self.bookmarkStore = bookmarkStore ?? BookmarkStore()
        documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        refresh()
    }

    init(
        documentsDirectory: URL,
        fileManager: FileManager = .default,
        bookmarkStore: BookmarkStore? = nil
    ) {
        self.fileManager = fileManager
        self.documentsDirectory = documentsDirectory
        self.bookmarkStore = bookmarkStore ?? BookmarkStore()
        refresh()
    }

    init(previewDocuments: [LibraryDocument]) {
        fileManager = .default
        bookmarkStore = BookmarkStore()
        documentsDirectory = URL(fileURLWithPath: "/tmp/FolikPreview", isDirectory: true)
        documents = previewDocuments
    }

    @discardableResult
    func importDocuments(at sourceURLs: [URL]) async -> [LibraryDocument] {
        guard !sourceURLs.isEmpty else { return [] }
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

    func delete(_ document: LibraryDocument) {
        do {
            try fileManager.removeItem(at: document.url)
            bookmarkStore.removeBookmarks(for: document.url)
            refresh()
        } catch {
            errorMessage = "Folik couldn’t remove \(document.displayName). \(error.localizedDescription)"
        }
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

            let fixtureURL = documentsDirectory.appendingPathComponent("Folik UI Test.pdf")
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
        fileManager: FileManager
    ) -> URL {
        let original = directory.appendingPathComponent(fileName)
        guard fileManager.fileExists(atPath: original.path) else { return original }

        let source = URL(fileURLWithPath: fileName)
        let stem = source.deletingPathExtension().lastPathComponent
        let ext = source.pathExtension
        var copyNumber = 2
        while true {
            let candidateName = ext.isEmpty ? "\(stem) \(copyNumber)" : "\(stem) \(copyNumber).\(ext)"
            let candidate = directory.appendingPathComponent(candidateName)
            if !fileManager.fileExists(atPath: candidate.path) { return candidate }
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

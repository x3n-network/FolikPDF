import Combine
import PDFKit
import UIKit
import XCTest
@testable import Folik

@MainActor
private final class SimulatedStorage { var isFull = true }

@MainActor
final class Release104Tests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("Folik104-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func pdf(_ name: String, pages: [String], color: UIColor = .black) throws -> URL {
        let url = root.appendingPathComponent(name + ".pdf")
        try UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 300, height: 400)).writePDF(to: url) { context in
            for text in pages {
                context.beginPage()
                color.setFill()
                UIRectFill(CGRect(x: 20, y: 20, width: 60, height: 60))
                NSString(string: text).draw(in: CGRect(x: 20, y: 100, width: 260, height: 280), withAttributes: [.font: UIFont.systemFont(ofSize: 12)])
            }
        }
        return url
    }
    private func item(_ url: URL) throws -> LibraryDocument {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        return LibraryDocument(url: url, pageCount: try XCTUnwrap(PDFDocument(url: url)).pageCount,
                               fileSize: Int64(values.fileSize ?? 0), modifiedAt: values.contentModificationDate ?? .distantPast)
    }

    func testFormWorkingCopyCanBeRenamedAfterEditingWithoutChangingSource() async throws {
        let source = try pdf("Source", pages: ["Original form"])
        let data = try Data(contentsOf: source)
        let library = DocumentLibrary(documentsDirectory: root)
        let copy = try await library.importConvertedPDF(.preparedPDF(data), named: "Source Fillable")
        XCTAssertNotEqual(copy.url, source)
        let session = DocumentSession(item: copy)
        session.beginFormFieldPlacement(.text, label: "Name", isRequired: true)
        session.placeAnnotationAtCurrentPageCenter()
        let saved = await session.saveForSharing()
        XCTAssertTrue(saved)
        let renamed = try library.rename(copy, to: "Application")
        let reopened = DocumentSession(item: renamed)
        XCTAssertEqual(reopened.formFields.count, 1)
        XCTAssertEqual(reopened.formFields.first?.title, "Name")
        XCTAssertEqual(try Data(contentsOf: source), data)
        XCTAssertFalse(FileManager.default.fileExists(atPath: copy.url.path))
    }

    func testFailedReplacementPreservesOriginalAndRetrySavesLatestEdits() async throws {
        let url = try pdf("Recovery", pages: ["Original"])
        let original = try Data(contentsOf: url)
        let storage = SimulatedStorage()
        let session = DocumentSession(item: try item(url), annotationSaveDelay: .seconds(30)) { document, destination in
            if storage.isFull {
                try PDFDocumentPersistence.save(document, to: destination) { _, _ in throw CocoaError(.fileWriteOutOfSpace) }
            } else { try PDFDocumentPersistence.save(document, to: destination) }
        }
        session.addInkAnnotation(pageIndex: 0, points: [CGPoint(x: 20, y: 30), CGPoint(x: 80, y: 90)])
        let failed = await session.saveForSharing()
        XCTAssertFalse(failed)
        XCTAssertTrue(session.isModified)
        XCTAssertTrue(session.saveFailed)
        XCTAssertFalse(session.isSaving)
        XCTAssertEqual(try Data(contentsOf: url), original)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: root.path).contains { $0.hasPrefix(".folik-save-") })
        storage.isFull = false
        let saved = await session.saveForSharing()
        XCTAssertTrue(saved)
        XCTAssertFalse(session.saveFailed)
        XCTAssertEqual(PDFDocument(url: url)?.page(at: 0)?.annotations.count, 1)
    }

    func testRequestedSaveOutlivesReaderAndFlushesDebouncedEdits() async throws {
        let url = try pdf("Leaving", pages: ["Keep edits"])
        var session: DocumentSession? = DocumentSession(item: try item(url), annotationSaveDelay: .seconds(30))
        session?.addInkAnnotation(pageIndex: 0, points: [CGPoint(x: 20, y: 30), CGPoint(x: 80, y: 90)])
        session?.requestSave()
        session = nil
        for _ in 0..<100 {
            if PDFDocument(url: url)?.page(at: 0)?.annotations.count == 1 { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(PDFDocument(url: url)?.page(at: 0)?.annotations.count, 1)
    }

    func testCancelledConversionLeavesNoCopyOrStagingFile() async throws {
        let library = DocumentLibrary(documentsDirectory: root)
        let task = Task { try await library.importConvertedPDF(.text(Data(String(repeating: "Long text document. ", count: 5000).utf8), extensionName: "txt"), named: "Cancelled") }
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") } catch is CancellationError { }
        XCTAssertTrue(library.documents.isEmpty)
        XCTAssertFalse(library.isImporting)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: root.path).contains { $0.hasSuffix(".pdf") })
    }

    func testImageHeavyDocumentSaveBenchmark() throws {
        let source = root.appendingPathComponent("Scans.pdf")
        let bounds = CGRect(x: 0, y: 0, width: 600, height: 800)
        try UIGraphicsPDFRenderer(bounds: bounds).writePDF(to: source) { context in
            for pageIndex in 0..<60 {
                autoreleasepool {
                    // Unique photo-like pixel data prevents PDFKit from deduplicating one tiny image across all pages.
                    var state = UInt32(pageIndex + 1)
                    var pixels = [UInt8](repeating: 255, count: 400 * 600 * 4)
                    for index in pixels.indices where index % 4 != 3 {
                        state = state &* 1664525 &+ 1013904223
                        pixels[index] = UInt8(truncatingIfNeeded: state >> 24)
                    }
                    let provider = CGDataProvider(data: Data(pixels) as CFData)!
                    let cgImage = CGImage(width: 400, height: 600, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 1600,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                                          provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
                    let jpeg = UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.75)!
                    context.beginPage()
                    UIImage(data: jpeg)!.draw(in: bounds)
                }
            }
        }
        XCTAssertGreaterThan(try Data(contentsOf: source).count, 5 * 1024 * 1024)
        let session = DocumentSession(item: try item(source), annotationSaveDelay: .seconds(30))
        let start = CFAbsoluteTimeGetCurrent()
        for index in 0..<30 { session.addInkAnnotation(pageIndex: index, points: [CGPoint(x: 20, y: 30), CGPoint(x: 80, y: 90)]) }
        XCTAssertTrue(session.persistChanges())
        print("FOLIK_BENCHMARK image_heavy_save_ms=\((CFAbsoluteTimeGetCurrent() - start) * 1000) bytes=\((try Data(contentsOf: source)).count)")
        let reopened = try XCTUnwrap(PDFDocument(url: source))
        XCTAssertEqual(reopened.pageCount, 60)
        XCTAssertEqual((0..<60).reduce(0) { $0 + (reopened.page(at: $1)?.annotations.count ?? 0) }, 30)
    }

    func testDeferredPreparationMatchesSynchronousAndCanRestartAfterCancellation() async throws {
        let url = try pdf("Prepare", pages: (0..<40).map { "Page \($0)" })
        let source = try XCTUnwrap(PDFDocument(url: url))
        for index in 0..<40 {
            let field = PDFAnnotation(bounds: CGRect(x: 20, y: 30, width: 100, height: 20), forType: .widget, withProperties: nil)
            field.widgetFieldType = .text
            field.fieldName = "Name \(index)"
            source.page(at: index)?.addAnnotation(field)
            source.page(at: index)?.addAnnotation(PDFAnnotation(bounds: CGRect(x: 20, y: 80, width: 80, height: 20), forType: .square, withProperties: nil))
        }
        XCTAssertTrue(source.write(to: url))
        let synchronous = DocumentSession(item: try item(url))
        let staged = DocumentSession(item: try item(url), deferredPreparation: true)
        XCTAssertTrue(staged.isPreparingDocument)
        XCTAssertNotNil(staged.document)
        XCTAssertTrue(staged.annotations.isEmpty)
        let cancelled = Task { await staged.prepareForReading() }
        cancelled.cancel()
        await cancelled.value
        XCTAssertFalse(staged.isPreparingDocument)
        await staged.prepareForReading()
        XCTAssertFalse(staged.isPreparingDocument)
        XCTAssertEqual(staged.annotations.map(\.id), synchronous.annotations.map(\.id))
        XCTAssertEqual(staged.formFields.map(\.id), synchronous.formFields.map(\.id))
        XCTAssertEqual(staged.preparationBatchCount, 5)
    }

    func testSearchArchiveReleasesMemoryWithoutDeletingReusableIndex() async throws {
        let url = try pdf("Cache", pages: ["Reusable search words"])
        let cache = root.appendingPathComponent("Index.json")
        let index = LibrarySearchIndex(cacheURL: cache)
        let document = try item(url)
        _ = try await index.search("words", documents: [document])
        let retained = await index.retainedTextBytes
        XCTAssertGreaterThan(retained, 0)
        let originalCache = try Data(contentsOf: cache)
        await index.releaseMemory()
        let released = await index.retainedTextBytes
        XCTAssertEqual(released, 0)
        XCTAssertEqual(try Data(contentsOf: cache), originalCache)
        let restored = try await index.search("words", documents: [document])
        XCTAssertEqual(restored.hits[url]?.first?.page, 1)
    }

    func testCancellingWaitCancelsDetachedWorker() async throws {
        let worker = Task.detached { try await Task.sleep(for: .seconds(30)); return 1 }
        let waiting = Task { try await worker.cancellableValue }
        waiting.cancel()
        do { _ = try await waiting.value; XCTFail("Expected cancellation") } catch is CancellationError { }
        XCTAssertTrue(worker.isCancelled)
    }

    func testOpeningAndOCRPerformanceProbe() async throws {
        let report = try await PerformanceProbe.run()
        XCTAssertEqual(report["annotation_count"], 3000)
        XCTAssertEqual(report["ocr_pages"], 12)
    }

    func testInventoryReusesUnchangedPDFsAndDetectsReplacement() throws {
        let first = try pdf("First", pages: ["One"])
        _ = try pdf("Second", pages: ["Two"])
        let initial = try LibraryInventory.read(directory: root, previous: [])
        XCTAssertEqual(initial.parsedPDFCount, 2)
        let warm = try LibraryInventory.read(directory: root, previous: initial.documents)
        XCTAssertEqual(warm.parsedPDFCount, 0)
        XCTAssertEqual(Set(warm.documents), Set(initial.documents))
        _ = try pdf("First", pages: ["Changed", "Added"])
        let changed = try LibraryInventory.read(directory: root, previous: warm.documents)
        XCTAssertEqual(changed.parsedPDFCount, 1)
        XCTAssertEqual(changed.documents.first { $0.url == first }?.pageCount, 2)
        XCTAssertEqual(changed.documents.first { $0.url == first }?.id, initial.documents.first { $0.url == first }?.id)
    }

    func testBulkDeleteRefreshesOnceAndBackgroundRefreshPreservesIdentity() async throws {
        _ = try pdf("First", pages: ["One"])
        _ = try pdf("Second", pages: ["Two"])
        let library = DocumentLibrary(documentsDirectory: root)
        let documents = library.documents
        var publications = 0
        let token = library.$documents.dropFirst().sink { _ in publications += 1 }
        await library.refreshInBackground()
        XCTAssertEqual(library.documents, documents)
        XCTAssertEqual(publications, 0)
        XCTAssertEqual(library.lastParsedPDFCount, 0)
        let before = library.inventoryRefreshCount
        library.delete(documents)
        XCTAssertEqual(library.inventoryRefreshCount, before + 1)
        XCTAssertTrue(library.documents.isEmpty)
        XCTAssertEqual(library.recentlyDeleted.count, 2)
        XCTAssertFalse(library.isRefreshing)
        withExtendedLifetime(token) {}
    }

    func testOverlappingRefreshCannotRestoreDeletedDocument() async throws {
        _ = try pdf("First", pages: ["One"])
        let library = DocumentLibrary(documentsDirectory: root)
        let document = try XCTUnwrap(library.documents.first)
        let refresh = Task { await library.refreshInBackground() }
        await Task.yield()
        library.delete(document)
        await library.refreshInBackground()
        await refresh.value
        XCTAssertTrue(library.documents.isEmpty)
        XCTAssertEqual(library.recentlyDeleted.count, 1)
    }

    func testSearchContinuesPastCacheBudgetAndMatchesWarmResults() async throws {
        let url = try pdf("Search", pages: [String(repeating: "filler ", count: 80), "Café needle", "needle", "needle", "needle"])
        let document = try item(url)
        let bounded = LibrarySearchIndex(cacheURL: root.appendingPathComponent("bounded.json"), documentCacheLimit: 24, archiveCacheLimit: 24)
        let result = try await bounded.search("needle", documents: [document])
        XCTAssertEqual(result.matchingPageCounts[url], 4)
        XCTAssertEqual(result.hits[url]?.map(\.page), [2, 3, 4])
        let peak = await bounded.peakRetainedDocumentTextBytes
        XCTAssertLessThanOrEqual(peak, 24)
        let index = LibrarySearchIndex(cacheURL: root.appendingPathComponent("warm.json"))
        let cold = try await index.search("cafe", documents: [document])
        let warm = try await index.search("cafe", documents: [document])
        XCTAssertEqual(cold.hits[url]?.map(\.excerpt), warm.hits[url]?.map(\.excerpt))
        XCTAssertEqual(warm.hits[url]?.first?.page, 2)
        _ = try pdf("Search", pages: ["Replacement without previous terms"])
        let revised = try await index.search("needle", documents: [item(url)])
        XCTAssertTrue(revised.hits.isEmpty)
    }

    func testThumbnailCacheReusesAndInvalidatesAfterFileReplacement() async throws {
        let url = try pdf("Preview", pages: ["Before"], color: .red)
        let cache = PDFThumbnailCache()
        let request = PDFThumbnailRequest(url: url, page: 0, width: 120, height: 160, revision: "same")
        let first = try await cache.image(for: request)
        let second = try await cache.image(for: request)
        XCTAssertTrue(first === second)
        _ = try pdf("Preview", pages: ["After", "Another page"], color: .blue)
        let changed = try await cache.image(for: request)
        XCTAssertNotNil(changed)
        XCTAssertFalse(first === changed)
        XCTAssertNotEqual(first?.image.dataProvider?.data as Data?, changed?.image.dataProvider?.data as Data?)
        let count = await cache.renderCount
        XCTAssertEqual(count, 2)
        let invalid = try await cache.image(for: PDFThumbnailRequest(url: url, page: 20, width: 120, height: 160, revision: "same"))
        XCTAssertNil(invalid)
        await cache.removeAll()
        let reloaded = try await cache.image(for: request)
        XCTAssertFalse(changed === reloaded)
    }

    func testDebouncedEditsSaveAfterIdleAndExplicitShareFlushesLatest() async throws {
        let url = try pdf("Drawing", pages: ["Draw here"])
        let session = DocumentSession(item: try item(url), annotationSaveDelay: .milliseconds(30))
        for index in 0..<5 {
            session.addInkAnnotation(pageIndex: 0, points: [CGPoint(x: 20, y: 30 + index), CGPoint(x: 80, y: 60 + index)])
        }
        XCTAssertEqual(session.successfulSaveCount, 0)
        for _ in 0..<100 where session.successfulSaveCount == 0 { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(session.successfulSaveCount, 1)
        session.addInkAnnotation(pageIndex: 0, points: [CGPoint(x: 20, y: 40), CGPoint(x: 80, y: 90)])
        let exported = try await session.prepareShare(mode: .editable)
        defer { DocumentExporter.removeExport(at: exported) }
        XCTAssertEqual(PDFDocument(url: exported)?.page(at: 0)?.annotations.count, 6)
        XCTAssertEqual(session.successfulSaveCount, 2)
        XCTAssertFalse(session.isModified)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: root.path).contains { $0.hasPrefix(".folik-save-") })
    }

    func testExportCleanupIsolatedFromOriginalAndOtherShares() throws {
        let source = try pdf("My Document", pages: ["Keep original"])
        let exportRoot = root.appendingPathComponent("Exports")
        let first = try DocumentExporter.export(sourceURL: source, mode: .editable, root: exportRoot)
        let second = try DocumentExporter.export(sourceURL: source, mode: .editable, root: exportRoot)
        XCTAssertEqual(first.lastPathComponent, "My Document.pdf")
        XCTAssertNotEqual(first, second)
        DocumentExporter.removeExport(at: source, root: exportRoot)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        DocumentExporter.removeExport(at: first, root: exportRoot)
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.deletingLastPathComponent().path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
        let unknown = exportRoot.appendingPathComponent("Keep Me")
        try FileManager.default.createDirectory(at: unknown, withIntermediateDirectories: true)
        let old = Date().addingTimeInterval(-172800)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: unknown.path)
        DocumentExporter.cleanupExpired(in: exportRoot)
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: second.deletingLastPathComponent().path)
        DocumentExporter.cleanupExpired(in: exportRoot)
        XCTAssertFalse(FileManager.default.fileExists(atPath: second.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unknown.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        let before = try FileManager.default.contentsOfDirectory(atPath: exportRoot.path)
        XCTAssertThrowsError(try DocumentExporter.export(sourceURL: root.appendingPathComponent("Missing.pdf"), mode: .editable, root: exportRoot))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: exportRoot.path), before)
    }
}

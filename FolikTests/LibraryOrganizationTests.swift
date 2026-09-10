import PDFKit
import UIKit
import XCTest
@testable import Folik

@MainActor
final class LibraryOrganizationTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    private func write(_ text: String, to url: URL) throws {
        try UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792)).writePDF(to: url) { c in
            c.beginPage(); c.beginPage()
            (text as NSString).draw(at: CGPoint(x: 50, y: 50), withAttributes: [.font: UIFont.systemFont(ofSize: 20)])
        }
    }
    func testOrganizationPersistsAndDeletionRemovesMetadata() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("Example.pdf"); try write("Example", to: url)
        let source = try Data(contentsOf: url)
        let library = DocumentLibrary(documentsDirectory: root)
        let item = try XCTUnwrap(library.documents.first)
        try library.organize(item, folder: " Work ", tags: ["receipt", "Receipt", "2026"])
        let reopened = DocumentLibrary(documentsDirectory: root)
        XCTAssertEqual(reopened.metadata(for: item).folder, "Work")
        XCTAssertEqual(reopened.metadata(for: item).tags.count, 2)
        XCTAssertEqual(try Data(contentsOf: url), source)
        reopened.delete(item)
        XCTAssertTrue(reopened.documents.isEmpty)
        XCTAssertTrue(try LibraryOrganization.load(from: root.appendingPathComponent(".folik-library.json")).isEmpty)
    }
    func testCorruptOrganizationIsNotOverwrittenAndLabelsAreBounded() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        try write("Example", to: root.appendingPathComponent("Example.pdf"))
        let store = root.appendingPathComponent(".folik-library.json")
        let invalid = Data("broken json".utf8); try invalid.write(to: store)
        let library = DocumentLibrary(documentsDirectory: root)
        XCTAssertThrowsError(try library.organize(XCTUnwrap(library.documents.first), folder: "Work", tags: []))
        XCTAssertEqual(try Data(contentsOf: store), invalid)
        XCTAssertThrowsError(try LibraryMetadata.validated(folder: String(repeating: "a", count: 81), tags: []))
    }
    func testLegacyOrganizationWithoutFavoriteStillLoads() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("Example.pdf"); try write("Example", to: url)
        let store = root.appendingPathComponent(".folik-library.json")
        try Data(#"{"Example.pdf":{"folder":"Work","tags":["2026"]}}"#.utf8).write(to: store)

        let library = DocumentLibrary(documentsDirectory: root)
        let metadata = library.metadata(for: try XCTUnwrap(library.documents.first))

        XCTAssertEqual(metadata.folder, "Work")
        XCTAssertEqual(metadata.tags, ["2026"])
        XCTAssertFalse(metadata.isFavorite)
    }

    func testBulkOrganizationPreservesFavorite() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        try write("First", to: root.appendingPathComponent("First.pdf"))
        try write("Second", to: root.appendingPathComponent("Second.pdf"))
        let library = DocumentLibrary(documentsDirectory: root)
        try library.setFavorite(true, for: [try XCTUnwrap(library.documents.first)])

        try library.organize(library.documents, folder: "Work", tags: ["review"])

        XCTAssertTrue(library.documents.allSatisfy { library.metadata(for: $0).folder == "Work" })
        XCTAssertEqual(library.documents.filter { library.metadata(for: $0).isFavorite }.count, 1)
    }
    func testSearchFindsPageAndDiacriticsAndDoesNotReuseStaleText() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("Unrelated filename.pdf")
        try write("Café invoice 4827", to: url)
        let library = DocumentLibrary(documentsDirectory: root)
        let result = try LibrarySearch.search("cafe", documents: library.documents)
        XCTAssertEqual(result.hits[url]?.first?.page, 2)
        XCTAssertTrue(result.hits[url]?.first?.excerpt.contains("4827") == true)
        XCTAssertEqual(result.matchingPageCounts[url], 1)
        try write("Replacement text", to: url)
        XCTAssertTrue(try LibrarySearch.search("4827", documents: library.documents).hits.isEmpty)
    }

    func testPersistentSearchIndexInvalidatesChangedFiles() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("Project.pdf")
        try write("needle first", to: url)
        let library = DocumentLibrary(documentsDirectory: root)
        let cache = root.appendingPathComponent("search-index.json")
        let index = LibrarySearchIndex(cacheURL: cache)

        let first = try await index.search("needle", documents: library.documents)
        XCTAssertEqual(first.hits[url]?.first?.page, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: cache.path))

        try write("replacement", to: url)
        let refreshed = DocumentLibrary(documentsDirectory: root)
        let second = try await index.search("needle", documents: refreshed.documents)
        XCTAssertTrue(second.hits.isEmpty)
    }
    func testSearchIdentifiesPDFsWithoutTextSeparatelyFromNoMatches() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let textURL = root.appendingPathComponent("Text.pdf")
        let scanURL = root.appendingPathComponent("Scan.pdf")
        try write("A document with selectable text", to: textURL)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 200)).image { c in
            UIColor.white.setFill(); c.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
            ("An image" as NSString).draw(at: CGPoint(x: 20, y: 20), withAttributes: [.font: UIFont.systemFont(ofSize: 20)])
        }
        try UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 200, height: 200)).writePDF(to: scanURL) { c in
            c.beginPage(); image.draw(at: .zero)
        }
        let original = try Data(contentsOf: scanURL)
        let result = try LibrarySearch.search("not present", documents: DocumentLibrary(documentsDirectory: root).documents)
        XCTAssertTrue(result.hits.isEmpty)
        XCTAssertEqual(result.noSearchableText, [scanURL])
        XCTAssertEqual(result.skipped, 0)
        XCTAssertEqual(try Data(contentsOf: scanURL), original)
    }

    func testSearchCancellationPropagates() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        try write("Example", to: root.appendingPathComponent("Example.pdf"))
        let documents = DocumentLibrary(documentsDirectory: root).documents
        let task = Task { try Task.checkCancellation(); return try LibrarySearch.search("Example", documents: documents) }
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancellation ignored") } catch { XCTAssertTrue(error is CancellationError) }
    }
}

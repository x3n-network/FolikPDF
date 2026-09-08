import UIKit
import XCTest
@testable import Folik

@MainActor
final class RecentlyDeletedTests: XCTestCase {
    func testRecoveryPreservesBytesOrganizationAndReadingStateAcrossRelaunchAndCollision() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
        let bookmarks = BookmarkStore(defaults: defaults)
        let states = ReaderStateStore(defaults: defaults)
        let source = root.appendingPathComponent("Example.pdf")
        try UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 100, height: 100)).writePDF(to: source) { c in c.beginPage(); c.beginPage() }
        let original = try Data(contentsOf: source)
        let library = DocumentLibrary(documentsDirectory: root, bookmarkStore: bookmarks, readerStateStore: states)
        let document = try XCTUnwrap(library.documents.first)
        try library.organize(document, folder: "Work", tags: ["receipt"])
        try library.setFavorite(true, for: [document])
        bookmarks.save([1], for: source)
        states.save(ReaderState(pageIndex: 1, layout: .continuous), for: source)
        states.markOpened(source)
        let snapshot = states.snapshot(for: source)
        library.delete(document)
        XCTAssertNil(library.errorMessage)
        XCTAssertTrue(library.documents.isEmpty)
        XCTAssertNil(states.snapshot(for: source))
        let reopened = DocumentLibrary(documentsDirectory: root, bookmarkStore: bookmarks, readerStateStore: states)
        let archived = try XCTUnwrap(reopened.recentlyDeleted.first)
        try original.write(to: source)
        let restored = try reopened.restoreDeleted(archived)
        XCTAssertNotEqual(restored, source)
        XCTAssertEqual(try Data(contentsOf: restored), original)
        XCTAssertEqual(try Data(contentsOf: source), original)
        XCTAssertEqual(states.snapshot(for: restored), snapshot)
        XCTAssertEqual(bookmarks.bookmarks(for: restored, pageCount: 2), [1])
        let item = try XCTUnwrap(reopened.documents.first { $0.url == restored })
        XCTAssertEqual(reopened.metadata(for: item), LibraryMetadata(folder: "Work", tags: ["receipt"], isFavorite: true))
        XCTAssertTrue(reopened.recentlyDeleted.isEmpty)
        reopened.delete(item)
        try reopened.permanentlyDelete(XCTUnwrap(reopened.recentlyDeleted.first))
        XCTAssertTrue(reopened.recentlyDeleted.isEmpty)
        XCTAssertEqual(try Data(contentsOf: source), original)
    }

    func testCorruptOrganizationBlocksDeleteAndRestoreWithoutLosingPDF() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Example.pdf")
        try UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 100, height: 100)).writePDF(to: source) { $0.beginPage() }
        let library = DocumentLibrary(documentsDirectory: root)
        let item = try XCTUnwrap(library.documents.first)
        let metadata = root.appendingPathComponent(".folik-library.json")
        try Data("invalid".utf8).write(to: metadata)
        library.delete(item)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertTrue(library.recentlyDeleted.isEmpty)
        try LibraryOrganization.save([:], to: metadata)
        library.delete(item)
        let archived = try XCTUnwrap(library.recentlyDeleted.first)
        try Data("invalid".utf8).write(to: metadata)
        XCTAssertThrowsError(try library.restoreDeleted(archived))
        XCTAssertEqual(library.recentlyDeleted.count, 1)
        let trash = RecentlyDeletedStore(root: root.appendingPathComponent(".folik-trash"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: trash.pdf(archived.id).path))
        try Data("invalid".utf8).write(to: trash.package(archived.id).appendingPathComponent("record.json"))
        let inventory = try trash.inventory()
        XCTAssertEqual(inventory.unreadable, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: trash.pdf(archived.id).path))
    }
}

import XCTest
import UIKit
@testable import Folik

private enum SharedInboxPDFTestFixture {
    static func write(to url: URL, pages: [String]) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))
        try renderer.writePDF(to: url) { context in
            for page in pages {
                context.beginPage()
                page.draw(
                    at: CGPoint(x: 72, y: 72),
                    withAttributes: [.font: UIFont.systemFont(ofSize: 18)]
                )
            }
        }
    }
}

@MainActor
final class SharedPDFInboxTests: XCTestCase {
    private var root: URL!
    private var sources: URL!
    private var inbox: URL!
    private var library: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("FolikShareTests-\(UUID().uuidString)")
        sources = root.appendingPathComponent("Sources")
        inbox = root.appendingPathComponent("Inbox")
        library = root.appendingPathComponent("Library")
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root { try? FileManager.default.removeItem(at: root) }
    }

    func testEnqueueAndConsumeMoveValidPDFsWithoutChangingBytes() throws {
        let first = sources.appendingPathComponent("Contract.pdf")
        let second = sources.appendingPathComponent("Receipt.pdf")
        try SharedInboxPDFTestFixture.write(to: first, pages: ["Contract"])
        try SharedInboxPDFTestFixture.write(to: second, pages: ["Receipt"])
        let expected = try Data(contentsOf: first)

        let queued = try SharedPDFInbox.enqueue([first, second], into: inbox)
        let result = try SharedPDFInbox.consume(from: inbox, into: library)

        XCTAssertEqual(queued.count, 2)
        XCTAssertEqual(result.importedURLs.map(\.lastPathComponent), ["Contract.pdf", "Receipt.pdf"])
        XCTAssertTrue(result.failedFilenames.isEmpty)
        XCTAssertEqual(try Data(contentsOf: library.appendingPathComponent("Contract.pdf")), expected)
        XCTAssertTrue(try SharedPDFInbox.pendingFiles(in: inbox).isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.path), "The source must remain unchanged")
    }

    func testDuplicateNamesStayStableAcrossQueueAndLibraryCollisions() throws {
        let source = sources.appendingPathComponent("Report.pdf")
        try SharedInboxPDFTestFixture.write(to: source, pages: ["Report"])
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        try SharedInboxPDFTestFixture.write(to: library.appendingPathComponent("Report.pdf"), pages: ["Existing"])

        _ = try SharedPDFInbox.enqueue([source], into: inbox)
        _ = try SharedPDFInbox.enqueue([source], into: inbox)
        let result = try SharedPDFInbox.consume(from: inbox, into: library)

        XCTAssertEqual(Set(result.importedURLs.map(\.lastPathComponent)), ["Report 2.pdf", "Report 3.pdf"])
    }

    func testValidationRejectsNonPDFAndPreservesExistingQueue() throws {
        let valid = sources.appendingPathComponent("Valid.pdf")
        let invalid = sources.appendingPathComponent("Not really.pdf")
        try SharedInboxPDFTestFixture.write(to: valid, pages: ["Valid"])
        try Data("not a pdf".utf8).write(to: invalid)
        _ = try SharedPDFInbox.enqueue([valid], into: inbox)

        XCTAssertThrowsError(try SharedPDFInbox.enqueue([invalid], into: inbox)) { error in
            XCTAssertEqual(error as? SharedPDFInboxError, .invalidPDF("Not really.pdf"))
        }
        XCTAssertEqual(try SharedPDFInbox.pendingFiles(in: inbox).map(\.lastPathComponent), ["Valid.pdf"])
    }

    func testDocumentLibraryConsumesTheSharedInboxAndKeepsUnreadableFilesForRetry() async throws {
        let valid = sources.appendingPathComponent("Shared Contract.pdf")
        try SharedInboxPDFTestFixture.write(to: valid, pages: ["Shared Contract"])
        _ = try SharedPDFInbox.enqueue([valid], into: inbox)
        try Data("broken".utf8).write(to: inbox.appendingPathComponent("Broken.pdf"))
        let documentLibrary = DocumentLibrary(documentsDirectory: library)

        let imported = await documentLibrary.importSharedInbox(from: inbox)

        XCTAssertEqual(imported.map(\.displayName), ["Shared Contract"])
        XCTAssertEqual(documentLibrary.documents.map(\.displayName), ["Shared Contract"])
        XCTAssertEqual(try SharedPDFInbox.pendingFiles(in: inbox).map(\.lastPathComponent), ["Broken.pdf"])
        XCTAssertEqual(
            documentLibrary.errorMessage,
            "Folik couldn’t add 1 shared PDF. The original shared file is still available to retry."
        )
    }

    func testLimitsAndCancellationAreEnforced() async throws {
        XCTAssertThrowsError(try SharedPDFInbox.validate([])) { error in
            XCTAssertEqual(error as? SharedPDFInboxError, .noPDFs)
        }
        let urls = (0...SharedPDFInbox.maximumFileCount).map {
            sources.appendingPathComponent("\($0).pdf")
        }
        XCTAssertThrowsError(try SharedPDFInbox.validate(urls)) { error in
            XCTAssertEqual(error as? SharedPDFInboxError, .tooManyFiles)
        }

        let source = sources.appendingPathComponent("Cancelled.pdf")
        try SharedInboxPDFTestFixture.write(to: source, pages: ["Cancelled"])
        let task = Task {
            try Task.checkCancellation()
            return try SharedPDFInbox.enqueue([source], into: inbox)
        }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("A cancelled enqueue should not succeed")
        } catch is CancellationError {
            // Expected.
        }
        catch {
            XCTFail("Expected CancellationError, received \(error)")
        }
    }
}

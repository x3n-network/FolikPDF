import PDFKit
import UIKit
import XCTest
@testable import Folik

@MainActor
final class PDFComparisonTests: XCTestCase {
    private func pdf(_ pages: [String]) -> Data {
        UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792)).pdfData { context in
            for text in pages {
                context.beginPage()
                (text as NSString).draw(
                    at: CGPoint(x: 72, y: 96),
                    withAttributes: [.font: UIFont.systemFont(ofSize: 22), .foregroundColor: UIColor.black]
                )
            }
        }
    }

    func testInsertionKeepsUnchangedPagesAligned() throws {
        let report = try PDFComparison.compare(
            pdf(["Cover", "Terms", "Signature page"]),
            pdf(["Cover", "New disclosure", "Terms", "Signature page"])
        )
        XCTAssertEqual(report.unchangedPageCount, 3)
        XCTAssertEqual(report.addedCount, 1)
        XCTAssertEqual(report.removedCount, 0)
        XCTAssertEqual(report.modifiedCount, 0)
        XCTAssertEqual(report.changes.first?.revisedPage, 2)
        XCTAssertEqual(report.changes.first?.revisedExcerpt, "New disclosure")
    }

    func testChangedAndRemovedPagesAreReportedWithBeforeAfterExcerpts() throws {
        let report = try PDFComparison.compare(
            pdf(["Cover", "Amount due 100 dollars", "Appendix", "Final page"]),
            pdf(["Cover", "Amount due 250 dollars", "Final page"])
        )
        XCTAssertEqual(report.unchangedPageCount, 2)
        XCTAssertEqual(report.modifiedCount, 1)
        XCTAssertEqual(report.removedCount, 1)
        let changed = try XCTUnwrap(report.changes.first { $0.kind == .modified })
        XCTAssertEqual(changed.originalPage, 2)
        XCTAssertEqual(changed.revisedPage, 2)
        XCTAssertTrue(changed.originalExcerpt?.contains("100") == true)
        XCTAssertTrue(changed.revisedExcerpt?.contains("250") == true)
        XCTAssertEqual(report.changes.first { $0.kind == .removed }?.originalPage, 3)
    }

    func testWhitespaceOnlyDifferencesAreIgnored() throws {
        let report = try PDFComparison.compare(pdf(["Same   words\nnew line"]), pdf(["Same words new line"]))
        XCTAssertTrue(report.isIdentical)
        XCTAssertTrue(report.changes.isEmpty)
    }

    func testImageOnlyAndProtectedDocumentsAreRejected() throws {
        let blank = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792)).pdfData { $0.beginPage() }
        XCTAssertThrowsError(try PDFComparison.compare(blank, blank)) { error in
            XCTAssertEqual(error as? PDFComparisonError, .noSearchableText)
        }
        let protected = try PDFProtection.protect(pdf(["Locked"]), password: "secret12")
        XCTAssertThrowsError(try PDFComparison.compare(protected.data, pdf(["Other"]))) { error in
            XCTAssertEqual(error as? PDFProcessingError, .protected)
        }
    }

    func testComparisonHonorsCancellation() async throws {
        let task = Task { try PDFComparison.compare(pdf(["One"]), pdf(["Two"])) }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Cancellation ignored")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }
}

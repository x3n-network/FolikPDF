import PDFKit
import UIKit
import XCTest
@testable import Folik

@MainActor
final class PDFProcessingTests: XCTestCase {
    private func scan() throws -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1000, height: 1300))
        let image = renderer.image { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 1000, height: 1300))
            ("Searchable invoice 4827" as NSString).draw(at: CGPoint(x: 90, y: 150), withAttributes: [.font: UIFont.systemFont(ofSize: 44), .foregroundColor: UIColor.black])
        }
        let pdf = PDFDocument(); pdf.insert(try XCTUnwrap(PDFPage(image: image)), at: 0)
        return try XCTUnwrap(pdf.dataRepresentation())
    }
    func testOCRAddsTextPreservesPageSizeAndOriginal() async throws {
        let source = try scan(); let original = source
        let input = try XCTUnwrap(PDFDocument(data: source))
        let result = try await PDFProcessing.searchable(source)
        let pdf = try XCTUnwrap(PDFDocument(data: result.data))
        XCTAssertEqual(source, original)
        XCTAssertEqual(pdf.pageCount, 1)
        XCTAssertTrue(pdf.string?.contains("4827") == true)
        XCTAssertEqual(pdf.page(at: 0)?.bounds(for: .mediaBox).size, input.page(at: 0)?.bounds(for: .mediaBox).size)
    }
    func testMixedDocumentPreservesExistingTextAndAnnotations() async throws {
        let source = try XCTUnwrap(PDFDocument(data: scan()))
        let text = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792)).pdfData { c in
            c.beginPage(); ("EXISTING TEXT" as NSString).draw(at: CGPoint(x: 72, y: 72), withAttributes: [.font: UIFont.systemFont(ofSize: 20)])
        }
        source.insert(try XCTUnwrap(PDFDocument(data: text)?.page(at: 0)), at: 1)
        let annotated = try XCTUnwrap(PDFDocument(data: scan())?.page(at: 0))
        let note = PDFAnnotation(bounds: CGRect(x: 40, y: 40, width: 30, height: 30), forType: .text, withProperties: nil)
        note.contents = "Keep this note"; annotated.addAnnotation(note); source.insert(annotated, at: 2)
        let result = try await PDFProcessing.searchable(XCTUnwrap(source.dataRepresentation()))
        let pdf = try XCTUnwrap(PDFDocument(data: result.data))
        XCTAssertEqual(pdf.pageCount, 3)
        XCTAssertTrue(pdf.page(at: 1)?.string?.contains("EXISTING TEXT") == true)
        XCTAssertEqual(pdf.page(at: 2)?.annotations.first?.contents, "Keep this note")
        XCTAssertTrue(result.warnings.contains { $0.contains("1 pages with annotations") })
    }
    func testOCRCancellationAndInvalidInput() async throws {
        let data = try scan()
        let task = Task { try await PDFProcessing.searchable(data) }
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancellation ignored") } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertThrowsError(try PDFProcessing.document(Data("invalid".utf8)))
    }
    func testRotatedPageHasCorrectOutputOrientation() async throws {
        let pdf = try XCTUnwrap(PDFDocument(data: scan())); pdf.page(at: 0)?.rotation = 90
        let result = try await PDFProcessing.searchable(XCTUnwrap(pdf.dataRepresentation()))
        let output = try XCTUnwrap(PDFDocument(data: result.data)?.page(at: 0))
        XCTAssertGreaterThan(output.bounds(for: .mediaBox).width, output.bounds(for: .mediaBox).height)
        XCTAssertTrue(output.string?.contains("4827") == true)
    }
}

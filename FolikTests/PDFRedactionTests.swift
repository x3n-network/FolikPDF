import PDFKit
import UIKit
import XCTest
@testable import Folik

@MainActor
final class PDFRedactionTests: XCTestCase {
    private func fixture() throws -> Data {
        let data = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792)).pdfData { c in
            c.beginPage()
            ("SECRET ACCOUNT 4827" as NSString).draw(at: CGPoint(x: 72, y: 72), withAttributes: [.font: UIFont.systemFont(ofSize: 24), .foregroundColor: UIColor.black])
            ("PUBLIC INFORMATION" as NSString).draw(at: CGPoint(x: 72, y: 600), withAttributes: [.font: UIFont.systemFont(ofSize: 24), .foregroundColor: UIColor.black])
        }
        let pdf = try XCTUnwrap(PDFDocument(data: data))
        pdf.documentAttributes = [PDFDocumentAttribute.authorAttribute: "SECRET AUTHOR", PDFDocumentAttribute.titleAttribute: "SECRET TITLE"]
        let annotation = PDFAnnotation(bounds: CGRect(x: 72, y: 650, width: 200, height: 30), forType: .widget, withProperties: nil)
        annotation.widgetFieldType = .text; annotation.fieldName = "SECRET FIELD"; annotation.widgetStringValue = "SECRET VALUE"
        pdf.page(at: 0)?.addAnnotation(annotation)
        let outline = PDFOutline(); let child = PDFOutline(); child.label = "SECRET OUTLINE"; outline.insertChild(child, at: 0); pdf.outlineRoot = outline
        return try XCTUnwrap(pdf.dataRepresentation())
    }
    func testRedactionRemovesTextMetadataFormsAndOutlineObjects() async throws {
        let input = try fixture(); let original = input
        let result = try await PDFRedaction.redact(input, areas: [RedactionArea(page: 0, rect: CGRect(x: 0, y: 0, width: 1, height: 0.35))])
        let pdf = try XCTUnwrap(PDFDocument(data: result.data)); let page = try XCTUnwrap(pdf.page(at: 0))
        XCTAssertEqual(input, original); XCTAssertEqual(pdf.pageCount, 1)
        XCTAssertTrue((pdf.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        XCTAssertTrue(page.annotations.isEmpty); XCTAssertNil(pdf.outlineRoot)
        XCTAssertNotEqual(pdf.documentAttributes?[PDFDocumentAttribute.authorAttribute] as? String, "SECRET AUTHOR")
        let cg = try XCTUnwrap(CGPDFDocument(CGDataProvider(data: result.data as CFData)!))
        let catalog = try XCTUnwrap(cg.catalog)
        for key in ["AcroForm", "Names", "Outlines", "Metadata"] {
            var object: CGPDFObjectRef?
            XCTAssertFalse(CGPDFDictionaryGetObject(catalog, key, &object), key)
        }
        var resources: CGPDFDictionaryRef?
        XCTAssertTrue(CGPDFDictionaryGetDictionary(try XCTUnwrap(XCTUnwrap(cg.page(at: 1)).dictionary), "Resources", &resources))
        var fonts: CGPDFDictionaryRef?
        XCTAssertFalse(CGPDFDictionaryGetDictionary(try XCTUnwrap(resources), "Font", &fonts))
        let bitmap = try PDFProcessing.bitmap(XCTUnwrap(page.pageRef))
        let lines = try await ScannedPDFWriter.recognizeText(in: bitmap).map(\.text).joined(separator: " ")
        XCTAssertFalse(lines.contains("SECRET")); XCTAssertFalse(lines.contains("4827"))
        XCTAssertTrue(lines.contains("PUBLIC"))
        if let directory = ProcessInfo.processInfo.environment["FOLIK_OFFICE_OUTPUT"] {
            try result.data.write(to: URL(fileURLWithPath: directory).appendingPathComponent("RedactionVerified.pdf"))
        }
    }
    func testFullPageMaskIsBlackInRenderedPixelsAndRotationPreserved() async throws {
        let source = try XCTUnwrap(PDFDocument(data: fixture())); source.page(at: 0)?.rotation = 90
        let data = try XCTUnwrap(source.dataRepresentation())
        let result = try await PDFRedaction.redact(data, areas: [RedactionArea(page: 0, rect: CGRect(x: 0, y: 0, width: 1, height: 1))])
        let page = try XCTUnwrap(PDFDocument(data: result.data)?.page(at: 0))
        XCTAssertEqual(page.bounds(for: .mediaBox).width, 792)
        XCTAssertEqual(page.bounds(for: .mediaBox).height, 612)
        let image = try PDFProcessing.bitmap(XCTUnwrap(page.pageRef), dpi: 20)
        let context = try XCTUnwrap(CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                             space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let pixels = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        XCTAssertLessThan(pixels[0], 3); XCTAssertLessThan(pixels[1], 3); XCTAssertLessThan(pixels[2], 3)
    }
    func testInvalidAreasAndCancellationFailWithoutOutput() async throws {
        for rect in [CGRect.zero, CGRect(x: -0.1, y: 0, width: 1, height: 1), CGRect(x: 0, y: 0, width: 2, height: 1)] {
            XCTAssertThrowsError(try PDFRedaction.validate([RedactionArea(page: 0, rect: rect)], pages: 1))
        }
        XCTAssertThrowsError(try PDFRedaction.validate([], pages: 1))
        XCTAssertThrowsError(try PDFRedaction.validate([RedactionArea(page: 2, rect: CGRect(x: 0, y: 0, width: 1, height: 1))], pages: 1))
        let input = try fixture()
        let task = Task { try await PDFRedaction.redact(input, areas: [RedactionArea(page: 0, rect: CGRect(x: 0, y: 0, width: 1, height: 1))]) }
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancellation ignored") } catch { XCTAssertTrue(error is CancellationError) }
    }
}

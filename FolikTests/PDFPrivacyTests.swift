import PDFKit
import UIKit
import XCTest
@testable import Folik

@MainActor
final class PDFPrivacyTests: XCTestCase {
    private func fixture() throws -> Data {
        let base = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792)).pdfData { context in
            context.beginPage()
            ("VISIBLE INVOICE 4827" as NSString).draw(
                at: CGPoint(x: 72, y: 96),
                withAttributes: [.font: UIFont.systemFont(ofSize: 24), .foregroundColor: UIColor.black]
            )
        }
        let pdf = try XCTUnwrap(PDFDocument(data: base))
        pdf.documentAttributes = [
            PDFDocumentAttribute.authorAttribute: "Private Author",
            PDFDocumentAttribute.titleAttribute: "Private Title",
            PDFDocumentAttribute.keywordsAttribute: ["internal", "invoice"]
        ]
        let page = try XCTUnwrap(pdf.page(at: 0))

        let form = PDFAnnotation(bounds: CGRect(x: 72, y: 520, width: 260, height: 36), forType: .widget, withProperties: nil)
        form.widgetFieldType = .text
        form.fieldName = "Account holder"
        form.widgetStringValue = "Joseph Example"
        page.addAnnotation(form)

        let comment = PDFAnnotation(bounds: CGRect(x: 72, y: 620, width: 34, height: 34), forType: .text, withProperties: nil)
        comment.contents = "Internal comment"
        page.addAnnotation(comment)

        let link = PDFAnnotation(bounds: CGRect(x: 72, y: 680, width: 180, height: 30), forType: .link, withProperties: nil)
        link.url = URL(string: "https://example.com/private")
        page.addAnnotation(link)

        let outline = PDFOutline()
        let child = PDFOutline()
        child.label = "Internal section"
        child.destination = PDFDestination(page: page, at: .zero)
        outline.insertChild(child, at: 0)
        pdf.outlineRoot = outline
        return try XCTUnwrap(pdf.dataRepresentation())
    }

    func testReportFindsMetadataTextFormsAnnotationsLinksAndOutline() throws {
        let report = try PDFPrivacy.inspect(fixture())
        XCTAssertEqual(report.pageCount, 1)
        XCTAssertEqual(report.searchablePageCount, 1)
        XCTAssertTrue(report.metadata.contains { $0.name == "Author" && $0.value == "Private Author" })
        XCTAssertTrue(report.metadata.contains { $0.name == "Title" && $0.value == "Private Title" })
        XCTAssertEqual(report.formFieldCount, 1)
        XCTAssertEqual(report.filledFormFieldCount, 1)
        XCTAssertEqual(report.annotationCount, 1)
        XCTAssertEqual(report.linkCount, 1)
        if #available(iOS 27.0, *) {
            // PDFKit 27 no longer serializes an outline assembled in memory.
            XCTAssertEqual(report.outlineItemCount, 0)
        } else {
            XCTAssertEqual(report.outlineItemCount, 1)
        }
    }

    func testReportFindsCatalogScriptsAndEmbeddedFiles() throws {
        let report = try PDFPrivacy.inspect(catalogFixture())
        XCTAssertTrue(report.hasScriptsOrAutomaticActions)
        XCTAssertTrue(report.hasEmbeddedFiles)
        XCTAssertEqual(report.signatureFieldCount, 2)
        XCTAssertEqual(report.signedSignatureCount, 1)
    }

    func testSanitizedCopyKeepsVisiblePageButRemovesPrivateObjects() async throws {
        let input = try fixture()
        let output = try await PDFPrivacy.sanitize(input)
        let pdf = try XCTUnwrap(PDFDocument(data: output.data))
        XCTAssertEqual(pdf.pageCount, 1)
        XCTAssertTrue((pdf.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        XCTAssertTrue(try XCTUnwrap(pdf.page(at: 0)).annotations.isEmpty)
        XCTAssertNil(pdf.outlineRoot)
        XCTAssertNotEqual(pdf.documentAttributes?[PDFDocumentAttribute.authorAttribute] as? String, "Private Author")
        XCTAssertNotEqual(pdf.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String, "Private Title")

        let cg = try XCTUnwrap(CGPDFDocument(CGDataProvider(data: output.data as CFData)!))
        let catalog = try XCTUnwrap(cg.catalog)
        for key in ["AcroForm", "Names", "Outlines", "Metadata", "OpenAction", "AA", "AF"] {
            var object: CGPDFObjectRef?
            XCTAssertFalse(CGPDFDictionaryGetObject(catalog, key, &object), key)
        }

        let bitmap = try PDFProcessing.bitmap(try XCTUnwrap(pdf.page(at: 0)?.pageRef))
        let recognized = try await ScannedPDFWriter.recognizeText(in: bitmap).map(\.text).joined(separator: " ")
        XCTAssertTrue(recognized.contains("VISIBLE"))
        XCTAssertTrue(output.recoveryNotice?.contains("original is unchanged") == true)
    }

    func testSanitizingHonorsCancellationAndRejectsProtectedInput() async throws {
        let task = Task { try await PDFPrivacy.sanitize(try fixture()) }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Cancellation ignored")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }

        let pdf = try XCTUnwrap(PDFDocument(data: fixture()))
        let protected = try XCTUnwrap(pdf.dataRepresentation(options: [
            PDFDocumentWriteOption.userPasswordOption: "open",
            PDFDocumentWriteOption.ownerPasswordOption: "owner"
        ]))
        XCTAssertThrowsError(try PDFPrivacy.inspect(protected)) { error in
            XCTAssertEqual(error as? PDFProcessingError, .protected)
        }
    }

    private func catalogFixture() -> Data {
        let objects = [
            "<< /Type /Catalog /Pages 2 0 R /OpenAction 4 0 R /Names << /JavaScript << /Names [(DocJS) 4 0 R] >> /EmbeddedFiles << /Names [(payload.txt) 5 0 R] >> >> /AcroForm << /Fields [7 0 R 8 0 R] >> >>",
            "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 100 100] >>",
            "<< /S /JavaScript /JS (app.alert\\(1\\)) >>",
            "<< /Type /Filespec /F (payload.txt) /EF << /F 6 0 R >> >>",
            "<< /Length 4 >>\nstream\ntest\nendstream",
            "<< /FT /Sig /T (Unsigned) >>",
            "<< /FT /Sig /T (Signed) /V 9 0 R >>",
            "<< /Type /Sig /Filter /Adobe.PPKLite /SubFilter /adbe.pkcs7.detached /ByteRange [0 10 20 30] /Contents <0011> >>"
        ]
        var pdf = "%PDF-1.7\n"
        var offsets = [0]
        for (index, object) in objects.enumerated() {
            offsets.append(pdf.utf8.count)
            pdf += "\(index + 1) 0 obj\n\(object)\nendobj\n"
        }
        let xref = pdf.utf8.count
        pdf += "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n"
        for offset in offsets.dropFirst() {
            pdf += String(format: "%010d 00000 n \n", offset)
        }
        pdf += "trailer\n<< /Size \(objects.count + 1) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n"
        return Data(pdf.utf8)
    }
}

import PDFKit
import UIKit
import XCTest
@testable import Folik

@MainActor
final class PDFProtectionTests: XCTestCase {
    private func fixture() throws -> Data {
        let data = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792)).pdfData { context in
            context.beginPage()
            ("PROTECTED INVOICE 4827" as NSString).draw(
                at: CGPoint(x: 72, y: 96),
                withAttributes: [.font: UIFont.systemFont(ofSize: 24), .foregroundColor: UIColor.black]
            )
        }
        let pdf = try XCTUnwrap(PDFDocument(data: data))
        let field = PDFAnnotation(bounds: CGRect(x: 72, y: 560, width: 260, height: 36), forType: .widget, withProperties: nil)
        field.widgetFieldType = .text
        field.fieldName = "Reference"
        field.widgetStringValue = "4827"
        pdf.page(at: 0)?.addAnnotation(field)
        return try XCTUnwrap(pdf.dataRepresentation())
    }

    func testProtectedCopyRequiresChosenPasswordAndPreservesContent() throws {
        let input = try fixture()
        let result = try PDFProtection.protect(input, password: "correct horse battery staple")
        XCTAssertEqual(result.pageCount, 1)
        XCTAssertFalse(try XCTUnwrap(PDFDocument(data: input)).isEncrypted)

        let locked = try XCTUnwrap(PDFDocument(data: result.data))
        XCTAssertTrue(locked.isEncrypted)
        XCTAssertTrue(locked.isLocked)
        XCTAssertFalse(locked.unlock(withPassword: "wrong password"))
        XCTAssertTrue(locked.isLocked)
        XCTAssertTrue(locked.unlock(withPassword: "correct horse battery staple"))
        XCTAssertFalse(locked.isLocked)
        XCTAssertEqual(locked.pageCount, 1)
        XCTAssertTrue(locked.string?.contains("PROTECTED INVOICE 4827") == true)
        XCTAssertEqual(locked.page(at: 0)?.annotations.first?.widgetStringValue, "4827")
    }

    func testPasswordValidationRejectsUnsafeLengthsWhitespaceAndControls() {
        for password in ["", "short", "      ", "valid\npassword", String(repeating: "a", count: 129)] {
            XCTAssertThrowsError(try PDFProtection.validate(password)) { error in
                XCTAssertEqual(error as? PDFProtectionError, .invalidPassword)
            }
        }
        XCTAssertNoThrow(try PDFProtection.validate("sixsix"))
        XCTAssertNoThrow(try PDFProtection.validate("a phrase with spaces"))
        XCTAssertNoThrow(try PDFProtection.validate("pässword🔐"))
    }

    func testProtectRejectsAlreadyProtectedInput() throws {
        let once = try PDFProtection.protect(fixture(), password: "first password")
        XCTAssertThrowsError(try PDFProtection.protect(once.data, password: "second password")) { error in
            XCTAssertEqual(error as? PDFProcessingError, .protected)
        }
    }
}

import PDFKit
import XCTest
@testable import Folik

@MainActor
final class OfficeCompatibilityTests: XCTestCase {
    private func fixture(_ name: String = "OfficeCompatibility", _ ext: String) throws -> Data {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(bundle.url(forResource: name, withExtension: ext, subdirectory: "Fixtures") ?? bundle.url(forResource: name, withExtension: ext))
        return try Data(contentsOf: url)
    }
    private func paragraphs(_ model: OfficeDocument) -> [OfficeParagraph] {
        model.blocks.compactMap { if case .paragraph(let p) = $0 { return p }; return nil }
    }

    func testBothReadersPreserveMarginsColumnProportionsAndInlineStyles() throws {
        for ext in ["docx", "odt"] {
            let model = try OfficeDocumentEngine.read(fixture("OfficeCompatibility", ext), extensionName: ext)
            XCTAssertEqual(model.pageSize.width, 612, ext)
            XCTAssertEqual(model.pageSize.height, 792, ext)
            XCTAssertEqual(model.margins.top, 60, ext)
            XCTAssertEqual(model.margins.bottom, 72, ext)
            XCTAssertEqual(model.margins.left, 90, ext)
            XCTAssertEqual(model.margins.right, 54, ext)
            let runs = paragraphs(model).flatMap(\.runs)
            XCTAssertTrue(runs.contains { $0.text == "removed" && $0.style.strikethrough }, ext)
            XCTAssertTrue(runs.contains { $0.text == "super" && $0.style.scriptPosition == 1 }, ext)
            XCTAssertTrue(runs.contains { $0.text == "sub" && $0.style.scriptPosition == -1 }, ext)
            let table = try XCTUnwrap(model.blocks.compactMap { block -> OfficeTable? in
                if case .table(let table) = block { return table }; return nil
            }.first)
            XCTAssertEqual(table.columnWidths, [90, 270], ext)
        }
    }

    func testWordNumberOverridesAndNestedRestartUseEachLevelsFormat() throws {
        let model = try OfficeDocumentEngine.read(fixture("OfficeCompatibility", "docx"), extensionName: "docx")
        let text = paragraphs(model).map { $0.runs.map(\.text).joined() }
        for expected in ["C. Outer first", "C.i) Nested first", "C.ii) Nested second", "D. Outer second", "D.i) Nested reset"] {
            XCTAssertTrue(text.contains(expected), expected)
        }
        XCTAssertEqual(OfficeNumbering.label(27, format: "upperLetter"), "AA")
        XCTAssertEqual(OfficeNumbering.label(49, format: "lowerRoman"), "xlix")
        XCTAssertEqual(OfficeNumbering.label(7, format: "decimalZero"), "07")
    }

    func testODTListsInheritStylesAndContinueNamedAndRecentSequences() throws {
        let model = try OfficeDocumentEngine.read(fixture("OfficeCompatibility", "odt"), extensionName: "odt")
        let text = paragraphs(model).map { $0.runs.map(\.text).joined() }
        for expected in ["C. Outer first", "i) Nested first", "ii) Nested second", "D. Outer second", "E. Outer third"] {
            XCTAssertTrue(text.contains(expected), expected)
        }
    }

    func testNotesTextBoxesAndInteractiveLinksReachThePDF() async throws {
        for ext in ["docx", "odt"] {
            let preview = try await OfficeDocumentEngine.preview(fixture("OfficeCompatibility", ext), extensionName: ext)
            let pdf = try XCTUnwrap(PDFDocument(data: preview.data))
            let text = try XCTUnwrap(pdf.string)
            XCTAssertEqual(text.components(separatedBy: "BOX ONCE").count - 1, 1, ext)
            XCTAssertFalse(text.contains("DUPLICATE FALLBACK"), ext)
            XCTAssertTrue(text.contains("FOOTNOTE CONTENT"), ext)
            XCTAssertTrue(text.contains("ENDNOTE CONTENT"), ext)
            let page = try XCTUnwrap(pdf.page(at: 0))
            let link = try XCTUnwrap(page.annotations.first { $0.url?.absoluteString == "https://example.com/compatibility" })
            let selection = try XCTUnwrap(pdf.findString("Visit example", withOptions: []).first)
            XCTAssertTrue(link.bounds.intersects(selection.bounds(for: page)), ext)
            let title = try XCTUnwrap(pdf.findString("Compatibility sample", withOptions: []).first)
            XCTAssertEqual(title.bounds(for: page).minX, 90, accuracy: 1, ext)
            if let output = ProcessInfo.processInfo.environment["FOLIK_OFFICE_OUTPUT"] {
                try preview.data.write(to: URL(fileURLWithPath: output).appendingPathComponent("Compatibility.\(ext).pdf"))
            }
        }
        XCTAssertNil(OfficeNumbering.safeLink("file:///private/example"))
        XCTAssertNil(OfficeNumbering.safeLink("javascript:alert(1)"))
    }

    func testUnknownAlternateChoiceUsesOnlyFallback() throws {
        let xml = #"<mc:AlternateContent xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006" xmlns:x="urn:unknown"><mc:Choice Requires="x"><x:item>unsupported</x:item></mc:Choice><mc:Fallback><item>fallback</item></mc:Fallback></mc:AlternateContent>"#
        XCTAssertEqual(try OfficeXML.parse(Data(xml.utf8)).alternative?.text, "fallback")
    }

    func testHugeODTRepetitionFailsWithoutIntegerOverflow() throws {
        for name in ["OfficeHugeRows", "OfficeHugeCells"] {
            XCTAssertThrowsError(try OfficeDocumentEngine.read(fixture(name, "odt"), extensionName: "odt")) { error in
                guard case OfficeConversionError.tooLarge = error else { return XCTFail("Unexpected error: \(error)") }
            }
        }
    }
}

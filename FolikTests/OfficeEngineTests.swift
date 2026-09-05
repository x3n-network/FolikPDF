import CoreText
import PDFKit
import XCTest
@testable import Folik

@MainActor
final class OfficeEngineTests: XCTestCase {
    private func fixture(_ name: String, _ ext: String) throws -> Data {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(bundle.url(forResource: name, withExtension: ext, subdirectory: "Fixtures") ?? bundle.url(forResource: name, withExtension: ext))
        return try Data(contentsOf: url)
    }
    private func compact(_ text: String) -> String { text.filter { !$0.isWhitespace } }

    func testDOCXAndODTModelsPreserveStyledContentImagesAndTables() throws {
        for ext in ["docx", "odt"] {
            let model = try OfficeDocumentEngine.read(fixture("OfficeEngine", ext), extensionName: ext)
            let paragraphs = model.blocks.compactMap { block -> OfficeParagraph? in
                if case .paragraph(let p) = block { return p }; return nil
            }
            let runs = paragraphs.flatMap(\.runs)
            XCTAssertTrue(runs.contains { $0.text.contains("bold text") && $0.style.bold }, ext)
            XCTAssertTrue(runs.contains { $0.text.contains("Engine sample") && ($0.style.bold || $0.style.size > 14) }, ext)
            XCTAssertEqual(model.blocks.filter { if case .image = $0 { return true }; return false }.count, 1)
            XCTAssertEqual(model.blocks.filter { if case .table = $0 { return true }; return false }.count, 1)
            XCTAssertTrue(runs.contains { $0.text.contains(ext == "docx" ? "1." : "3.") }, ext)
            if ext == "docx" { XCTAssertTrue(model.warnings.contains { $0.contains("Headers") }) }
        }
    }

    func testBothFormatsPaginateTallTableRowsWithoutLosingText() async throws {
        for ext in ["docx", "odt"] {
            let preview = try await OfficeDocumentEngine.preview(fixture("OfficeEngine", ext), extensionName: ext)
            let pdf = try XCTUnwrap(PDFDocument(data: preview.data))
            XCTAssertGreaterThan(pdf.pageCount, 2)
            let text = compact(try XCTUnwrap(pdf.string))
            for index in 0..<160 {
                XCTAssertTrue(text.contains(compact(String(format: "Cell line %03d", index))), "\(ext) cell line \(index)")
            }
            for marker in ["Engine sample", "AFTER IMAGE MARKER", "AFTER TABLE MARKER", "FINAL \(ext.uppercased()) MARKER", "Neighbor cell"] {
                XCTAssertTrue(text.contains(compact(marker)), "\(ext): \(marker)")
            }
            XCTAssertTrue(preview.warnings.contains { $0.contains("Table") })
            if let output = ProcessInfo.processInfo.environment["FOLIK_OFFICE_OUTPUT"] {
                try preview.data.write(to: URL(fileURLWithPath: output).appendingPathComponent("Synthetic.\(ext).pdf"))
            }
        }
    }

    func testPreviewSaveUsesExactReviewedBytesAndUniqueFilename() async throws {
        let preview = try await OfficeDocumentEngine.preview(fixture("OfficePreview", "docx"), extensionName: "docx")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = DocumentLibrary(documentsDirectory: directory)
        let first = try await library.importConvertedPDF(.preparedPDF(preview.data), named: "Office")
        let second = try await library.importConvertedPDF(.preparedPDF(preview.data), named: "Office")
        XCTAssertEqual(try Data(contentsOf: first.url), preview.data)
        XCTAssertEqual(try Data(contentsOf: second.url), preview.data)
        XCTAssertEqual(second.url.lastPathComponent, "Office 2.pdf")
    }

    func testTableImagesAndColumnSpansSurviveBothReaders() async throws {
        for ext in ["docx", "odt"] {
            let model = try OfficeDocumentEngine.read(fixture("OfficeEngine", ext), extensionName: ext)
            var tableImageCount = 0
            var spanCount = 0
            for block in model.blocks {
                if case .table(let rows) = block {
                    for row in rows.rows { for cell in row {
                        if cell.columnSpan == 2 { spanCount += 1 }
                        tableImageCount += cell.blocks.filter { if case .image = $0 { return true }; return false }.count
                    } }
                }
            }
            XCTAssertEqual(spanCount, 1, ext)
            XCTAssertEqual(tableImageCount, 1, ext)
            let preview = try await OfficeDocumentEngine.preview(fixture("OfficeEngine", ext), extensionName: ext)
            XCTAssertFalse(preview.warnings.contains { $0.contains("Images inside tables") })
        }
    }

    func testArchiveStoredDeflatedAndCRCValidation() throws {
        for name in ["OfficeStored", "OfficeDeflated"] {
            let data = try fixture(name, "zip")
            let archive = try OfficePackage(data: data)
            XCTAssertEqual(String(data: try archive.read("content.xml"), encoding: .utf8), "known archive content")
        }
        var damaged = try fixture("OfficeStored", "zip")
        let range = try XCTUnwrap(damaged.range(of: Data("known archive content".utf8)))
        damaged[range.lowerBound] ^= 1
        let archive = try OfficePackage(data: damaged)
        XCTAssertThrowsError(try archive.read("content.xml"))
        XCTAssertThrowsError(try OfficePackage(data: damaged.prefix(20)))
    }

    func testPackageBoundsAndPathTraversalAreRejected() throws {
        XCTAssertThrowsError(try OfficePackage.resolve("../../outside", relativeTo: "word/document.xml"))
        XCTAssertThrowsError(try OfficePackage.resolve("https://example.com/image.png", relativeTo: "word/document.xml"))
        XCTAssertEqual(try OfficePackage.resolve("../media/image.png", relativeTo: "word/parts/document.xml"), "word/media/image.png")
        var data = try fixture("OfficeStored", "zip")
        let signature = Data([0x50, 0x4b, 0x01, 0x02])
        let index = try XCTUnwrap(data.range(of: signature)?.lowerBound)
        for offset in 24..<28 { data[index + offset] = 0xff }
        XCTAssertThrowsError(try OfficePackage(data: data))
    }

    func testXMLUsesNamespacesAndRejectsEntitiesAndExcessiveDepth() throws {
        let xml = Data(#"<x:p xmlns:x="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><x:r><x:t>Example</x:t></x:r></x:p>"#.utf8)
        let node = try OfficeXML.parse(xml)
        XCTAssertEqual(node.name, "w:p")
        XCTAssertEqual(node.text, "Example")
        XCTAssertThrowsError(try OfficeXML.parse(Data(#"<!DOCTYPE root [<!ENTITY test SYSTEM "file:///etc/passwd">]><root>&test;</root>"#.utf8)))
        XCTAssertThrowsError(try OfficeXML.parse(Data((String(repeating: "<a>", count: 90) + String(repeating: "</a>", count: 90)).utf8)))
    }

    func testUnsupportedInputFailsAndCancellationPropagates() async throws {
        let data = try fixture("OfficePreview", "docx")
        XCTAssertThrowsError(try OfficeDocumentEngine.read(data, extensionName: "pages"))
        let task = Task { try await OfficeDocumentEngine.preview(data, extensionName: "docx") }
        task.cancel()
        do { _ = try await task.value; XCTFail("Conversion ignored cancellation") }
        catch { XCTAssertTrue(error is CancellationError || error is OfficeConversionError) }
    }

    func testUserProvidedDocumentsWhenConfigured() async throws {
        guard let directory = ProcessInfo.processInfo.environment["FOLIK_OFFICE_OUTPUT"] else {
            throw XCTSkip("Optional private test files were not supplied.")
        }
        let root = URL(fileURLWithPath: directory)
        let source = try Data(contentsOf: root.appendingPathComponent("UserReport.docx"))
        let preview = try await OfficeDocumentEngine.preview(source, extensionName: "docx")
        try preview.data.write(to: root.appendingPathComponent("UserReport.pdf"))
        let pdf = try XCTUnwrap(PDFDocument(data: preview.data))
        let expected = try JSONDecoder().decode([String].self, from: Data(contentsOf: root.appendingPathComponent("expected.json")))
        let extracted = compact(try XCTUnwrap(pdf.string))
        let missing = expected.filter { !extracted.contains(compact($0)) }
        let report: [String: Any] = ["pages": pdf.pageCount, "warnings": preview.warnings, "expectedTextFragments": expected.count, "missingTextFragments": missing]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: root.appendingPathComponent("report.json"))
        XCTAssertTrue(missing.isEmpty, "\(missing.count) source text fragments missing; see private report.json")
        let txt = try Data(contentsOf: root.appendingPathComponent("UserText.txt"))
        try PDFConverter.writeText(txt, extensionName: "txt", to: root.appendingPathComponent("UserText.pdf"))
        let textPDF = try XCTUnwrap(PDFDocument(url: root.appendingPathComponent("UserText.pdf")))
        let text = compact(try XCTUnwrap(textPDF.string))
        for line in String(decoding: txt, as: UTF8.self).split(separator: "\n") {
            XCTAssertTrue(text.contains(compact(String(line))), "A source TXT line was missing")
        }
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("UserReport.docx")), source)
    }
}

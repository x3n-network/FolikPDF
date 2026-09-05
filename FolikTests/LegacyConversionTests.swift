import PDFKit
import XCTest
@testable import Folik

@MainActor
final class LegacyConversionTests: XCTestCase {
    private func fixture(_ name: String, ext: String = "doc") throws -> Data {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(bundle.url(forResource: name, withExtension: ext, subdirectory: "Fixtures") ?? bundle.url(forResource: name, withExtension: ext))
        return try Data(contentsOf: url)
    }
    func testRealLegacyUnicodeAndLongDocumentsPreserveMainText() async throws {
        for name in ["LegacyUnicode", "LegacyLong"] {
            let preview = try await OfficeDocumentEngine.preview(fixture(name), extensionName: "DOC")
            let pdf = try XCTUnwrap(PDFDocument(data: preview.data))
            let text = try XCTUnwrap(pdf.string)
            if name == "LegacyUnicode" {
                for marker in ["Legacy Word sample", "Café", "Ελληνικά", "日本語", "FINAL LEGACY MARKER"] { XCTAssertTrue(text.contains(marker), marker) }
            } else {
                XCTAssertGreaterThan(pdf.pageCount, 2)
                for index in 0..<180 { XCTAssertTrue(text.contains(String(format: "Legacy line %03d", index))) }
            }
            XCTAssertTrue(preview.warnings.contains { $0.contains("text recovery") && $0.contains("images") })
            if let output = ProcessInfo.processInfo.environment["FOLIK_OFFICE_OUTPUT"] {
                try preview.data.write(to: URL(fileURLWithPath: output).appendingPathComponent(name + ".pdf"))
            }
        }
    }
    func testMixedPieceEncodingsAndSavedFieldResults() async throws {
        let preview = try await OfficeDocumentEngine.preview(fixture("LegacyPieces"), extensionName: "doc")
        let text = try XCTUnwrap(PDFDocument(data: preview.data)?.string)
        for marker in ["Compressed café € “quotes”", "Unicode 日本語", "VISIBLE RESULT", "Cell A", "Cell B", "LAST PIECE"] {
            XCTAssertTrue(text.contains(marker), marker)
        }
        XCTAssertFalse(text.contains("HYPERLINK secret"))
        XCTAssertNotNil(preview.recoveryNotice)
    }
    func testEncryptedAndMalformedLegacyFilesFail() throws {
        for name in ["LegacyEncrypted", "LegacyBadPieces"] {
            XCTAssertThrowsError(try OfficeDocumentEngine.read(fixture(name), extensionName: "doc"))
        }
    }
    func testPagesArchivePreservesBothPagesAndRejectsThumbnailOnly() async throws {
        let source = try fixture("PagesSavedPreview", ext: "pages")
        let preview = try await OfficeDocumentEngine.preview(source, extensionName: "pages")
        XCTAssertEqual(preview.data, try OfficePackage(data: source).read("QuickLook/Preview.pdf"))
        let pdf = try XCTUnwrap(PDFDocument(data: preview.data))
        XCTAssertEqual(pdf.pageCount, 2)
        XCTAssertTrue(pdf.page(at: 0)?.string?.contains("PAGES FIRST PAGE") == true)
        XCTAssertTrue(pdf.page(at: 1)?.string?.contains("PAGES FINAL PAGE") == true)
        XCTAssertNotNil(preview.recoveryNotice)
        XCTAssertThrowsError(try PagesPDFReader.preview(fixture("PagesThumbnailOnly", ext: "pages"))) { error in
            guard case OfficeConversionError.pagesNeedsExport = error else { return XCTFail("Unexpected error: \(error)") }
        }
    }
    func testNewFallbackPathsRespectCancellation() async throws {
        for (name, ext) in [("LegacyLong", "doc"), ("PagesSavedPreview", "pages")] {
            let data = try fixture(name, ext: ext)
            let task = Task { try await OfficeDocumentEngine.preview(data, extensionName: ext) }
            task.cancel()
            do { _ = try await task.value; XCTFail("Cancellation ignored") }
            catch { XCTAssertTrue(error is CancellationError) }
        }
    }
    func testCompoundChainCyclesAndTruncationAreRejected() throws {
        let original = try fixture("LegacyUnicode")
        XCTAssertThrowsError(try CompoundDocument(Data(original.prefix(400))))
        var broken = original
        let sectorSize = 1 << Int(try original.office16(30))
        let directory = Int(try original.office32(48))
        let fatSector = Int(try original.office32(76))
        let offset = (fatSector + 1) * sectorSize + directory * 4
        for byte in 0..<4 { broken[offset + byte] = UInt8((directory >> (byte * 8)) & 255) }
        XCTAssertThrowsError(try CompoundDocument(broken))
    }
    func testPagesPDFPreservesEveryByteAndRequiresARealPDF() async throws {
        let recovered = try await OfficeDocumentEngine.preview(fixture("LegacyUnicode"), extensionName: "doc")
        let preview = try await OfficeDocumentEngine.preview(recovered.data, extensionName: "pages")
        XCTAssertEqual(preview.data, recovered.data)
        XCTAssertEqual(preview.pageCount, recovered.pageCount)
        XCTAssertTrue(preview.warnings.contains { $0.contains("outdated or incomplete") })
        XCTAssertThrowsError(try PagesPDFReader.preview(Data("%PDF-broken".utf8)))
    }
    func testPagesDirectoryPreviewAndMissingPreview() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pages")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("QuickLook"), withIntermediateDirectories: true)
        XCTAssertThrowsError(try PagesPDFReader.readFile(root))
        let source = try await OfficeDocumentEngine.preview(fixture("LegacyUnicode"), extensionName: "doc")
        try source.data.write(to: root.appendingPathComponent("QuickLook/Preview.pdf"))
        let read = try PagesPDFReader.readFile(root)
        XCTAssertEqual(try PagesPDFReader.preview(read).data, source.data)
        try FileManager.default.removeItem(at: root.appendingPathComponent("QuickLook/Preview.pdf"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("QuickLook/Preview.pdf"), withDestinationURL: root.appendingPathComponent("elsewhere.pdf"))
        XCTAssertThrowsError(try PagesPDFReader.readFile(root))
    }
}

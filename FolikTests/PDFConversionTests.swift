import ImageIO
import PDFKit
import UIKit
import UniformTypeIdentifiers
import XCTest
@testable import Folik

@MainActor
final class PDFConversionTests: XCTestCase {
    private var workspace: URL!
    private var directory: URL!

    override func setUpWithError() throws {
        workspace = FileManager.default.temporaryDirectory.appendingPathComponent("Conversion-\(UUID().uuidString)")
        directory = workspace.appendingPathComponent("Library")
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: workspace)
    }

    func testTextPaginationPreservesEveryLineAndOriginal() async throws {
        let source = workspace.appendingPathComponent("Notes.txt")
        let lines = (0..<180).map { "Line \($0): café résumé Folik conversion." }
        let data = Data(lines.joined(separator: "\n").utf8)
        try data.write(to: source)
        let loaded = try PDFConverter.readFile(source, maximumBytes: PDFConverter.maximumTextBytes)
        let library = DocumentLibrary(documentsDirectory: directory)
        let document = try await library.importConvertedPDF(.text(loaded, extensionName: "txt"), named: "Notes")
        let pdf = try XCTUnwrap(PDFDocument(url: document.url))
        XCTAssertGreaterThan(pdf.pageCount, 1)
        let extracted = try XCTUnwrap(pdf.string)
        for line in lines { XCTAssertTrue(extracted.contains(line), "Missing \(line)") }
        XCTAssertEqual(try Data(contentsOf: source), data)
        XCTAssertFalse(library.isImporting)
        XCTAssertNil(library.importStatus)
    }

    func testRTFAndUTF16RemainSearchableAndDuplicateNamesAreSafe() async throws {
        let library = DocumentLibrary(documentsDirectory: directory)
        let rtf = Data(#"{\rtf1\ansi\deff0{\fonttbl{\f0 Helvetica;}}\f0\fs28 Bold \b heading\b0\par Second paragraph.}"#.utf8)
        let first = try await library.importConvertedPDF(.text(rtf, extensionName: "RTF"), named: "Report.pdf")
        let text = try XCTUnwrap(PDFDocument(url: first.url)?.string)
        XCTAssertTrue(text.contains("Bold heading"))
        XCTAssertTrue(text.contains("Second paragraph."))
        let original = try Data(contentsOf: first.url)
        let utf16 = try XCTUnwrap("Unicode café document".data(using: .utf16))
        let second = try await library.importConvertedPDF(.text(utf16, extensionName: "txt"), named: "Report")
        XCTAssertEqual(second.url.lastPathComponent, "Report 2.pdf")
        XCTAssertTrue(PDFDocument(url: second.url)?.string?.contains("Unicode café document") == true)
        XCTAssertEqual(try Data(contentsOf: first.url), original)
    }

    func testImagesPreservePageOrderOrientationAndSearchableText() async throws {
        let library = DocumentLibrary(documentsDirectory: directory)
        let pages = [image("First receipt", size: CGSize(width: 600, height: 900)),
                     image("Second invoice", size: CGSize(width: 900, height: 600))]
        let document = try await library.importConvertedPDF(.images(pages.reversed()), named: "Receipts")
        let pdf = try XCTUnwrap(PDFDocument(url: document.url))
        XCTAssertEqual(pdf.pageCount, 2)
        XCTAssertEqual(pdf.page(at: 0)?.bounds(for: .mediaBox).size, CGSize(width: 792, height: 612))
        XCTAssertEqual(pdf.page(at: 1)?.bounds(for: .mediaBox).size, CGSize(width: 612, height: 792))
        XCTAssertTrue(pdf.page(at: 0)?.string?.contains("Second invoice") == true)
        XCTAssertTrue(pdf.page(at: 1)?.string?.contains("First receipt") == true)
    }

    func testEXIFOrientationIsAppliedBeforeChoosingPageSize() async throws {
        let raw = try XCTUnwrap(UIImage(data: image("Rotated", size: CGSize(width: 600, height: 900)))?.cgImage)
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, raw, [kCGImagePropertyOrientation: 6] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let decoded = try PDFConverter.image(data as Data)
        XCTAssertGreaterThan(decoded.width, decoded.height)
        let library = DocumentLibrary(documentsDirectory: directory)
        let document = try await library.importConvertedPDF(.images([data as Data]), named: "Rotated")
        XCTAssertEqual(PDFDocument(url: document.url)?.page(at: 0)?.bounds(for: .mediaBox).size, CGSize(width: 792, height: 612))
    }

    func testFailuresLeaveNoPartialPDFAndAllowRetry() async throws {
        let library = DocumentLibrary(documentsDirectory: directory)
        let invalidInputs: [PDFConversionInput] = [
            .images([]), .images([Data("broken".utf8)]),
            .images([image("Good", size: CGSize(width: 300, height: 400)), Data("broken".utf8)]),
            .text(Data(" ".utf8), extensionName: "txt"),
            .text(Data([0xff, 0x00]), extensionName: "txt"),
            .text(Data("invalid RTF".utf8), extensionName: "rtf"),
            .text(Data("Word".utf8), extensionName: "docx")
        ]
        for input in invalidInputs {
            do {
                _ = try await library.importConvertedPDF(input, named: "Invalid")
                XCTFail("Invalid conversion succeeded")
            } catch { }
            XCTAssertTrue(library.documents.isEmpty)
            XCTAssertFalse(library.isImporting)
            XCTAssertNil(library.importStatus)
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
        }
        let retry = try await library.importConvertedPDF(.text(Data("Retry succeeded".utf8), extensionName: "txt"), named: "Retry")
        XCTAssertEqual(retry.pageCount, 1)
    }

    func testInputBoundsAndFilenameValidation() throws {
        for name in ["", " ", "../Escape", "a/b", "a:b", ".hidden", ".pdf"] {
            XCTAssertThrowsError(try PDFConverter.fileName(name))
        }
        XCTAssertEqual(try PDFConverter.fileName(" Report.PDF "), "Report.pdf")
        let source = workspace.appendingPathComponent("large.txt")
        try Data(repeating: 65, count: 11).write(to: source)
        XCTAssertThrowsError(try PDFConverter.readFile(source, maximumBytes: 10))
    }

    private func image(_ title: String, size: CGSize) -> Data {
        UIGraphicsImageRenderer(size: size).jpegData(withCompressionQuality: 0.9) { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            (title as NSString).draw(at: CGPoint(x: 30, y: 60), withAttributes: [
                .font: UIFont.systemFont(ofSize: 36), .foregroundColor: UIColor.black
            ])
        }
    }
}

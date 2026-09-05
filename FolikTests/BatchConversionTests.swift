import PDFKit
import XCTest
@testable import Folik

@MainActor
final class BatchConversionTests: XCTestCase {
    private var sources: [BatchSource] {
        [BatchSource(name: "Report", extensionName: "txt", data: Data("FIRST BATCH MARKER".utf8)),
         BatchSource(name: "Report", extensionName: "txt", data: Data("SECOND BATCH MARKER".utf8))]
    }
    func testSeparateAndCombinedPreserveOrderAndText() async throws {
        let separate = try await BatchConversion.prepare(sources, combined: false)
        XCTAssertEqual(separate.count, 2)
        XCTAssertTrue(PDFDocument(data: separate[1].preview.data)?.string?.contains("SECOND BATCH MARKER") == true)
        let combined = try await BatchConversion.prepare(Array(sources.reversed()), combined: true)
        let pdf = try XCTUnwrap(PDFDocument(data: combined[0].preview.data))
        XCTAssertEqual(pdf.pageCount, 2)
        XCTAssertTrue(pdf.page(at: 0)?.string?.contains("SECOND BATCH MARKER") == true)
        XCTAssertTrue(pdf.page(at: 1)?.string?.contains("FIRST BATCH MARKER") == true)
    }
    func testBatchSaveKeepsExactBytesAndResolvesDuplicateNames() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = DocumentLibrary(documentsDirectory: directory)
        let prepared = try await BatchConversion.prepare(sources, combined: false)
        let documents = try await library.importBatchPDFs(prepared)
        XCTAssertEqual(documents.map { $0.url.lastPathComponent }, ["Report.pdf", "Report 2.pdf"])
        for index in 0..<documents.count { XCTAssertEqual(try Data(contentsOf: documents[index].url), prepared[index].preview.data) }
    }
    func testInvalidBatchDoesNotLeavePartialLibraryFiles() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = DocumentLibrary(documentsDirectory: directory)
        var prepared = try await BatchConversion.prepare(sources, combined: false)
        prepared.append(BatchPDFOutput(name: "Invalid", preview: OfficePreview(data: Data("broken".utf8), warnings: [], pageCount: 1)))
        do { _ = try await library.importBatchPDFs(prepared); XCTFail("Invalid batch saved") } catch { }
        XCTAssertTrue(library.documents.isEmpty)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }
    func testLimitsFailuresAndCancellation() async throws {
        do { _ = try await BatchConversion.prepare([], combined: false); XCTFail("Empty batch accepted") } catch { }
        do { _ = try await BatchConversion.prepare([BatchSource(name: "Bad", extensionName: "docx", data: Data())], combined: false); XCTFail("Invalid source accepted") } catch { }
        let input = sources
        let task = Task { try await BatchConversion.prepare(input, combined: true) }
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancellation ignored") } catch { XCTAssertTrue(error is CancellationError) }
    }
}

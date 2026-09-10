import UIKit
import XCTest
@testable import Folik

final class PDFTransferItemTests: XCTestCase {
    func testTemporaryCopyPreservesPDFBytesAndCleansUpOnlyItsStagingDirectory() throws {
        let sourceDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FolikTransferSource-\(UUID().uuidString)", isDirectory: true)
        let source = sourceDirectory.appendingPathComponent("Drop Contract.PDF")
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sourceDirectory) }
        let expected = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792)).pdfData { context in
            context.beginPage()
            "Dropped contract".draw(at: CGPoint(x: 72, y: 72), withAttributes: [.font: UIFont.systemFont(ofSize: 18)])
        }
        try expected.write(to: source)

        let item = try PDFTransferItem.temporaryCopy(of: source)

        XCTAssertEqual(item.url.lastPathComponent, "Drop Contract.pdf")
        XCTAssertEqual(try Data(contentsOf: item.url), expected)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))

        PDFTransferItem.removeTemporaryCopies([item])

        XCTAssertFalse(FileManager.default.fileExists(atPath: item.url.deletingLastPathComponent().path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }
}

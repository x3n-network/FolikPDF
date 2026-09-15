import PDFKit
import UIKit
import XCTest
@testable import Folik

@MainActor
final class PDFCompressionTests: XCTestCase {
    func testImageCompressionNeverGrowsFileAndPreservesTextAndWidget() throws {
        var seed: UInt32 = 4827
        let pixels: [UInt8] = (0..<(700 * 900 * 4)).map { index in
            if index % 4 == 3 { return 255 }
            seed = 1664525 &* seed &+ 1013904223
            return UInt8(truncatingIfNeeded: seed >> 24)
        }
        let provider = try XCTUnwrap(CGDataProvider(data: Data(pixels) as CFData))
        let image = try XCTUnwrap(CGImage(width: 700, height: 900, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 2800,
                                         space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                                         provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent))
        let data = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792)).pdfData { c in
            c.beginPage(); UIImage(cgImage: image).draw(in: CGRect(x: 0, y: 0, width: 612, height: 700))
            ("PRESERVE SELECTABLE TEXT" as NSString).draw(at: CGPoint(x: 30, y: 730), withAttributes: [.font: UIFont.systemFont(ofSize: 16)])
        }
        let pdf = try XCTUnwrap(PDFDocument(data: data))
        let widget = PDFAnnotation(bounds: CGRect(x: 30, y: 30, width: 100, height: 30), forType: .widget, withProperties: nil)
        widget.widgetFieldType = .text; widget.fieldName = "Example"; widget.widgetStringValue = "Keep value"
        pdf.page(at: 0)?.addAnnotation(widget)
        let input = try XCTUnwrap(pdf.dataRepresentation())
        let output = try PDFCompression.compress(input, preset: .smaller)
        XCTAssertLessThanOrEqual(output.data.count, input.count)
        let reopened = try XCTUnwrap(PDFDocument(data: output.data))
        XCTAssertTrue(reopened.string?.contains("PRESERVE SELECTABLE TEXT") == true)
        XCTAssertEqual(reopened.page(at: 0)?.annotations.first?.widgetStringValue, "Keep value")
        XCTAssertTrue(output.resultSummary?.contains("smaller") == true
            || output.resultSummary?.contains("original bytes retained") == true)
    }
    func testEveryPresetReturnsNoLargerPDFAndRejectsInvalidData() throws {
        let input = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792)).pdfData { $0.beginPage() }
        for preset in PDFCompressionPreset.allCases {
            let result = try PDFCompression.compress(input, preset: preset)
            XCTAssertLessThanOrEqual(result.data.count, input.count)
            XCTAssertEqual(PDFDocument(data: result.data)?.pageCount, 1)
        }
        XCTAssertThrowsError(try PDFCompression.compress(Data(), preset: .smaller))
    }
}

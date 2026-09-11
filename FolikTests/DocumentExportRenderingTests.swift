import PDFKit
import UIKit
import XCTest
@testable import Folik

@MainActor
final class DocumentExportRenderingTests: XCTestCase {
    func testFlattenedCopyMatchesVisiblePages() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Appearance.pdf")
        try UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792)).writePDF(to: source) { c in
            for _ in 0..<5 {
                c.beginPage()
                UIColor.white.setFill(); c.fill(CGRect(x: 0, y: 0, width: 612, height: 792))
                UIColor.blue.setFill(); c.fill(CGRect(x: 70, y: 180, width: 80, height: 45))
                NSString(string: "Keep this orientation").draw(at: CGPoint(x: 90, y: 300), withAttributes: [.font: UIFont.systemFont(ofSize: 20)])
            }
        }
        let document = try XCTUnwrap(PDFDocument(url: source))
        for index in 0..<5 {
            let page = try XCTUnwrap(document.page(at: index))
            if index > 0 {
                page.setBounds(CGRect(x: 50, y: 100, width: 400, height: 550), for: .cropBox)
                page.rotation = (index - 1) * 90
            }
            let highlight = PDFAnnotation(bounds: CGRect(x: 80, y: 150, width: 300, height: 180), forType: .square, withProperties: nil)
            highlight.color = .clear
            highlight.interiorColor = UIColor.yellow.withAlphaComponent(0.4)
            page.addAnnotation(highlight)
            let hidden = PDFAnnotation(bounds: CGRect(x: 100, y: 400, width: 230, height: 100), forType: .square, withProperties: nil)
            hidden.color = .red; hidden.interiorColor = .red
            hidden.shouldDisplay = false
            hidden.shouldPrint = false
            page.addAnnotation(hidden)
        }
        XCTAssertTrue(document.write(to: source))
        let originalBytes = try Data(contentsOf: source)
        let editable = try DocumentExporter.export(sourceURL: source, mode: .editable, root: root)
        XCTAssertEqual(try Data(contentsOf: editable), originalBytes)
        let output = try DocumentExporter.export(sourceURL: source, mode: .flattened, root: root)
        let original = try XCTUnwrap(PDFDocument(url: source))
        let flattened = try XCTUnwrap(PDFDocument(url: output))
        XCTAssertEqual(flattened.pageCount, original.pageCount)
        for index in 0..<original.pageCount {
            let before = try XCTUnwrap(original.page(at: index))
            let after = try XCTUnwrap(flattened.page(at: index))
            XCTAssertTrue(after.annotations.isEmpty)
            let expected = before.thumbnail(of: CGSize(width: 600, height: 600), for: .cropBox)
            let actual = after.thumbnail(of: CGSize(width: 600, height: 600), for: .cropBox)
            XCTAssertEqual(expected.size.width / expected.size.height, actual.size.width / actual.size.height, accuracy: 0.01, "Page \(index)")
            let width = 400, height = 400
            func pixels(_ image: UIImage) throws -> [UInt8] {
                let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                    bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
                context.setFillColor(UIColor.white.cgColor)
                context.fill(CGRect(x: 0, y: 0, width: width, height: height))
                context.draw(try XCTUnwrap(image.cgImage), in: CGRect(x: 0, y: 0, width: width, height: height))
                return Array(UnsafeBufferPointer(start: try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self), count: width * height * 4))
            }
            let expectedPixels = try pixels(expected), actualPixels = try pixels(actual)
            let error = zip(expectedPixels, actualPixels).reduce(0.0) { $0 + abs(Double($1.0) - Double($1.1)) } / Double(expectedPixels.count)
            XCTAssertLessThan(error, 2, "Page \(index) changed appearance")
            if error >= 2 {
                for (name, image) in [("source-\(index)", expected), ("flattened-\(index)", actual)] {
                    let attachment = XCTAttachment(image: image)
                    attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
                }
            }
        }
        XCTAssertEqual(try Data(contentsOf: source), originalBytes)
    }
}

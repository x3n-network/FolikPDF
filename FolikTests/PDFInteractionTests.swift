import PDFKit
import UIKit
import XCTest
@testable import Folik

@MainActor
final class PDFInteractionTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    private func fixture(rotation: Int, scale: CGFloat) throws -> (DocumentSession, PDFKitView.Coordinator, PDFPage) {
        let url = directory.appendingPathComponent(UUID().uuidString + ".pdf")
        try UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))
            .writePDF(to: url) { context in
                context.beginPage()
                context.beginPage()
            }
        let document = try XCTUnwrap(PDFDocument(url: url))
        for index in 0..<2 {
            let page = try XCTUnwrap(document.page(at: index))
            page.setBounds(CGRect(x: 24, y: 36, width: 564, height: 720), for: .cropBox)
            page.rotation = rotation
        }
        XCTAssertTrue(document.write(to: url))
        let item = LibraryDocument(url: url, pageCount: 2, fileSize: 0, modifiedAt: Date())
        let session = DocumentSession(item: item)
        let coordinator = PDFKitView.Coordinator(session: session)
        let view = coordinator.pdfView
        view.frame = CGRect(x: 0, y: 0, width: 800, height: 1000)
        view.document = session.document
        view.autoScales = false
        view.scaleFactor = scale
        view.layoutDocumentView()
        let page = try XCTUnwrap(session.document?.page(at: 1))
        view.go(to: page)
        view.layoutIfNeeded()
        return (session, coordinator, page)
    }

    func testTapAndResizeFollowVisibleCornerOnRotatedCroppedPages() throws {
        for rotation in [0, 90, 180, 270] {
            for scale: CGFloat in [0.7, 1.5] {
                let (session, coordinator, page) = try fixture(rotation: rotation, scale: scale)
                let view = coordinator.pdfView
                let crop = page.bounds(for: .cropBox)
                let center = CGPoint(x: crop.midX, y: crop.midY)
                let tap = InteractionTap()
                tap.point = view.convert(center, from: page)
                session.beginFormFieldPlacement(.text, label: "Tapped", isRequired: false)
                coordinator.updateDrawingState()
                coordinator.perform(NSSelectorFromString("handlePlacementTap:"), with: tap)
                let field = try XCTUnwrap(session.formFields.first)
                XCTAssertEqual(field.pageIndex, 1)
                XCTAssertEqual(field.annotation.bounds.midX, center.x, accuracy: 0.1)
                XCTAssertEqual(field.annotation.bounds.midY, center.y, accuracy: 0.1)
                session.beginFormLayoutEditing()
                session.selectAnnotation(field.annotation, pageIndex: 1, navigate: false)
                coordinator.updateDrawingState()
                let original = view.convert(field.annotation.bounds, from: page).standardized
                let pan = InteractionPan()
                pan.point = CGPoint(x: original.maxX, y: original.maxY)
                pan.state = .began
                coordinator.perform(NSSelectorFromString("handleAnnotationTransformPan:"), with: pan)
                pan.point.x += 20
                pan.point.y += 24
                pan.state = .changed
                coordinator.perform(NSSelectorFromString("handleAnnotationTransformPan:"), with: pan)
                // The final event can carry a newer location than the last changed event.
                pan.point.x += 15
                pan.point.y += 6
                pan.state = .ended
                coordinator.perform(NSSelectorFromString("handleAnnotationTransformPan:"), with: pan)
                let resized = view.convert(field.annotation.bounds, from: page).standardized
                XCTAssertEqual(resized.minX, original.minX, accuracy: 0.1, "rotation \(rotation)")
                XCTAssertEqual(resized.minY, original.minY, accuracy: 0.1)
                XCTAssertEqual(resized.maxX, original.maxX + 35, accuracy: 0.1)
                XCTAssertEqual(resized.maxY, original.maxY + 30, accuracy: 0.1)
                session.undoAnnotationAction()
                let undone = view.convert(field.annotation.bounds, from: page).standardized
                XCTAssertEqual(undone.width, original.width, accuracy: 0.1)
                XCTAssertEqual(undone.height, original.height, accuracy: 0.1)
            }
        }
    }
}

private final class InteractionTap: UITapGestureRecognizer {
    var point = CGPoint.zero
    override var state: UIGestureRecognizer.State { get { .ended } set {} }
    override func location(in view: UIView?) -> CGPoint { point }
}

private final class InteractionPan: UIPanGestureRecognizer {
    var point = CGPoint.zero
    private var simulatedState = UIGestureRecognizer.State.possible
    override var state: UIGestureRecognizer.State {
        get { simulatedState }
        set { simulatedState = newValue }
    }
    override func location(in view: UIView?) -> CGPoint { point }
}

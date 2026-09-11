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

    func testAddedFieldsHaveVisibleBordersAfterReopeningAndFlattening() throws {
        for kind in FormFieldPlacementKind.allCases {
            let url = directory.appendingPathComponent("Border-\(kind.rawValue).pdf")
            try SampleForm.data().write(to: url)
            let session = DocumentSession(item: LibraryDocument(url: url, pageCount: 1, fileSize: 0, modifiedAt: Date()))
            let originalNames = Set(session.formFields.map(\.title))
            session.beginFormFieldPlacement(kind, label: "Added field", isRequired: false)
            session.placeAnnotation(pageIndex: 0, point: CGPoint(x: 306, y: 200))
            let reopened = try XCTUnwrap(PDFDocument(url: url))
            let page = try XCTUnwrap(reopened.page(at: 0))
            let field = try XCTUnwrap(page.annotations.first { $0.fieldName == "Added field" })
            XCTAssertTrue(originalNames.isSubset(of: Set(page.annotations.compactMap(\.fieldName))))
            let flattenedURL = try DocumentExporter.export(sourceURL: url, mode: .flattened, root: directory)
            let flattenedPage = try XCTUnwrap(PDFDocument(url: flattenedURL)?.page(at: 0))
            for renderedPage in [page, flattenedPage] {
                let bounds = field.bounds
                let width = Int(bounds.width.rounded(.up)) + 8
                let height = Int(bounds.height.rounded(.up)) + 8
                let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height,
                    bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
                context.setFillColor(UIColor.white.cgColor)
                context.fill(CGRect(x: 0, y: 0, width: width, height: height))
                context.translateBy(x: 4 - bounds.minX, y: 4 - bounds.minY)
                renderedPage.draw(with: .mediaBox, to: context)
                let pixels = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
                // Each side must draw a visible blue border, without a selection overlay or focus.
                var sides = [0, 0, 0, 0]
                for y in 2..<(height - 2) {
                    for x in 2..<(width - 2) {
                        let offset = (y * width + x) * 4
                        guard Int(pixels[offset + 2]) > Int(pixels[offset]) + 30 else { continue }
                        if x < 7 { sides[0] += 1 }
                        if x >= width - 7 { sides[1] += 1 }
                        if y < 7 { sides[2] += 1 }
                        if y >= height - 7 { sides[3] += 1 }
                    }
                }
                for count in sides { XCTAssertGreaterThan(count, 10, "Missing border for \(kind.rawValue)") }
            }
        }
    }

    func testAnnotationTapMoveAndCancelledDragAcrossPageRotations() throws {
        for rotation in [0, 90, 180, 270] {
            for kind in [AnnotationPlacementKind.textBox, .stamp, .signature] {
                let (session, coordinator, page) = try fixture(rotation: rotation, scale: 1.1)
                let view = coordinator.pdfView
                let crop = page.bounds(for: .cropBox)
                let center = CGPoint(x: crop.midX, y: crop.midY)
                switch kind {
                case .signature:
                    session.beginSignaturePlacement(SignatureAsset(kind: .signature,
                        strokes: [SignatureStroke(points: [SignaturePoint(x: 0.1, y: 0.8),
                            SignaturePoint(x: 0.9, y: 0.2)])], typedText: nil))
                case .stamp: session.beginStampPlacement(.approved)
                default: session.beginAnnotationPlacement(kind, text: "Tapped text")
                }
                let tap = InteractionTap()
                tap.point = view.convert(center, from: page)
                coordinator.updateDrawingState()
                coordinator.perform(NSSelectorFromString("handlePlacementTap:"), with: tap)
                let annotation = try XCTUnwrap(session.annotations.first?.annotation)
                XCTAssertEqual(annotation.bounds.midX, center.x, accuracy: 0.1)
                XCTAssertEqual(annotation.bounds.midY, center.y, accuracy: 0.1)
                session.beginAnnotationEditing()
                session.selectAnnotation(annotation, pageIndex: 1, navigate: false)
                coordinator.updateDrawingState()
                let before = view.convert(annotation.bounds, from: page).standardized
                let pan = InteractionPan()
                pan.point = CGPoint(x: before.midX, y: before.midY)
                pan.state = .began
                coordinator.perform(NSSelectorFromString("handleAnnotationTransformPan:"), with: pan)
                pan.point.x += 25
                pan.point.y += 30
                pan.state = .ended
                coordinator.perform(NSSelectorFromString("handleAnnotationTransformPan:"), with: pan)
                let moved = view.convert(annotation.bounds, from: page).standardized
                XCTAssertEqual(moved.midX, before.midX + 25, accuracy: 0.1)
                XCTAssertEqual(moved.midY, before.midY + 30, accuracy: 0.1)
                let savedBounds = annotation.bounds
                pan.point = CGPoint(x: moved.midX, y: moved.midY)
                pan.state = .began
                coordinator.perform(NSSelectorFromString("handleAnnotationTransformPan:"), with: pan)
                pan.point.x += 20
                pan.state = .changed
                coordinator.perform(NSSelectorFromString("handleAnnotationTransformPan:"), with: pan)
                pan.state = .cancelled
                coordinator.perform(NSSelectorFromString("handleAnnotationTransformPan:"), with: pan)
                XCTAssertEqual(annotation.bounds, savedBounds)
                session.undoAnnotationAction()
                XCTAssertEqual(view.convert(annotation.bounds, from: page).midX, before.midX, accuracy: 0.1)
            }
        }
    }

    func testOnPageSelectionKeepsViewportAndOutlineTracksLayout() throws {
        let (session, coordinator, page) = try fixture(rotation: 90, scale: 1.2)
        let view = coordinator.pdfView
        let crop = page.bounds(for: .cropBox)
        let center = CGPoint(x: crop.midX, y: crop.midY)
        session.beginFormFieldPlacement(.text, label: "Select here", isRequired: false)
        session.placeAnnotation(pageIndex: 1, point: center)
        let field = try XCTUnwrap(session.formFields.first)
        session.beginFormLayoutEditing()
        coordinator.updateDrawingState()
        let previousCommand = session.command?.id
        let tap = InteractionTap()
        tap.point = view.convert(center, from: page)
        coordinator.perform(NSSelectorFromString("handleAnnotationSelectionTap:"), with: tap)
        XCTAssertTrue(session.selectedAnnotation?.annotation === field.annotation)
        XCTAssertEqual(session.command?.id, previousCommand, "Selecting a visible field must not navigate")
        coordinator.updateDrawingState()
        let outline = try XCTUnwrap(view.layer.sublayers?.compactMap { $0 as? CAShapeLayer }
            .first { $0.lineDashPattern == [6, 4] })
        view.frame.size = CGSize(width: 600, height: 800)
        view.scaleFactor = 0.8
        view.layoutDocumentView()
        view.setNeedsLayout()
        view.layoutIfNeeded()
        let expected = view.convert(field.annotation.bounds, from: page).standardized.insetBy(dx: -3, dy: -3)
        let actual = try XCTUnwrap(outline.path).boundingBoxOfPath
        XCTAssertEqual(actual.minX, expected.minX, accuracy: 0.1)
        XCTAssertEqual(actual.minY, expected.minY, accuracy: 0.1)
        XCTAssertEqual(actual.width, expected.width, accuracy: 0.1)
        XCTAssertEqual(actual.height, expected.height, accuracy: 0.1)
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

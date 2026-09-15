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
            let originalNames = Set(session.formFields.compactMap { $0.annotation.fieldName })
            session.beginFormFieldPlacement(kind, label: "Added field", isRequired: false)
            session.placeAnnotation(pageIndex: 0, point: CGPoint(x: 306, y: 200))
            let reopened = try XCTUnwrap(PDFDocument(url: url))
            let page = try XCTUnwrap(reopened.page(at: 0))
            let field = try XCTUnwrap(page.annotations.first { $0.fieldName == "Added field" })
            XCTAssertTrue(originalNames.isSubset(of: Set(page.annotations.compactMap(\.fieldName))))
            let flattenedURL = try DocumentExporter.export(sourceURL: url, mode: .flattened, root: directory)
            let flattenedPage = try XCTUnwrap(PDFDocument(url: flattenedURL)?.page(at: 0))
            if kind == .checkbox {
                XCTAssertGreaterThan(field.border?.lineWidth ?? 0, 0)
                try assertVisibleBorder(on: flattenedPage, bounds: field.bounds, kind: kind)
            } else {
                for renderedPage in [page, flattenedPage] {
                    try assertVisibleBorder(on: renderedPage, bounds: field.bounds, kind: kind)
                }
            }
        }
    }

    private func legacyForm(kind: FormFieldPlacementKind, marked: Bool = true, readOnly: Bool = false) throws -> URL {
        let url = directory.appendingPathComponent(UUID().uuidString + ".pdf")
        let pdf = try XCTUnwrap(PDFDocument(data: SampleForm.data()))
        let field = PDFAnnotation(bounds: CGRect(x: 190, y: 180, width: 230, height: 60), forType: .widget, withProperties: nil)
        switch kind {
        case .signature: field.widgetFieldType = .signature
        case .checkbox:
            field.widgetFieldType = .button
            field.widgetControlType = .checkBoxControl
            field.buttonWidgetStateString = "Yes"
            field.buttonWidgetState = .onState
        default:
            field.widgetFieldType = .text
            field.widgetStringValue = "Saved answer"
            field.widgetDefaultStringValue = "Default answer"
            field.font = .systemFont(ofSize: 16)
            field.isMultiline = kind == .multilineText
        }
        field.fieldName = "Legacy field"
        field.setValue("Original label", forAnnotationKey: .widgetTextLabelUI)
        field.setValue(NSNumber(value: 2 | (readOnly ? 1 : 0)), forAnnotationKey: .widgetFieldFlags)
        if marked {
            field.contents = "Folik form field"
            field.setValue(kind.rawValue, forAnnotationKey: PDFAnnotationKey(rawValue: "FolikFieldKind"))
            field.setValue(17, forAnnotationKey: PDFAnnotationKey(rawValue: "FolikFieldOrder"))
        }
        field.backgroundColor = .white
        field.color = FolikTheme.annotationBlue
        let border = PDFBorder(); border.lineWidth = 1.5; field.border = border
        pdf.page(at: 0)?.annotations.first { $0.fieldName == "Name" }?.widgetStringValue = "Existing customer"
        pdf.page(at: 0)?.addAnnotation(field)
        XCTAssertTrue(pdf.write(to: url))
        return url
    }

    func testOlderFolikFieldsAreRepairedOnceWithoutLosingData() throws {
        for kind in FormFieldPlacementKind.allCases {
            let url = try legacyForm(kind: kind)
            let original = try XCTUnwrap(PDFDocument(url: url)?.page(at: 0)?.annotations.last)
            let item = LibraryDocument(url: url, pageCount: 1, fileSize: 0, modifiedAt: Date())
            let session = DocumentSession(item: item)
            XCTAssertEqual(session.successfulSaveCount, 1)
            let page = try XCTUnwrap(PDFDocument(url: url)?.page(at: 0))
            let repaired = try XCTUnwrap(page.annotations.last)
            XCTAssertEqual(page.annotations.count, 5)
            XCTAssertEqual(page.annotations.first { $0.fieldName == "Name" }?.widgetStringValue, "Existing customer")
            XCTAssertEqual(repaired.fieldName, original.fieldName)
            XCTAssertEqual(repaired.bounds, original.bounds)
            XCTAssertEqual(repaired.widgetStringValue, original.widgetStringValue)
            XCTAssertEqual(repaired.widgetDefaultStringValue, original.widgetDefaultStringValue)
            XCTAssertEqual(repaired.buttonWidgetState, original.buttonWidgetState)
            XCTAssertEqual(repaired.value(forAnnotationKey: .widgetFieldFlags) as? NSNumber,
                           original.value(forAnnotationKey: .widgetFieldFlags) as? NSNumber)
            XCTAssertEqual(repaired.value(forAnnotationKey: .widgetTextLabelUI) as? String, "Original label")
            XCTAssertEqual(repaired.value(forAnnotationKey: PDFAnnotationKey(rawValue: "FolikFieldOrder")) as? NSNumber,
                           original.value(forAnnotationKey: PDFAnnotationKey(rawValue: "FolikFieldOrder")) as? NSNumber)
            try assertVisibleBorder(on: page, bounds: repaired.bounds, kind: kind)
            let flattened = try DocumentExporter.export(sourceURL: url, mode: .flattened, root: directory)
            try assertVisibleBorder(on: XCTUnwrap(PDFDocument(url: flattened)?.page(at: 0)), bounds: repaired.bounds, kind: kind)
            let catalog = try FormTemplateTests.canonicalValues(XCTUnwrap(PDFDocument(url: url)))
            XCTAssertEqual(Set(catalog.keys), Set(session.formFields.compactMap { $0.annotation.fieldName }))
            XCTAssertEqual(catalog["Name"], "Existing customer")
            if kind == .checkbox { XCTAssertEqual(catalog["Legacy field"], "Yes") }
            else if kind != .signature { XCTAssertEqual(catalog["Legacy field"], "Saved answer") }
            let attachment = XCTAttachment(data: try Data(contentsOf: url), uniformTypeIdentifier: "com.adobe.pdf")
            attachment.name = "repaired-\(kind.rawValue)"; attachment.lifetime = .keepAlways; add(attachment)
            let data = try Data(contentsOf: url)
            let reopened = DocumentSession(item: item)
            XCTAssertEqual(reopened.successfulSaveCount, 0)
            XCTAssertEqual(try Data(contentsOf: url), data)
        }
    }

    func testBorderRepairPreservesExternalAndReadOnlyFields() throws {
        for (marked, readOnly) in [(false, false), (true, true)] {
            let url = try legacyForm(kind: .text, marked: marked, readOnly: readOnly)
            let original = try Data(contentsOf: url)
            let session = DocumentSession(item: LibraryDocument(url: url, pageCount: 1, fileSize: 0, modifiedAt: Date()))
            XCTAssertEqual(session.successfulSaveCount, 0)
            XCTAssertFalse(session.isModified)
            XCTAssertEqual(try Data(contentsOf: url), original)
        }
    }

    func testBorderRepairLeavesStyledAndSignedDocumentsUntouched() throws {
        let styled = try legacyForm(kind: .text)
        let pdf = try XCTUnwrap(PDFDocument(url: styled))
        let appearance = PDFAppearanceCharacteristics()
        appearance.borderColor = .red
        pdf.page(at: 0)?.annotations.last?.setValue(appearance, forAnnotationKey: .widgetAppearanceDictionary)
        XCTAssertTrue(pdf.write(to: styled))
        let signed = directory.appendingPathComponent("Signed.pdf")
        // Structurally signed fixture; it does not claim cryptographic validity.
        let objects = [
            "<< /Type /Catalog /Pages 2 0 R /AcroForm << /Fields [4 0 R 5 0 R] >> >>",
            "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Annots [4 0 R 5 0 R] >>",
            "<< /Type /Annot /Subtype /Widget /FT /Tx /T (Legacy) /Rect [190 180 420 240] /Contents (Folik form field) /V (Saved answer) >>",
            "<< /Type /Annot /Subtype /Widget /FT /Sig /T (Signed) /Rect [40 40 140 70] /V 6 0 R >>",
            "<< /Type /Sig /ByteRange [0 10 20 30] /Contents <0011> >>"
        ]
        var data = Data("%PDF-1.7\n".utf8)
        var offsets = [0]
        for (index, object) in objects.enumerated() {
            offsets.append(data.count)
            data.append(Data("\(index + 1) 0 obj\n\(object)\nendobj\n".utf8))
        }
        let xref = data.count
        data.append(Data("xref\n0 \(offsets.count)\n0000000000 65535 f \n".utf8))
        for offset in offsets.dropFirst() { data.append(Data(String(format: "%010d 00000 n \n", offset).utf8)) }
        data.append(Data("trailer\n<< /Size \(offsets.count) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n".utf8))
        try data.write(to: signed)
        XCTAssertEqual(try PDFPrivacy.inspect(data).signedSignatureCount, 1)
        for url in [styled, signed] {
            let original = try Data(contentsOf: url)
            let session = DocumentSession(item: LibraryDocument(url: url, pageCount: 1, fileSize: 0, modifiedAt: Date()))
            XCTAssertEqual(session.successfulSaveCount, 0, url.lastPathComponent)
            XCTAssertEqual(try Data(contentsOf: url), original)
        }
    }

    func testBorderRepairRecognizesFieldsFromBeforeKindMetadata() throws {
        let url = try legacyForm(kind: .text)
        let pdf = try XCTUnwrap(PDFDocument(url: url))
        pdf.page(at: 0)?.annotations.last?.removeValue(forAnnotationKey: PDFAnnotationKey(rawValue: "FolikFieldKind"))
        XCTAssertTrue(pdf.write(to: url))
        let session = DocumentSession(item: LibraryDocument(url: url, pageCount: 1, fileSize: 0, modifiedAt: Date()))
        XCTAssertEqual(session.successfulSaveCount, 1)
        let page = try XCTUnwrap(PDFDocument(url: url)?.page(at: 0))
        try assertVisibleBorder(on: page, bounds: XCTUnwrap(page.annotations.last).bounds, kind: .text)
    }

    func testBorderRepairFailedSavePreservesOriginalAndCanRetry() async throws {
        let url = try legacyForm(kind: .text)
        let original = try Data(contentsOf: url)
        var fail = true
        let session = DocumentSession(item: LibraryDocument(url: url, pageCount: 1, fileSize: 0, modifiedAt: Date()),
            deferredPreparation: true, saveDocument: { document, destination in
                if fail { throw CocoaError(.fileWriteOutOfSpace) }
                try PDFDocumentPersistence.save(document, to: destination)
            })
        await session.prepareForReading()
        XCTAssertTrue(session.isModified)
        XCTAssertTrue(session.saveFailed)
        XCTAssertEqual(try Data(contentsOf: url), original)
        fail = false
        XCTAssertTrue(session.persistChanges())
        XCTAssertFalse(session.saveFailed)
        XCTAssertFalse(session.isModified)
        XCTAssertEqual(session.formFields.last?.annotation.widgetStringValue, "Saved answer")
    }

    private func assertVisibleBorder(on renderedPage: PDFPage, bounds: CGRect, kind: FormFieldPlacementKind) throws {
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

    func testAuthoredFieldOutlineRemainsVisibleInBuildAndFillModes() throws {
        let (session, coordinator, page) = try fixture(rotation: 0, scale: 1)
        session.setFormMode(.build)
        session.beginFormFieldPlacement(.text, label: "Always outlined", isRequired: false)
        session.placeAnnotation(pageIndex: 1, point: CGPoint(x: 306, y: 396))
        coordinator.updateDrawingState()

        let outline = try XCTUnwrap(coordinator.pdfView.layer.sublayers?
            .compactMap { $0 as? CAShapeLayer }
            .first { $0.lineDashPattern == nil && $0.lineWidth == 1.5 && $0.path != nil })
        XCTAssertFalse(outline.isHidden)
        XCTAssertNotNil(outline.path)

        session.setFormMode(.fill)
        coordinator.updateDrawingState()
        XCTAssertFalse(outline.isHidden)
        XCTAssertNotNil(outline.path)
        XCTAssertEqual(outline.fillColor, UIColor.clear.cgColor)

        let expected = coordinator.pdfView.convert(
            try XCTUnwrap(session.formFields.first?.annotation.bounds),
            from: page
        ).standardized
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

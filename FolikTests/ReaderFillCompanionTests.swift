import SwiftUI
import PDFKit
import UIKit
import XCTest
@testable import Folik

@MainActor
final class ReaderFillCompanionTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: root)
    }

    func testSelectedTextEditorUpdatesLivePDFAndPersistsWithoutNavigatingOnOpen() async throws {
        let session = try makeSession()
        let field = try XCTUnwrap(session.formFields.first)
        let commandID = session.command?.id
        let selection = try XCTUnwrap(session.document?.findString("Fixture", withOptions: []).first)
        session.reportSelection(selection)

        session.prepareFillCompanion()
        XCTAssertEqual(session.selectedFillFieldID, field.id)
        XCTAssertEqual(session.command?.id, commandID)
        XCTAssertTrue(session.hasTextSelection)
        XCTAssertTrue(session.setFillFieldValue(fieldID: field.id, value: "Ada Lovelace"))
        XCTAssertEqual(field.annotation.widgetStringValue, "Ada Lovelace")
        XCTAssertEqual(session.completedFormFieldCount, 1)
        let saved = await session.saveForSharing()
        XCTAssertTrue(saved)
        let reopened = try XCTUnwrap(PDFDocument(url: session.item.url))
        XCTAssertEqual(reopened.page(at: 0)?.annotations.first?.widgetStringValue, "Ada Lovelace")
    }

    func testExplicitFieldNavigationAndNextUnfinishedRetainSelectionAcrossRecomposition() async throws {
        let session = try makeSession()
        session.beginFormFieldPlacement(.text, label: "Second", isRequired: true)
        session.placeAnnotationAtCurrentPageCenter()
        session.setFormMode(.fill)
        let second = try XCTUnwrap(session.formFields.first { $0.title == "Second" })
        session.goToFormField(second)
        XCTAssertEqual(session.selectedFillFieldID, second.id)
        let commandID = session.command?.id
        session.prepareFillCompanion()
        session.prepareFillCompanion()
        XCTAssertEqual(session.selectedFillFieldID, second.id)
        XCTAssertEqual(session.command?.id, commandID)
        XCTAssertTrue(session.setFillFieldValue(fieldID: second.id, value: "Done"))
        session.goToNextIncompleteFormField()
        XCTAssertEqual(session.selectedFillFieldID, session.formFields.first?.id)
        let saved = await session.saveForSharing()
        XCTAssertTrue(saved)
    }

    func testCheckboxEditorUpdatesAllLogicalDuplicatesAndCompletionOnce() async throws {
        let first = widget("Consent", type: .button)
        let duplicate = widget("Consent", type: .button)
        for field in [first, duplicate] {
            field.widgetControlType = .checkBoxControl
            field.buttonWidgetStateString = "Yes"
            field.buttonWidgetState = .offState
        }
        let session = try makeSession(additionalWidgets: [first, duplicate])
        let checkbox = try XCTUnwrap(session.formFields.first { $0.kind == .checkbox })
        XCTAssertTrue(session.setFillFieldSelected(fieldID: checkbox.id, selected: true))
        let group = session.formFields.filter { $0.logicalID == checkbox.logicalID }
        XCTAssertEqual(group.count, 2)
        XCTAssertTrue(group.allSatisfy(\.isSelected))
        XCTAssertEqual(session.completedFormFieldCount, 1)
        XCTAssertEqual(session.fillableFormFieldCount, 2)
        XCTAssertTrue(session.setFillFieldSelected(fieldID: checkbox.id, selected: false))
        XCTAssertEqual(session.completedFormFieldCount, 0)
        let saved = await session.saveForSharing()
        XCTAssertTrue(saved)
    }

    func testRadioFieldsStayOnPageWorkflowWhenPDFKitCannotReliablyPersistTheirAppearance() async throws {
        let session = try makeRadioSession()
        let options = session.formFields.filter { $0.kind == .radio }
        XCTAssertEqual(options.count, 2)
        let first = try XCTUnwrap(options.first)
        let second = try XCTUnwrap(options.last)
        XCTAssertFalse(session.setFillFieldSelected(fieldID: first.id, selected: true))
        XCTAssertFalse(session.setFillFieldSelected(fieldID: second.id, selected: true))
        XCTAssertTrue(session.formFields.allSatisfy { !$0.isSelected })
        XCTAssertEqual(session.completedFormFieldCount, 0)
        session.selectFillField(second.id)
        XCTAssertEqual(session.selectedFillFieldID, second.id)
        guard case .goToAnnotation(let annotation, _) = session.command?.action else {
            return XCTFail("Unsupported companion fields must still navigate to the actual PDF widget")
        }
        XCTAssertTrue(annotation === second.annotation)
        let saved = await session.saveForSharing()
        XCTAssertTrue(saved)
    }

    func testChoiceEditorSavesExportValueAndRejectsUnlistedValues() async throws {
        let choice = widget("Color", type: .choice)
        choice.choices = ["Red", "Blue"]
        choice.values = ["red", "blue"]
        let session = try makeSession(additionalWidgets: [choice])
        let field = try XCTUnwrap(session.formFields.first { $0.kind == .choice })
        XCTAssertTrue(session.setFillFieldValue(fieldID: field.id, value: "blue"))
        XCTAssertFalse(session.setFillFieldValue(fieldID: field.id, value: "unlisted"))
        XCTAssertEqual(field.annotation.widgetStringValue, "Blue")
        XCTAssertEqual(field.annotation.value(forAnnotationKey: .widgetValue) as? String, "blue")
        let saved = await session.saveForSharing()
        XCTAssertTrue(saved)
        let reopened = try XCTUnwrap(PDFDocument(url: session.item.url))
        let savedField = try XCTUnwrap(reopened.page(at: 0)?.annotations.first { $0.fieldName == "Color" })
        XCTAssertEqual(savedField.widgetStringValue, "Blue")
        XCTAssertEqual(savedField.value(forAnnotationKey: .widgetValue) as? String, "blue")
    }

    func testTextMutationHonorsLiveReadOnlyDuplicatesRemovedWidgetsAndUnsupportedKinds() async throws {
        let duplicate = widget("Full name", type: .text)
        let signature = widget("Approval", type: .signature)
        let multiline = widget("Notes", type: .text)
        multiline.isMultiline = true
        let session = try makeSession(additionalWidgets: [duplicate, signature, multiline])
        let name = try XCTUnwrap(session.formFields.first)
        XCTAssertTrue(session.setFillFieldValue(fieldID: name.id, value: "Shared"))
        XCTAssertTrue(session.formFields.filter { $0.logicalID == name.logicalID }.allSatisfy { $0.value == "Shared" })
        let liveDuplicate = try XCTUnwrap(session.formFields.first { $0.logicalID == name.logicalID && $0.id != name.id })
        liveDuplicate.annotation.isReadOnly = true // Cached field still says editable.
        XCTAssertFalse(session.setFillFieldValue(fieldID: name.id, value: "Must not overwrite"))
        XCTAssertEqual(name.annotation.widgetStringValue, "Shared")
        let sign = try XCTUnwrap(session.formFields.first { $0.kind == .signature })
        XCTAssertFalse(session.setFillFieldValue(fieldID: sign.id, value: "Not a signature"))
        XCTAssertNil(sign.annotation.widgetStringValue)
        let notes = try XCTUnwrap(session.formFields.first { $0.kind == .multilineText })
        XCTAssertTrue(session.setFillFieldValue(fieldID: notes.id, value: "First line\nSecond line"))
        XCTAssertEqual(notes.annotation.widgetStringValue, "First line\nSecond line")
        session.document?.page(at: 0)?.removeAnnotation(notes.annotation)
        XCTAssertFalse(session.setFillFieldValue(fieldID: notes.id, value: "Stale"))
        XCTAssertEqual(notes.annotation.widgetStringValue, "First line\nSecond line")
        let saved = await session.saveForSharing()
        XCTAssertTrue(saved)
    }

    func testSelectedFieldIdentitySurvivesEarlierAnnotationDeletionAndRejectsRemovedWidget() async throws {
        let session = try makeSession()
        session.beginAnnotationPlacement(.note, text: "Before the widgets")
        session.placeAnnotationAtCurrentPageCenter()
        let note = try XCTUnwrap(session.annotations.first)
        let page = try XCTUnwrap(session.document?.page(at: 0))
        let target = widget("Repeated answer", type: .text)
        let duplicates = [widget("Repeated answer", type: .text), widget("Repeated answer", type: .text)]
        let unrelated = widget("Unrelated answer", type: .text)
        for annotation in [target] + duplicates + [unrelated] { page.addAnnotation(annotation) }
        session.refreshFormState(markModified: false)
        let displayed = try XCTUnwrap(session.formFields.first { $0.annotation === target })
        let originalIndex = try XCTUnwrap(page.annotations.firstIndex { $0 === target })
        session.selectFillField(displayed.id)

        session.deleteAnnotation(note)
        XCTAssertLessThan(try XCTUnwrap(page.annotations.firstIndex { $0 === target }), originalIndex)
        session.selectFillField(displayed.id)
        guard case .goToAnnotation(let navigated, _) = session.command?.action else {
            return XCTFail("Selecting the displayed field must still navigate to its widget")
        }
        XCTAssertTrue(navigated === target, "A shifted index must not select a logical duplicate instead")
        XCTAssertTrue(session.setFillFieldValue(fieldID: displayed.id, value: "Original answer"))
        XCTAssertTrue(([target] + duplicates).allSatisfy { $0.widgetStringValue == "Original answer" })
        XCTAssertNil(unrelated.widgetStringValue)
        session.refreshFormState(markModified: false)
        session.prepareFillCompanion()
        XCTAssertEqual(session.selectedFillFieldID, displayed.id)
        XCTAssertTrue(session.selectedFillField?.annotation === target)
        XCTAssertEqual(session.formFields.filter { $0.logicalID == displayed.logicalID }.count, 3)

        session.undoAnnotationAction()
        XCTAssertTrue(page.annotations.contains { $0 === note.annotation })
        session.refreshFormState(markModified: false)
        XCTAssertTrue(session.selectedFillField?.annotation === target)
        XCTAssertTrue(session.setFillFieldValue(fieldID: displayed.id, value: "After undo"))
        session.redoAnnotationAction()
        XCTAssertFalse(page.annotations.contains { $0 === note.annotation })
        XCTAssertTrue(session.setFillFieldValue(fieldID: displayed.id, value: "After redo"))

        // A new same-name widget occupies the removed widget's original numeric slot.
        page.removeAnnotation(target)
        page.removeAnnotation(unrelated)
        let replacement = widget("Repeated answer", type: .text)
        page.addAnnotation(replacement)
        XCTAssertTrue(page.annotations[originalIndex] === replacement)
        XCTAssertFalse(session.setFillFieldValue(fieldID: displayed.id, value: "Stale edit"))
        XCTAssertNil(session.selectedFillField)
        let commandID = session.command?.id
        session.selectFillField(displayed.id)
        XCTAssertEqual(session.command?.id, commandID)
        session.refreshFormState(markModified: false)
        XCTAssertFalse(session.setFillFieldValue(fieldID: displayed.id, value: "Still stale"))
        XCTAssertTrue(duplicates.allSatisfy { $0.widgetStringValue == "After redo" })
        XCTAssertNil(replacement.widgetStringValue)
        XCTAssertEqual(target.widgetStringValue, "After redo")
        let saved = await session.saveForSharing()
        XCTAssertTrue(saved)
    }

    func testUndoOfEarlierAnnotationKeepsCheckboxAndChoiceIDsBoundToLiveWidgets() async throws {
        let session = try makeSession()
        session.beginAnnotationPlacement(.note, text: "Undo before widgets")
        session.placeAnnotationAtCurrentPageCenter()
        let page = try XCTUnwrap(session.document?.page(at: 0))
        let checkbox = widget("Consent", type: .button)
        checkbox.widgetControlType = .checkBoxControl
        checkbox.buttonWidgetStateString = "Yes"
        checkbox.buttonWidgetState = .offState
        let choice = widget("Color", type: .choice)
        choice.choices = ["Red", "Blue"]
        choice.values = ["red", "blue"]
        for annotation in [checkbox, choice] { page.addAnnotation(annotation) }
        session.refreshFormState(markModified: false)
        let displayedCheckbox = try XCTUnwrap(session.formFields.first { $0.annotation === checkbox })
        let displayedChoice = try XCTUnwrap(session.formFields.first { $0.annotation === choice })
        let originalIndex = try XCTUnwrap(page.annotations.firstIndex { $0 === checkbox })
        session.selectFillField(displayedCheckbox.id, navigate: false)

        session.undoAnnotationAction()
        XCTAssertLessThan(try XCTUnwrap(page.annotations.firstIndex { $0 === checkbox }), originalIndex)
        XCTAssertTrue(session.setFillFieldSelected(fieldID: displayedCheckbox.id, selected: true))
        XCTAssertEqual(checkbox.buttonWidgetState, .onState)
        XCTAssertEqual(session.fillFieldChoices(fieldID: displayedChoice.id).map(\.value), ["red", "blue"])
        XCTAssertTrue(session.setFillFieldValue(fieldID: displayedChoice.id, value: "blue"))
        session.refreshFormState(markModified: false)
        session.prepareFillCompanion()
        XCTAssertEqual(session.selectedFillFieldID, displayedCheckbox.id)
        XCTAssertTrue(session.selectedFillField?.annotation === checkbox)
        session.redoAnnotationAction()
        XCTAssertTrue(session.setFillFieldSelected(fieldID: displayedCheckbox.id, selected: false))
        XCTAssertEqual(checkbox.buttonWidgetState, .offState)
        page.removeAnnotation(checkbox)
        XCTAssertFalse(session.setFillFieldSelected(fieldID: displayedCheckbox.id, selected: true))
        page.removeAnnotation(choice)
        XCTAssertTrue(session.fillFieldChoices(fieldID: displayedChoice.id).isEmpty)
        XCTAssertFalse(session.setFillFieldValue(fieldID: displayedChoice.id, value: "red"))
        let saved = await session.saveForSharing()
        XCTAssertTrue(saved)
    }

    func testMultiSelectChoicesAreNotSilentlyReducedToOneValue() throws {
        let choice = widget("Options", type: .choice)
        choice.choices = ["One", "Two"]
        choice.setValue(NSNumber(value: 1 << 21), forAnnotationKey: .widgetFieldFlags)
        let session = try makeSession(additionalWidgets: [choice])
        let field = try XCTUnwrap(session.formFields.first { $0.kind == .choice })
        XCTAssertTrue(session.fillFieldChoices(fieldID: field.id).isEmpty)
        XCTAssertFalse(session.setFillFieldValue(fieldID: field.id, value: "One"))
        XCTAssertFalse(session.setFillFieldValue(fieldID: "deleted-field", value: "No"))
    }

    func testTextMaximumLengthIsNotBypassedByCompanion() throws {
        let session = try makeSession()
        let field = try XCTUnwrap(session.formFields.first)
        field.annotation.maximumLength = 3
        XCTAssertFalse(session.setFillFieldValue(fieldID: field.id, value: "Too long"))
        XCTAssertNil(field.annotation.widgetStringValue)
    }

    func testCheckedValuePersistsAndLockedDocumentsRejectMutation() async throws {
        let checkbox = widget("Consent", type: .button)
        checkbox.widgetControlType = .checkBoxControl
        checkbox.buttonWidgetStateString = "Yes"
        checkbox.buttonWidgetState = .offState
        let session = try makeSession(additionalWidgets: [checkbox])
        let field = try XCTUnwrap(session.formFields.first { $0.kind == .checkbox })
        XCTAssertTrue(session.setFillFieldSelected(fieldID: field.id, selected: true))
        let saved = await session.saveForSharing()
        XCTAssertTrue(saved)
        let reopened = try XCTUnwrap(PDFDocument(url: session.item.url))
        XCTAssertEqual(reopened.page(at: 0)?.annotations.first { $0.fieldName == "Consent" }?.buttonWidgetState, .onState)
        let protected = try PDFProtection.protect(try Data(contentsOf: session.item.url), password: "test password")
        try protected.data.write(to: session.item.url)
        let locked = DocumentSession(item: session.item)
        XCTAssertTrue(locked.isLocked)
        XCTAssertFalse(locked.setFillFieldValue(fieldID: session.formFields[0].id, value: "Blocked"))
        XCTAssertFalse(locked.setFillFieldSelected(fieldID: field.id, selected: false))
    }

    func testNativeCompanionHostsOnlySelectedEditorWithoutChangingPDFNavigation() async throws {
        let session = try makeSession(additionalWidgets: [widget("Other answer", type: .text)])
        let originalCommand = session.command?.id
        let selection = try XCTUnwrap(session.document?.findString("Fixture", withOptions: []).first)
        session.reportSelection(selection)
        let controller = UIHostingController(rootView: ReaderFillCompanion(session: session, close: {}))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 420, height: 680)
        window.rootViewController = controller
        window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        controller.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        controller.view.layoutIfNeeded()
        XCTAssertEqual(session.selectedFillFieldID, session.formFields.first?.id)
        XCTAssertEqual(session.command?.id, originalCommand)
        XCTAssertTrue(session.hasTextSelection)
        let textFields = descendants(of: controller.view).compactMap { $0 as? UITextField }
        XCTAssertEqual(textFields.count, 1, "The companion must not reproduce the entire form")
        let editor = try XCTUnwrap(textFields.first)
        editor.text = "Entered in companion"
        editor.sendActions(for: .editingChanged)
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(session.formFields.first?.value, "Entered in companion")
        controller.rootView = ReaderFillCompanion(session: session, close: {})
        controller.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(session.selectedFillFieldID, session.formFields.first?.id)
        XCTAssertEqual(session.command?.id, originalCommand)
        XCTAssertEqual(descendants(of: controller.view).compactMap { $0 as? UITextField }.first?.text, "Entered in companion")
        let saved = await session.saveForSharing()
        XCTAssertTrue(saved)
    }

    private func descendants(of view: UIView) -> [UIView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }

    // Real AcroForm appearances are required: PDFKit's synthesized radio widgets
    // otherwise round-trip every export name as "Yes", which is not a safe radio group.
    private func makeRadioSession() throws -> DocumentSession {
        let offAppearance = "0 0 0 RG 1 1 18 18 re S\n"
        let onAppearance = "0 0 0 rg 1 1 18 18 re f\n"
        let objects = [
            "<< /Type /Catalog /Pages 2 0 R /AcroForm 4 0 R >>",
            "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Annots [6 0 R 7 0 R] >>",
            "<< /Fields [5 0 R] >>",
            "<< /FT /Btn /Ff 32768 /T (Contact) /Kids [6 0 R 7 0 R] >>",
            "<< /Type /Annot /Subtype /Widget /Parent 5 0 R /P 3 0 R /Rect [30 600 50 620] /AP << /N << /Off 8 0 R /Email 9 0 R >> >> /AS /Off >>",
            "<< /Type /Annot /Subtype /Widget /Parent 5 0 R /P 3 0 R /Rect [80 600 100 620] /AP << /N << /Off 8 0 R /Phone 9 0 R >> >> /AS /Off >>",
            "<< /Type /XObject /Subtype /Form /BBox [0 0 20 20] /Resources << >> /Length \(offAppearance.utf8.count) >>\nstream\n\(offAppearance)endstream",
            "<< /Type /XObject /Subtype /Form /BBox [0 0 20 20] /Resources << >> /Length \(onAppearance.utf8.count) >>\nstream\n\(onAppearance)endstream"
        ]
        var text = "%PDF-1.7\n"
        var offsets = [0]
        for (index, object) in objects.enumerated() {
            offsets.append(text.utf8.count)
            text += "\(index + 1) 0 obj\n\(object)\nendobj\n"
        }
        let xref = text.utf8.count
        text += "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n"
        for offset in offsets.dropFirst() { text += String(format: "%010d 00000 n \n", offset) }
        text += "trailer\n<< /Size \(objects.count + 1) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n"
        let url = root.appendingPathComponent("Radios.pdf")
        try Data(text.utf8).write(to: url)
        return DocumentSession(item: LibraryDocument(url: url, pageCount: 1, fileSize: Int64(text.utf8.count), modifiedAt: Date()))
    }

    private func widget(_ name: String, type: PDFAnnotationWidgetSubtype) -> PDFAnnotation {
        let field = PDFAnnotation(bounds: CGRect(x: 30, y: 450, width: 180, height: 30), forType: .widget, withProperties: nil)
        field.widgetFieldType = type
        field.fieldName = name
        return field
    }

    private func makeSession(additionalWidgets: [PDFAnnotation] = []) throws -> DocumentSession {
        let url = root.appendingPathComponent("Form.pdf")
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))
        let data = renderer.pdfData { context in
            context.beginPage()
            ("Fixture" as NSString).draw(at: CGPoint(x: 30, y: 30), withAttributes: [.font: UIFont.systemFont(ofSize: 16)])
        }
        let pdf = try XCTUnwrap(PDFDocument(data: data))
        let field = PDFAnnotation(bounds: CGRect(x: 30, y: 600, width: 200, height: 30), forType: .widget, withProperties: nil)
        field.widgetFieldType = .text
        field.fieldName = "Full name"
        pdf.page(at: 0)?.addAnnotation(field)
        for widget in additionalWidgets { pdf.page(at: 0)?.addAnnotation(widget) }
        XCTAssertTrue(pdf.write(to: url))
        let item = LibraryDocument(url: url, pageCount: 1, fileSize: Int64(data.count), modifiedAt: Date())
        return DocumentSession(item: item)
    }
}

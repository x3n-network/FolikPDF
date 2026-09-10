import PDFKit
import UIKit
import XCTest
@testable import Folik

@MainActor
final class FormTemplateTests: XCTestCase {
    func testTemplatesPreserveValuesAndAlwaysStartBlank() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = DocumentLibrary(documentsDirectory: root)
        for template in FormTemplate.allCases {
            let original = try template.data()
            let first = try await library.importConvertedPDF(.preparedPDF(original), named: template.title)
            let session = DocumentSession(item: first)
            let expectedCount = template == .meetingNotes ? 7 : 10
            XCTAssertEqual(session.pageCount, 1)
            XCTAssertEqual(session.formFields.count, expectedCount)
            XCTAssertEqual(session.completedFormFieldCount, 0)
            let blank = try XCTUnwrap(PDFDocument(data: original)?.page(at: 0))
            let attachment = XCTAttachment(image: blank.thumbnail(of: CGSize(width: 1224, height: 1584), for: .mediaBox))
            attachment.name = template.id + "-blank"; attachment.lifetime = .keepAlways; add(attachment)
            let text = try XCTUnwrap(session.formFields.first { $0.kind == .text })
            text.annotation.widgetStringValue = "Pat Example"
            let notes = try XCTUnwrap(session.formFields.first { $0.kind == .multilineText })
            notes.annotation.widgetStringValue = "First line\nFollow-up next week"
            let checkbox = session.formFields.first { $0.kind == .checkbox }
            checkbox?.annotation.buttonWidgetState = .onState
            session.noteFormEditing()
            let saved = await session.saveForSharing()
            XCTAssertTrue(saved)
            let reopened = DocumentSession(item: first)
            XCTAssertEqual(reopened.formFields.count, expectedCount)
            XCTAssertEqual(reopened.formFields.first { $0.title == text.title }?.annotation.widgetStringValue, "Pat Example")
            XCTAssertEqual(reopened.completedFormFieldCount, checkbox == nil ? 2 : 3)
            let document = try XCTUnwrap(PDFDocument(url: first.url))
            let canonicalFields = try canonicalValues(document)
            XCTAssertEqual(Set(canonicalFields.keys), Set(reopened.formFields.map(\.title)))
            XCTAssertEqual(canonicalFields[text.title], "Pat Example")
            XCTAssertEqual(canonicalFields[notes.title], "First line\nFollow-up next week")
            if let checkbox { XCTAssertEqual(canonicalFields[checkbox.title], "Yes") }
            let filled = XCTAttachment(image: try XCTUnwrap(document.page(at: 0)).thumbnail(of: CGSize(width: 1224, height: 1584), for: .mediaBox))
            filled.name = template.id + "-filled"; filled.lifetime = .keepAlways; add(filled)
            for field in reopened.formFields {
                XCTAssertTrue(blank.bounds(for: .mediaBox).contains(field.annotation.bounds))
            }
            let second = try await library.importConvertedPDF(.preparedPDF(template.data()), named: template.title)
            XCTAssertNotEqual(first.url, second.url)
            XCTAssertEqual(DocumentSession(item: second).completedFormFieldCount, 0)
            XCTAssertEqual(try template.data(), original)
        }
    }

    func testPersonalTemplatesClearOrKeepValuesAndPersistIndependently() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let pdf = try XCTUnwrap(PDFDocument(data: FormTemplate.workOrder.data()))
        let widgets = try XCTUnwrap(pdf.page(at: 0)).annotations
        let text = try XCTUnwrap(widgets.first { $0.fieldName == "Customer or team" })
        text.widgetStringValue = "My Company"
        text.widgetDefaultStringValue = "Old Default"
        let check = try XCTUnwrap(widgets.first { $0.widgetFieldType == .button })
        check.buttonWidgetState = .onState
        let source = try XCTUnwrap(pdf.dataRepresentation())
        let library = DocumentLibrary(documentsDirectory: root)
        try await library.saveTemplate(source, named: "Weekly Work", clearAnswers: true)
        try await library.saveTemplate(source, named: "Weekly Work", clearAnswers: false)
        XCTAssertEqual(library.personalTemplates.count, 2)
        XCTAssertNotEqual(library.personalTemplates[0].url, library.personalTemplates[1].url)
        XCTAssertTrue(library.documents.isEmpty)
        let blank = try XCTUnwrap(PDFDocument(url: library.personalTemplates[0].url))
        let kept = try XCTUnwrap(PDFDocument(url: library.personalTemplates[1].url))
        for template in library.personalTemplates {
            let attachment = XCTAttachment(data: try Data(contentsOf: template.url), uniformTypeIdentifier: "com.adobe.pdf")
            attachment.name = template.title; attachment.lifetime = .keepAlways; add(attachment)
        }
        XCTAssertEqual(try canonicalValues(blank)["Customer or team"], "")
        XCTAssertEqual(try canonicalValues(blank)["Work completed"], "Off")
        XCTAssertEqual(try canonicalValues(kept)["Customer or team"], "My Company")
        XCTAssertEqual(try canonicalValues(kept)["Work completed"], "Yes")
        XCTAssertEqual(try canonicalValues(blank).count, 10)
        XCTAssertEqual(blank.page(at: 0)?.annotations.first { $0.fieldName == "Customer or team" }?.widgetDefaultStringValue, "")
        let restored = DocumentLibrary(documentsDirectory: root)
        try await restored.refreshTemplates()
        XCTAssertEqual(restored.personalTemplates, library.personalTemplates)
        let master = library.personalTemplates[0]
        let data = try Data(contentsOf: master.url)
        let copy = try await library.importConvertedPDF(.preparedPDF(data), named: master.title)
        try library.deleteTemplate(master)
        XCTAssertTrue(FileManager.default.fileExists(atPath: copy.url.path))
        XCTAssertEqual(try Data(contentsOf: copy.url), data)
        XCTAssertEqual(text.widgetStringValue, "My Company")
    }

    private func canonicalValues(_ document: PDFDocument) throws -> [String: String] {
        let catalog = try XCTUnwrap(document.documentRef?.catalog)
        var acroForm: CGPDFDictionaryRef?
        XCTAssertTrue(CGPDFDictionaryGetDictionary(catalog, "AcroForm", &acroForm))
        var fields: CGPDFArrayRef?
        XCTAssertTrue(CGPDFDictionaryGetArray(try XCTUnwrap(acroForm), "Fields", &fields))
        // PDFKit may group fields under nonterminal parent dictionaries.
        // Follow Kids and inherited values instead of assuming a flat Fields array.
        var canonicalFields: [String: String] = [:]
        func visit(_ dictionary: CGPDFDictionaryRef, inheritedName: String = "", inheritedValue: String = "", depth: Int = 0) throws {
            XCTAssertLessThan(depth, 10)
            guard depth < 10 else { return }
            var nameString: CGPDFStringRef?
            let name = CGPDFDictionaryGetString(dictionary, "T", &nameString)
                ? (nameString.flatMap { CGPDFStringCopyTextString($0) as String? } ?? inheritedName) : inheritedName
            var valueString: CGPDFStringRef?
            var valueName: UnsafePointer<CChar>?
            let value: String
            if CGPDFDictionaryGetString(dictionary, "V", &valueString), let valueString {
                value = CGPDFStringCopyTextString(valueString) as String? ?? ""
            } else if CGPDFDictionaryGetName(dictionary, "V", &valueName), let valueName {
                value = String(cString: valueName)
            } else { value = inheritedValue }
            var kids: CGPDFArrayRef?
            if CGPDFDictionaryGetArray(dictionary, "Kids", &kids), let kids, CGPDFArrayGetCount(kids) > 0 {
                for index in 0..<CGPDFArrayGetCount(kids) {
                    var child: CGPDFDictionaryRef?
                    XCTAssertTrue(CGPDFArrayGetDictionary(kids, index, &child))
                    try visit(XCTUnwrap(child), inheritedName: name, inheritedValue: value, depth: depth + 1)
                }
            } else { canonicalFields[name] = value }
        }
        let roots = try XCTUnwrap(fields)
        for index in 0..<CGPDFArrayGetCount(roots) {
            var field: CGPDFDictionaryRef?
            XCTAssertTrue(CGPDFArrayGetDictionary(roots, index, &field))
            try visit(XCTUnwrap(field))
        }
        return canonicalFields
    }
}

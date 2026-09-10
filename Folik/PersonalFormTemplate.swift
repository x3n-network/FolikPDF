import Foundation
import PDFKit

nonisolated struct PersonalFormTemplate: Identifiable, Hashable, Sendable {
    let url: URL
    var id: String { url.lastPathComponent }
    var title: String { url.deletingPathExtension().lastPathComponent }
}

nonisolated enum PersonalTemplateStore {
    static func list(in root: URL) throws -> [PersonalFormTemplate] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
            .filter { $0.pathExtension.lowercased() == "pdf" && (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
            .map { PersonalFormTemplate(url: $0) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    static func save(_ data: Data, named name: String, clearAnswers: Bool, in root: URL) throws -> PersonalFormTemplate {
        let filename = try PDFConverter.fileName(name)
        let document = try PDFProcessing.document(data)
        guard try PDFPrivacy.inspect(data).signedSignatureCount == 0 else {
            throw TemplateError.signedDocument
        }
        if clearAnswers {
            for index in 0..<document.pageCount {
                for annotation in document.page(at: index)?.annotations ?? [] where annotation.type?.lowercased() == "widget" {
                    switch annotation.widgetFieldType {
                    case .text, .choice:
                        annotation.widgetStringValue = ""
                        annotation.widgetDefaultStringValue = ""
                        annotation.removeValue(forAnnotationKey: PDFAnnotationKey(rawValue: "/I"))
                    case .button:
                        if annotation.widgetControlType != .pushButtonControl {
                            annotation.buttonWidgetState = .offState
                            annotation.widgetDefaultStringValue = "Off"
                        }
                    default: break
                    }

                }
            }
        }
        guard let output = document.dataRepresentation(), PDFDocument(data: output) != nil else {
            throw CocoaError(.fileWriteUnknown)
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let base = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
        var destination = root.appendingPathComponent(filename)
        var suffix = 2
        while FileManager.default.fileExists(atPath: destination.path) {
            destination = root.appendingPathComponent("\(base) \(suffix).pdf")
            suffix += 1
        }
        try output.write(to: destination, options: [.atomic, .completeFileProtectionUnlessOpen])
        return PersonalFormTemplate(url: destination)
    }

    enum TemplateError: LocalizedError {
        case signedDocument
        var errorDescription: String? { "Use an unsigned original to create a reusable template." }
    }
}

import AppIntents
import UniformTypeIdentifiers

struct SanitizePDFIntent: AppIntent {
    static let title: LocalizedStringResource = "Sanitize PDF"
    static let description = IntentDescription(
        "Creates an image-only PDF without source metadata, selectable or hidden text, links, outlines, attachments, scripts, or editable objects. The original is unchanged."
    )
    static let openAppWhenRun = false

    @Parameter(title: "PDF", description: "The PDF to sanitize")
    var pdf: IntentFile

    static var parameterSummary: some ParameterSummary {
        Summary("Sanitize \(\.$pdf)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> & ProvidesDialog {
        let data = try await pdf.data(contentType: .pdf)
        let preview = try await PDFPrivacy.sanitize(data)
        let stem = URL(fileURLWithPath: pdf.filename).deletingPathExtension().lastPathComponent
        let output = IntentFile(
            data: preview.data,
            filename: stem + " Sanitized.pdf",
            type: .pdf
        )
        return .result(
            value: output,
            dialog: "Created a sanitized image-only copy. Review every page before sharing."
        )
    }
}

struct FolikShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SanitizePDFIntent(),
            phrases: [
                "Sanitize a PDF with \(.applicationName)",
                "Make a safe PDF copy with \(.applicationName)"
            ],
            shortTitle: "Sanitize PDF",
            systemImageName: "checkmark.shield"
        )
    }

    static var shortcutTileColor: ShortcutTileColor { .blue }
}

import SwiftUI
import UniformTypeIdentifiers

struct PrivacyReportView: View {
    var initialURL: URL? = nil
    let complete: (LibraryDocument) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var loadedInitialSource = false
    @State private var source: Data?
    @State private var sourceName: String?
    @State private var filename = "Sanitized Document"
    @State private var report: PDFPrivacyReport?
    @State private var showFiles = false
    @State private var busy = false
    @State private var status = ""
    @State private var error: String?
    @State private var task: Task<Void, Never>?
    @State private var preview: OfficePreview?

    var body: some View {
        NavigationStack {
            Form {
                sourceSection
                if let report {
                    overview(report)
                    findings(report)
                    sanitizeSection(report)
                }
                if busy {
                    Section {
                        ProgressView(status)
                        Button("Cancel Processing") { task?.cancel() }
                    }
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Inspect & Sanitize")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { task?.cancel(); dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button("Preview Sanitized Copy", action: sanitize)
                    .buttonStyle(.borderedProminent)
                    .frame(minHeight: 48)
                    .padding()
                    .background(.regularMaterial)
                    .disabled(busy || report == nil || (try? PDFConverter.fileName(filename)) == nil)
                    .accessibilityIdentifier("privacy.preview")
            }
            .fileImporter(isPresented: $showFiles, allowedContentTypes: [.pdf]) { result in
                switch result {
                case .success(let url): load(url)
                case .failure(let failure): error = failure.localizedDescription
                }
            }
            .sheet(item: $preview) {
                OfficePreviewView(preview: $0, filename: filename, complete: complete)
            }
            .interactiveDismissDisabled(busy)
            .onDisappear { task?.cancel() }
            .onAppear {
                guard !loadedInitialSource else { return }
                loadedInitialSource = true
                if let initialURL {
                    load(initialURL)
                    return
                }
                #if DEBUG
                let arguments = ProcessInfo.processInfo.arguments
                if let index = arguments.firstIndex(of: "--ui-test-pdf-source"),
                   index + 1 < arguments.count,
                   let data = Data(base64Encoded: arguments[index + 1]) {
                    load(data: data, name: "Test.pdf", filename: "Sanitized Test")
                }
                #endif
            }
        }
    }

    private var sourceSection: some View {
        Section {
            if let sourceName {
                Label(sourceName, systemImage: "doc.text.magnifyingglass")
                    .font(.subheadline.weight(.semibold))
                    .accessibilityIdentifier("privacy.source")
            }
            Button(source == nil ? "Choose PDF" : "Choose Another PDF") { showFiles = true }
                .frame(minHeight: 44)
                .disabled(busy)
            Text("Folik inspects this PDF on your device. The report highlights information and interactive objects that may travel with the file when you share it.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func overview(_ report: PDFPrivacyReport) -> some View {
        Section("Document overview") {
            LabeledContent("Pages", value: report.pageCount.formatted())
            LabeledContent("File size", value: ByteCountFormatter.string(fromByteCount: Int64(report.fileSize), countStyle: .file))
            LabeledContent("Pages with selectable text", value: "\(report.searchablePageCount) of \(report.pageCount)")
        }
    }

    @ViewBuilder
    private func findings(_ report: PDFPrivacyReport) -> some View {
        Section("Privacy report") {
            if report.metadata.isEmpty {
                reportRow("No document metadata found", detail: "No title, author, subject, keyword, creator, producer, or document dates were reported.", icon: "checkmark.shield")
            } else {
                DisclosureGroup("Document metadata (\(report.metadata.count))") {
                    ForEach(report.metadata) { item in
                        LabeledContent(item.name, value: item.value)
                            .font(.footnote)
                    }
                }
                .accessibilityIdentifier("privacy.metadata")
            }
            if report.filledFormFieldCount > 0 {
                reportRow("Filled form values", detail: "\(report.filledFormFieldCount) field\(report.filledFormFieldCount == 1 ? "" : "s") may contain entered information.", icon: "rectangle.and.pencil.and.ellipsis")
            }
            if report.signatureFieldCount > 0 {
                reportRow("Digital signature fields", detail: "\(report.signatureFieldCount) signature field\(report.signatureFieldCount == 1 ? "" : "s") found. Sanitizing creates a different PDF and invalidates existing digital signatures.", icon: "signature")
            }
            countRow("Form fields", count: report.formFieldCount, icon: "list.bullet.rectangle")
            countRow("Annotations and comments", count: report.annotationCount, icon: "note.text")
            countRow("Links", count: report.linkCount, icon: "link")
            countRow("Outline entries", count: report.outlineItemCount, icon: "list.bullet.indent")
            if report.hasEmbeddedFiles || report.attachmentCount > 0 {
                reportRow("Attachments or embedded files", detail: "The PDF can carry files beyond its visible pages.", icon: "paperclip")
            }
            if report.hasScriptsOrAutomaticActions {
                reportRow("Scripts or automatic actions", detail: "The document catalog contains JavaScript or an action that may run when the PDF is opened.", icon: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
            if report.itemCount == 0 && report.searchablePageCount == 0 {
                reportRow("No extra content found", detail: "Folik found only visible page content in the supported checks.", icon: "checkmark.shield")
            }
        }
    }

    private func sanitizeSection(_ report: PDFPrivacyReport) -> some View {
        Section("Sanitized copy") {
            TextField("Filename", text: $filename)
                .disabled(busy)
            Label("Keeps the visible appearance of each page", systemImage: "checkmark.circle")
            Label("Removes metadata and interactive objects", systemImage: "checkmark.circle")
            Label("Removes selectable and hidden text", systemImage: "checkmark.circle")
            Text("The new copy is image-only, so search, text selection, links, forms, document accessibility text, and digital-signature validity are lost. Review the preview before saving.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if report.signatureFieldCount > 0 {
                Label("Existing digital signatures will not remain valid", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.orange)
            }
        }
    }

    private func countRow(_ title: String, count: Int, icon: String) -> some View {
        reportRow(title, detail: "\(count) found", icon: icon)
    }

    private func reportRow(_ title: String, detail: String, icon: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(FolikTheme.cobalt)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }

    private func load(_ url: URL) {
        busy = true
        error = nil
        status = "Inspecting PDF…"
        source = nil
        report = nil
        preview = nil
        task = Task {
            defer { busy = false }
            do {
                let data = try await Task.detached {
                    try PDFConverter.readFile(url, maximumBytes: PDFProcessing.maximumBytes)
                }.value
                try Task.checkCancellation()
                let result = try await Task.detached { try PDFPrivacy.inspect(data) }.value
                try Task.checkCancellation()
                source = data
                sourceName = url.lastPathComponent
                filename = url.deletingPathExtension().lastPathComponent + " Sanitized"
                report = result
            } catch is CancellationError { }
            catch { self.error = error.localizedDescription }
        }
    }

    private func load(data: Data, name: String, filename: String) {
        busy = true
        error = nil
        status = "Inspecting PDF…"
        source = data
        sourceName = name
        self.filename = filename
        report = nil
        task = Task {
            defer { busy = false }
            do {
                let result = try await Task.detached { try PDFPrivacy.inspect(data) }.value
                try Task.checkCancellation()
                report = result
            } catch is CancellationError { }
            catch { self.error = error.localizedDescription }
        }
    }

    private func sanitize() {
        guard let source, !busy else { return }
        busy = true
        error = nil
        status = "Sanitizing PDF…"
        task = Task {
            defer { busy = false }
            let worker = Task.detached {
                try await PDFPrivacy.sanitize(source) { page, count in
                    await MainActor.run { status = "Sanitizing page \(page) of \(count)…" }
                }
            }
            do {
                let result = try await withTaskCancellationHandler(
                    operation: { try await worker.value },
                    onCancel: { worker.cancel() }
                )
                try Task.checkCancellation()
                preview = result
            } catch is CancellationError { }
            catch { self.error = error.localizedDescription }
        }
    }
}

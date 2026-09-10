import PDFKit
import SwiftUI
import UniformTypeIdentifiers

struct OfficeConversionView: View {
    let complete: (LibraryDocument) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showFiles = false
    @State private var sourceName = ""
    @State private var filename = "Document"
    @State private var sourceData: Data?
    @State private var extensionName = "docx"
    @State private var busy = false
    @State private var errorMessage: String?
    @State private var preview: OfficePreview?
    @State private var worker: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { showFiles = true } label: {
                        Label("Choose Document", systemImage: "folder")
                            .frame(minHeight: 44)
                    }
                    .disabled(busy)
                    .accessibilityIdentifier("office.chooseFile")
                    if !sourceName.isEmpty { Label(sourceName, systemImage: "doc.richtext") }
                } footer: {
                    Text("DOCX and ODT support styled conversion. Older Word (.doc) files use text recovery. Pages files can use a saved PDF preview when available. Up to 25 MB. For Google Docs, export a Word (.docx) copy first.")
                }
                Section("PDF filename") {
                    TextField("Filename", text: $filename).autocorrectionDisabled()
                        .disabled(busy)
                        .accessibilityIdentifier("office.filename")
                }
                Section {
                    Text("Folik converts text, headings, lists, embedded images, and basic tables on this device. Review the PDF before saving: fonts, spacing, and page breaks can differ from the original.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let errorMessage {
                    Section { ProcessingErrorView(message: errorMessage).accessibilityIdentifier("office.error") }
                }
            }
            .navigationTitle("Documents to PDF")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { worker?.cancel(); dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 10) {
                    if busy { ProcessingStatusView(status: "Preparing document…") { worker?.cancel() } }
                    Button("Preview PDF", action: preparePreview)
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .buttonStyle(.borderedProminent)
                        .disabled(busy || sourceData == nil || (try? PDFConverter.fileName(filename)) == nil)
                        .accessibilityIdentifier("office.preview")
                }
                .padding().background(.regularMaterial)
            }
            .fileImporter(isPresented: $showFiles,
                          allowedContentTypes: ["docx", "odt", "doc", "pages"].compactMap { UTType(filenameExtension: $0) }) { result in
                switch result {
                case .success(let url): load(url)
                case .failure(let error): errorMessage = error.localizedDescription
                }
            }
            .sheet(item: $preview) { preview in
                OfficePreviewView(preview: preview, filename: filename, complete: complete)
            }
            .interactiveDismissDisabled(busy)
            .onDisappear { worker?.cancel() }
            .onAppear {
                #if DEBUG
                let args = ProcessInfo.processInfo.arguments
                if let flag = args.firstIndex(of: "--ui-test-office-data"), flag + 2 < args.count, sourceData == nil,
                   let data = Data(base64Encoded: args[flag + 1]) {
                    sourceData = data
                    extensionName = args[flag + 2]
                    sourceName = "Office Example." + extensionName
                    filename = "Office Example"
                }
                #endif
            }
        }
        .tint(FolikTheme.cobalt)
    }

    private func load(_ url: URL) {
        let ext = url.pathExtension.lowercased()
        guard ["docx", "odt", "doc", "pages"].contains(ext) else { errorMessage = OfficeConversionError.unsupportedPackage.localizedDescription; return }
        busy = true; errorMessage = nil
        worker = Task {
            defer { busy = false }
            do {
                let data = try await Task.detached(priority: .userInitiated) {
                    if ext == "pages" { return try PagesPDFReader.readFile(url) }
                    return try PDFConverter.readFile(url, maximumBytes: OfficePackage.maximumFileBytes)
                }.cancellableValue
                try Task.checkCancellation()
                sourceData = data; extensionName = ext
                sourceName = url.lastPathComponent
                filename = url.deletingPathExtension().lastPathComponent
                preview = nil
            } catch is CancellationError { }
            catch { errorMessage = error.localizedDescription }
        }
    }
    private func preparePreview() {
        guard let sourceData, !busy else { return }
        busy = true; errorMessage = nil
        let ext = extensionName
        worker = Task {
            defer { busy = false }
            do {
                let result = try await OfficeDocumentEngine.preview(sourceData, extensionName: ext)
                try Task.checkCancellation()
                preview = result
            } catch is CancellationError { }
            catch { errorMessage = error.localizedDescription }
        }
    }
}

struct OfficePreviewView: View {
    let preview: OfficePreview
    let filename: String
    let complete: (LibraryDocument) -> Void
    @EnvironmentObject private var library: DocumentLibrary
    @Environment(\.dismiss) private var dismiss
    @State private var saving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(filename)
                            .font(.headline)
                            .accessibilityIdentifier("preview.filename")
                        Text(preview.resultSummary ?? "\(preview.pageCount) \(preview.pageCount == 1 ? "page" : "pages") · Review before saving")
                            .font(.subheadline.weight(.semibold))
                        Text(preview.recoveryNotice ?? "Image placement and complex layouts may differ. Compare important documents with the original.")
                            .font(.footnote).foregroundStyle(.secondary)
                        if !preview.warnings.isEmpty {
                            DisclosureGroup("\(preview.notesTitle) (\(preview.warnings.count))") {
                                ForEach(preview.warnings, id: \.self) { warning in
                                    Text(warning).font(.footnote).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 3)
                                }
                            }
                            .accessibilityIdentifier("office.notes")
                        }
                        if let errorMessage { ProcessingErrorView(message: errorMessage) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding()
                }
                .frame(maxHeight: 180)
                OfficePDFPreview(data: preview.data)
                    .accessibilityIdentifier("office.pdfPreview")
            }
            .navigationTitle(preview.previewTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Back") { dismiss() }.disabled(saving) }
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: save) {
                    HStack {
                        if saving { ProgressView() }
                        Text(saving ? "Saving…" : "Save Copy").font(.headline)
                    }
                    .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.borderedProminent)
                .disabled(saving)
                .padding().background(.regularMaterial)
                .accessibilityIdentifier("office.save")
            }
            .interactiveDismissDisabled(saving)
        }
    }
    private func save() {
        guard !saving else { return }
        saving = true; errorMessage = nil
        Task {
            defer { saving = false }
            do { complete(try await library.importConvertedPDF(.preparedPDF(preview.data), named: filename)) }
            catch { errorMessage = error.localizedDescription }
        }
    }
}

struct OfficePDFPreview: UIViewRepresentable {
    let data: Data
    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.document = PDFDocument(data: data)
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.backgroundColor = .secondarySystemBackground
        return view
    }
    func updateUIView(_ view: PDFView, context: Context) { }
}

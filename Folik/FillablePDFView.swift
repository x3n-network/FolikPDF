import PDFKit
import SwiftUI
import UniformTypeIdentifiers

nonisolated enum FillablePDFPreparation {
    static func prepare(_ data: Data) throws -> OfficePreview {
        let document = try PDFProcessing.document(data)
        return OfficePreview(
            data: data,
            warnings: [
                "The page artwork stays unchanged. Form fields are added separately in the reader.",
                "Review field placement and test the finished copy in the PDF apps your recipients use."
            ],
            pageCount: document.pageCount,
            recoveryNotice: "Fillable copy. Save it, then open Forms to add and arrange fields. Your source PDF remains unchanged."
        )
    }
}

struct FillablePDFView: View {
    var initialURL: URL? = nil
    let complete: (LibraryDocument) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var loadedInitialSource = false
    @State private var source: Data?
    @State private var sourceName: String?
    @State private var filename = "Fillable Document"
    @State private var showingFiles = false
    @State private var busy = false
    @State private var status = ""
    @State private var errorMessage: String?
    @State private var preview: OfficePreview?
    @State private var worker: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let sourceName {
                        Label(sourceName, systemImage: "doc")
                            .font(.subheadline.weight(.semibold))
                            .accessibilityIdentifier("fillable.source")
                    }
                    Button(source == nil ? "Choose PDF" : "Choose Another PDF") {
                        showingFiles = true
                    }
                    .frame(minHeight: 44)
                    .disabled(busy)

                    Text("Create a separate copy, then place real text fields, checkboxes, date fields, and signature fields over a scan or any other PDF.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if source != nil {
                    Section("New copy") {
                        TextField("Filename", text: $filename)
                            .disabled(busy)
                    }
                }

                if busy {
                    Section {
                        ProgressView(status)
                        Button("Cancel Processing") { worker?.cancel() }
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Make Fillable Copy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        worker?.cancel()
                        dismiss()
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button("Preview Fillable Copy", action: preparePreview)
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .padding()
                    .background(.regularMaterial)
                    .disabled(busy || source == nil || (try? PDFConverter.fileName(filename)) == nil)
                    .accessibilityIdentifier("fillable.preview")
            }
            .fileImporter(isPresented: $showingFiles, allowedContentTypes: [.pdf]) { result in
                switch result {
                case .success(let url): load(url)
                case .failure(let error): errorMessage = error.localizedDescription
                }
            }
            .sheet(item: $preview) {
                OfficePreviewView(preview: $0, filename: filename, complete: complete)
            }
            .onDisappear { worker?.cancel() }
            .onAppear {
                guard !loadedInitialSource else { return }
                loadedInitialSource = true
                if let initialURL { load(initialURL) }
            }
        }
    }

    private func load(_ url: URL) {
        busy = true
        status = "Reading PDF…"
        errorMessage = nil
        source = nil
        sourceName = nil
        preview = nil
        worker = Task {
            defer { busy = false }
            do {
                let data = try await Task.detached(priority: .userInitiated) {
                    try PDFConverter.readFile(url, maximumBytes: PDFProcessing.maximumBytes)
                }.value
                try Task.checkCancellation()
                _ = try await Task.detached(priority: .userInitiated) {
                    try PDFProcessing.document(data).pageCount
                }.value
                try Task.checkCancellation()
                source = data
                sourceName = url.lastPathComponent
                filename = url.deletingPathExtension().lastPathComponent + " Fillable"
            } catch is CancellationError {
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func preparePreview() {
        guard let source, !busy else { return }
        busy = true
        status = "Preparing fillable copy…"
        errorMessage = nil
        worker = Task {
            defer { busy = false }
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try FillablePDFPreparation.prepare(source)
                }.value
                try Task.checkCancellation()
                preview = result
            } catch is CancellationError {
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

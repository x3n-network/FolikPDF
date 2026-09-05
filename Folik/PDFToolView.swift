import SwiftUI
import UniformTypeIdentifiers

struct PDFToolView: View {
    let complete: (LibraryDocument) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showFiles = false
    @State private var source: Data?
    @State private var filename = "Searchable Document"
    @State private var status = ""
    @State private var error: String?
    @State private var busy = false
    @State private var task: Task<Void, Never>?
    @State private var preview: OfficePreview?
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button("Choose PDF") { showFiles = true }.disabled(busy)
                    Text("Add searchable text to scanned PDF pages on this device. Pages with existing text or annotations are preserved and skipped.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if source != nil {
                    Section("New copy") { TextField("Filename", text: $filename).disabled(busy) }
                }
                if busy { Section { ProgressView(status); Button("Cancel Processing") { task?.cancel() } } }
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }
            .navigationTitle("Make PDF Searchable")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { task?.cancel(); dismiss() } } }
            .safeAreaInset(edge: .bottom) {
                Button("Preview Searchable Copy", action: process)
                    .buttonStyle(.borderedProminent).frame(minHeight: 48).padding()
                    .disabled(busy || source == nil || (try? PDFConverter.fileName(filename)) == nil)
                    .accessibilityIdentifier("pdfTool.preview")
            }
            .fileImporter(isPresented: $showFiles, allowedContentTypes: [.pdf]) { result in
                switch result {
                case .success(let url): load(url)
                case .failure(let failure): error = failure.localizedDescription
                }
            }
            .sheet(item: $preview) { OfficePreviewView(preview: $0, filename: filename, complete: complete) }
            .onDisappear { task?.cancel() }
            .onAppear {
                #if DEBUG
                let args = ProcessInfo.processInfo.arguments
                if let index = args.firstIndex(of: "--ui-test-pdf-source"), index + 1 < args.count, source == nil {
                    source = Data(base64Encoded: args[index + 1]); filename = "Searchable Test"
                }
                #endif
            }
        }
    }
    private func load(_ url: URL) {
        busy = true; error = nil; status = "Reading PDF…"; source = nil
        task = Task {
            defer { busy = false }
            do {
                let data = try await Task.detached { try PDFConverter.readFile(url, maximumBytes: PDFProcessing.maximumBytes) }.value
                try Task.checkCancellation()
                source = data; filename = url.deletingPathExtension().lastPathComponent + " Searchable"
            } catch is CancellationError { } catch { self.error = error.localizedDescription }
        }
    }
    private func process() {
        guard let source, !busy else { return }
        busy = true; error = nil; status = "Recognizing text…"
        task = Task {
            defer { busy = false }
            let worker = Task.detached {
                try await PDFProcessing.searchable(source) { page, count in
                    await MainActor.run { status = "Recognizing page \(page) of \(count)…" }
                }
            }
            do {
                let result = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
                try Task.checkCancellation(); preview = result
            } catch is CancellationError { } catch { self.error = error.localizedDescription }
        }
    }
}

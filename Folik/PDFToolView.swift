import SwiftUI
import UniformTypeIdentifiers

struct PDFToolView: View {
    var compress = false
    var initialURL: URL? = nil
    let complete: (LibraryDocument) -> Void
    @State private var loadedInitialSource = false
    @State private var sourceName: String?
    @Environment(\.dismiss) private var dismiss
    @State private var preset: PDFCompressionPreset = .smaller
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
                    if let sourceName {
                        Label(sourceName, systemImage: "doc")
                            .font(.subheadline.weight(.semibold))
                            .accessibilityIdentifier("pdfTool.source")
                    }
                    Button(source == nil ? "Choose PDF" : "Choose Another PDF") { showFiles = true }
                        .frame(minHeight: 44)
                        .disabled(busy)
                    Text(compress ? "Reduce image-heavy PDFs while keeping the original. Review quality and compare file sizes before saving." : "Add searchable text to scanned PDF pages on this device. Pages with existing text or annotations are preserved and skipped.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if compress {
                    Section("Compression") {
                        Picker("Quality", selection: $preset) { ForEach(PDFCompressionPreset.allCases) { Text($0.rawValue).tag($0) } }.disabled(busy)
                        Text(preset.detail).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if source != nil {
                    Section("New copy") { TextField("Filename", text: $filename).disabled(busy) }
                }
                if busy { Section { ProgressView(status); Button("Cancel Processing") { task?.cancel() } } }
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }
            .navigationTitle(compress ? "Compress PDF" : "Make PDF Searchable")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { task?.cancel(); dismiss() } } }
            .safeAreaInset(edge: .bottom) {
                Button(compress ? "Preview Compressed Copy" : "Preview Searchable Copy", action: process)
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
                guard !loadedInitialSource else { return }
                loadedInitialSource = true
                if let initialURL {
                    load(initialURL)
                    return
                }
                #if DEBUG
                let args = ProcessInfo.processInfo.arguments
                if let index = args.firstIndex(of: "--ui-test-pdf-source"), index + 1 < args.count, source == nil {
                    source = Data(base64Encoded: args[index + 1]); filename = compress ? "Compressed Test" : "Searchable Test"
                }
                #endif
            }
        }
    }
    private func load(_ url: URL) {
        busy = true; error = nil; status = "Reading PDF…"; source = nil; sourceName = nil; preview = nil
        task = Task {
            defer { busy = false }
            do {
                let data = try await Task.detached { try PDFConverter.readFile(url, maximumBytes: PDFProcessing.maximumBytes) }.value
                try Task.checkCancellation()
                source = data; sourceName = url.lastPathComponent; filename = url.deletingPathExtension().lastPathComponent + (compress ? " Compressed" : " Searchable")
            } catch is CancellationError { } catch { self.error = error.localizedDescription }
        }
    }
    private func process() {
        guard let source, !busy else { return }
        busy = true; error = nil; status = compress ? "Compressing PDF…" : "Recognizing text…"
        let selectedPreset = preset
        let isCompression = compress
        task = Task {
            defer { busy = false }
            let worker = Task.detached {
                if isCompression { return try PDFCompression.compress(source, preset: selectedPreset) }
                return try await PDFProcessing.searchable(source) { page, count in
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

import SwiftUI
import UniformTypeIdentifiers

struct BatchConversionView: View {
    @EnvironmentObject private var library: DocumentLibrary
    @Environment(\.dismiss) private var dismiss
    @State private var sources: [BatchSource] = []
    @State private var outputs: [BatchPDFOutput] = []
    @State private var review: OfficePreview?
    @State private var combined = false
    @State private var filename = "Combined Documents"
    @State private var showFiles = false
    @State private var busy = false
    @State private var saving = false
    @State private var status = ""
    @State private var error: String?
    @State private var task: Task<Void, Never>?
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("Choose Files") { showFiles = true }.disabled(busy)
                    Text("Up to 20 files and 100 MB total. PDFs, supported Office files, TXT/RTF, and images. Reorder files before preparing the PDFs.").font(.footnote).foregroundStyle(.secondary)
                    Toggle("Combine into one PDF", isOn: $combined).disabled(busy).accessibilityIdentifier("batch.combine")
                    if combined { TextField("Combined filename", text: $filename).disabled(busy) }
                }
                Section("Source order") {
                    ForEach(Array(sources.enumerated()), id: \.element.id) { index, source in
                        HStack {
                            Text("\(index + 1). \(source.name).\(source.extensionName)").lineLimit(2)
                            Spacer()
                            Menu("Actions") {
                                if index > 0 { Button("Move Up") { sources.swapAt(index, index - 1); outputs = [] } }
                                if index + 1 < sources.count { Button("Move Down") { sources.swapAt(index, index + 1); outputs = [] } }
                                Button("Remove", role: .destructive) { sources.remove(at: index); outputs = [] }
                            }.disabled(busy).accessibilityLabel("Actions for \(source.name)")
                        }
                    }
                }
                if busy { Section { ProgressView(status); if !saving { Button("Cancel Processing") { task?.cancel() } } } }
                if let error { Section { Text(error).foregroundStyle(.red) } }
                if !outputs.isEmpty {
                    Section("Review prepared PDFs") {
                        ForEach(outputs) { output in
                            Button { review = output.preview } label: {
                                VStack(alignment: .leading) {
                                    Text(output.name)
                                    Text("\(output.preview.pageCount) pages · \(output.preview.warnings.count) conversion notes").font(.caption)
                                    if let notice = output.preview.recoveryNotice { Text(notice).font(.caption) }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Batch to PDF").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { task?.cancel(); dismiss() }.disabled(saving) } }
            .safeAreaInset(edge: .bottom) {
                Button(outputs.isEmpty ? "Prepare PDFs" : "Save All to Library") { outputs.isEmpty ? prepare() : save() }
                    .buttonStyle(.borderedProminent).frame(minHeight: 48).padding().disabled(busy || sources.isEmpty)
                    .accessibilityIdentifier("batch.action")
            }
            .fileImporter(isPresented: $showFiles, allowedContentTypes: BatchConversion.extensions.compactMap { UTType(filenameExtension: $0) }, allowsMultipleSelection: true) { result in
                switch result { case .success(let urls): load(urls); case .failure(let failure): error = failure.localizedDescription }
            }
            .sheet(item: $review) { preview in
                NavigationStack {
                    VStack {
                        if let notice = preview.recoveryNotice { Text(notice).font(.footnote).padding() }
                        DisclosureGroup("Conversion notes (\(preview.warnings.count))") {
                            ScrollView { ForEach(preview.warnings, id: \.self) { Text($0).font(.footnote).padding(.vertical, 2) } }.frame(maxHeight: 180)
                        }.padding()
                        OfficePDFPreview(data: preview.data)
                    }.navigationTitle("Batch Preview").navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { review = nil } } }
                }
            }
            .onChange(of: combined) { outputs = [] }
            .onChange(of: filename) { outputs = [] }
            .onDisappear { task?.cancel() }
            .interactiveDismissDisabled(saving)
            .onAppear {
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--ui-test-batch") && sources.isEmpty {
                    sources = [BatchSource(name: "First", extensionName: "txt", data: Data("FIRST BATCH MARKER".utf8)), BatchSource(name: "Second", extensionName: "txt", data: Data("SECOND BATCH MARKER".utf8))]
                }
                #endif
            }
        }
    }
    private func load(_ urls: [URL]) {
        guard urls.count + sources.count <= 20 else { error = "Choose at most 20 files."; return }
        busy = true; outputs = []; error = nil; status = "Reading files…"
        let existingBytes = sources.reduce(0) { $0 + $1.data.count }
        task = Task {
            defer { busy = false }
            do {
                let loaded = try await Task.detached {
                    var items: [BatchSource] = []; var total = existingBytes
                    for url in urls {
                        try Task.checkCancellation()
                        let ext = url.pathExtension.lowercased()
                        let data = try ext == "pages" ? PagesPDFReader.readFile(url) : PDFConverter.readFile(url, maximumBytes: PDFProcessing.maximumBytes)
                        total += data.count; guard total <= PDFProcessing.maximumBytes else { throw PDFProcessingError.tooLarge }
                        items.append(BatchSource(name: url.deletingPathExtension().lastPathComponent, extensionName: ext, data: data))
                    }
                    return items
                }.value
                try Task.checkCancellation(); sources += loaded
            } catch is CancellationError { } catch { self.error = error.localizedDescription }
        }
    }
    private func prepare() {
        busy = true; error = nil
        let inputs = sources; let combine = combined; let name = filename
        task = Task {
            defer { busy = false }
            let worker = Task.detached { try await BatchConversion.prepare(inputs, combined: combine, name: name) { index, count in
                await MainActor.run { status = "Converting file \(index) of \(count)…" }
            } }
            do {
                let prepared = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
                try Task.checkCancellation(); outputs = prepared
            } catch is CancellationError { } catch { self.error = error.localizedDescription }
        }
    }
    private func save() {
        saving = true; busy = true; error = nil; status = "Saving prepared PDFs…"
        task = Task {
            defer { saving = false; busy = false }
            do { _ = try await library.importBatchPDFs(outputs); dismiss() }
            catch { self.error = error.localizedDescription }
        }
    }
}

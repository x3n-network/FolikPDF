import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct PDFConversionView: View {
    enum Mode: String, Identifiable {
        case images, text
        var id: String { rawValue }
        var title: String { self == .images ? "Images to PDF" : "Text/RTF to PDF" }
    }

    private struct Page: Identifiable {
        let id = UUID()
        let data: Data
        let thumbnail: UIImage
    }

    let mode: Mode
    let complete: (LibraryDocument) -> Void
    @EnvironmentObject private var library: DocumentLibrary
    @Environment(\.dismiss) private var dismiss
    @State private var pages: [Page] = []
    @State private var photos: [PhotosPickerItem] = []
    @State private var documentData: Data?
    @State private var documentExtension = "txt"
    @State private var sourceName = ""
    @State private var name = "Images"
    @State private var showFiles = false
    @State private var loading = false
    @State private var converting = false
    @State private var errorMessage: String?
    @State private var conversionTask: Task<Void, Never>?
    @State private var loadTask: Task<Void, Never>?

    private var busy: Bool { loading || converting }
    private var canCreate: Bool {
        !busy && (mode == .images ? !pages.isEmpty : documentData != nil) && (try? PDFConverter.fileName(name)) != nil
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if mode == .images {
                        PhotosPicker(selection: $photos, maxSelectionCount: max(1, PDFConverter.maximumImages - pages.count), selectionBehavior: .ordered, matching: .images) {
                            Label("Choose from Photos", systemImage: "photo.on.rectangle")
                                .frame(minHeight: 44)
                        }
                        .disabled(busy || pages.count >= PDFConverter.maximumImages)
                    }
                    Button { showFiles = true } label: {
                        Label(mode == .images ? "Choose Images from Files" : "Choose TXT or RTF File", systemImage: "folder")
                            .frame(minHeight: 44)
                    }
                    .accessibilityIdentifier("converter.chooseFiles")
                    .disabled(busy || (mode == .images && pages.count >= PDFConverter.maximumImages))
                } footer: {
                    Text(mode == .images
                         ? "JPEG, PNG, and HEIC. Up to 30 images, 20 MB each and 100 MB total. Each image becomes one page; detected text is searchable."
                         : "TXT and RTF up to 5 MB. Text flows onto Letter-size pages with margins. Basic RTF styling is preserved; complex layouts and attachments aren’t supported.")
                }

                if mode == .images && !pages.isEmpty {
                    Section("Pages · \(pages.count)") {
                        ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                            HStack(spacing: 12) {
                                Image(uiImage: page.thumbnail)
                                    .resizable().scaledToFit()
                                    .frame(width: 48, height: 64)
                                    .accessibilityHidden(true)
                                Text("Page \(index + 1)")
                                Spacer()
                                Menu {
                                    Button("Move Up", systemImage: "arrow.up") { pages.swapAt(index, index - 1) }
                                        .disabled(index == 0)
                                    Button("Move Down", systemImage: "arrow.down") { pages.swapAt(index, index + 1) }
                                        .disabled(index == pages.count - 1)
                                    Button("Remove", systemImage: "trash", role: .destructive) { pages.remove(at: index) }
                                } label: {
                                    Image(systemName: "ellipsis").frame(width: 44, height: 44)
                                }
                                .accessibilityLabel("Actions for page \(index + 1)")
                            }
                        }
                        .onMove { pages.move(fromOffsets: $0, toOffset: $1) }
                        .onDelete { pages.remove(atOffsets: $0) }
                    }
                    .disabled(busy)
                } else if !sourceName.isEmpty {
                    Section("Selected document") {
                        Label(sourceName, systemImage: "doc.text")
                    }
                }

                Section("PDF filename") {
                    TextField("Filename", text: $name)
                        .accessibilityIdentifier("converter.filename")
                        .autocorrectionDisabled()
                        .disabled(busy)
                }
                if let errorMessage {
                    Section {
                        ProcessingErrorView(message: errorMessage)
                            .accessibilityIdentifier("converter.error")
                    }
                }
            }
            .navigationTitle(mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { loadTask?.cancel(); dismiss() }
                        .disabled(converting)
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 10) {
                    if busy {
                        ProcessingStatusView(status: loading ? "Loading selection…" : "Creating PDF…") {
                            loadTask?.cancel()
                            conversionTask?.cancel()
                        }
                    }
                    Button(action: createPDF) {
                        Text("Create PDF").font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canCreate)
                    .accessibilityIdentifier("converter.create")
                }
                .padding()
                .background(.regularMaterial)
            }
            .fileImporter(isPresented: $showFiles,
                          allowedContentTypes: mode == .images ? [.jpeg, .png, .heic, .heif] : [.plainText, .rtf],
                          allowsMultipleSelection: mode == .images) { result in
                switch result {
                case .success(let urls): loadFiles(urls)
                case .failure(let error): errorMessage = error.localizedDescription
                }
            }
            .onChange(of: photos) { _, selection in
                guard !selection.isEmpty else { return }
                loading = true
                errorMessage = nil
                loadTask = Task {
                    defer { loading = false; photos = [] }
                    do {
                        var additions: [Page] = []
                        var bytes = pages.reduce(0) { $0 + $1.data.count }
                        for item in selection {
                            try Task.checkCancellation()
                            guard let data = try await item.loadTransferable(type: Data.self) else { throw PDFConversionError.invalidImage }
                            bytes += data.count
                            guard bytes <= PDFConverter.maximumTotalImageBytes else { throw PDFConversionError.tooLarge }
                            additions.append(try await makePage(data))
                        }
                        try Task.checkCancellation()
                        pages.append(contentsOf: additions)
                    } catch is CancellationError { }
                    catch { errorMessage = error.localizedDescription }
                }
            }
            .onAppear {
                if mode == .text { name = "Document" }
                #if DEBUG
                prepareTestSelection()
                #endif
            }
            .onDisappear { loadTask?.cancel(); conversionTask?.cancel() }
            .interactiveDismissDisabled(busy)
        }
        .tint(FolikTheme.cobalt)
    }

    private func makePage(_ data: Data) async throws -> Page {
        let thumbnail = try await Task.detached(priority: .userInitiated) {
            try PDFConverter.image(data, maximumPixelSize: 160)
        }.cancellableValue
        return Page(data: data, thumbnail: UIImage(cgImage: thumbnail))
    }

    private func loadFiles(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        loading = true
        errorMessage = nil
        loadTask = Task {
            defer { loading = false }
            do {
                if mode == .images {
                    guard pages.count + urls.count <= PDFConverter.maximumImages else { throw PDFConversionError.tooLarge }
                    var additions: [Page] = []
                    var bytes = pages.reduce(0) { $0 + $1.data.count }
                    for url in urls {
                        try Task.checkCancellation()
                        let data = try await Task.detached(priority: .userInitiated) {
                            try PDFConverter.readFile(url, maximumBytes: PDFConverter.maximumImageBytes)
                        }.cancellableValue
                        bytes += data.count
                        guard bytes <= PDFConverter.maximumTotalImageBytes else { throw PDFConversionError.tooLarge }
                        additions.append(try await makePage(data))
                    }
                    try Task.checkCancellation()
                    pages.append(contentsOf: additions)
                } else if let url = urls.first {
                    guard ["txt", "rtf"].contains(url.pathExtension.lowercased()) else { throw PDFConversionError.unsupportedDocument }
                    let data = try await Task.detached(priority: .userInitiated) {
                        try PDFConverter.readFile(url, maximumBytes: PDFConverter.maximumTextBytes)
                    }.cancellableValue
                    try Task.checkCancellation()
                    documentData = data
                    documentExtension = url.pathExtension
                    sourceName = url.lastPathComponent
                    name = url.deletingPathExtension().lastPathComponent
                }
            } catch is CancellationError { }
            catch { errorMessage = error.localizedDescription }
        }
    }

    #if DEBUG
    private func prepareTestSelection() {
        guard ProcessInfo.processInfo.arguments.contains("--ui-test-conversion-selection"), pages.isEmpty, documentData == nil else { return }
        if mode == .text {
            documentData = Data((0..<120).map { "Conversion line \($0)" }.joined(separator: "\n").utf8)
            documentExtension = "txt"
            sourceName = "Conversion.txt"
            name = "Converted Text"
        } else {
            for title in ["First conversion page", "Second conversion page"] {
                let image = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 900)).image { context in
                    UIColor.white.setFill()
                    context.fill(CGRect(x: 0, y: 0, width: 600, height: 900))
                    (title as NSString).draw(at: CGPoint(x: 40, y: 80), withAttributes: [
                        .font: UIFont.systemFont(ofSize: 32), .foregroundColor: UIColor.black
                    ])
                }
                if let data = image.jpegData(compressionQuality: 0.9) {
                    pages.append(Page(data: data, thumbnail: image))
                }
            }
            name = "Converted Images"
        }
    }
    #endif

    private func createPDF() {
        guard canCreate else { return }
        let input: PDFConversionInput
        if mode == .images { input = .images(pages.map(\.data)) }
        else if let documentData { input = .text(documentData, extensionName: documentExtension) }
        else { return }
        converting = true
        errorMessage = nil
        conversionTask = Task {
            defer { converting = false }
            do {
                let document = try await library.importConvertedPDF(input, named: name)
                complete(document)
            } catch is CancellationError { } catch { errorMessage = error.localizedDescription }
        }
    }
}

import PDFKit
import SwiftUI
import UniformTypeIdentifiers

struct RedactionView: View {
    var initialURL: URL? = nil
    let complete: (LibraryDocument) -> Void
    @State private var loadedInitialSource = false
    @State private var sourceName: String?
    @Environment(\.dismiss) private var dismiss
    @State private var source: Data?
    @State private var page = 0
    @State private var pageCount = 0
    @State private var image: CGImage?
    @State private var areas: [RedactionArea] = []
    @State private var filename = "Redacted Document"
    @State private var showFiles = false
    @State private var busy = false
    @State private var status = ""
    @State private var error: String?
    @State private var preview: OfficePreview?
    @State private var task: Task<Void, Never>?
    @State private var searchText = ""
    @State private var suggestions: [RedactionSuggestion] = []
    @State private var showSuggestions = false
    @State private var left = 5.0
    @State private var top = 5.0
    @State private var width = 60.0
    @State private var height = 15.0
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let sourceName {
                        Label(sourceName, systemImage: "doc")
                            .font(.subheadline.weight(.semibold))
                            .accessibilityIdentifier("pdfTool.source")
                    }
                    Button(source == nil ? "Choose PDF" : "Choose Another PDF") { showFiles = true }
                        .frame(minHeight: 44)
                        .disabled(busy)
                    Text("Mark sensitive areas by dragging on the page or entering percentages. Create and review an image-only copy; text selection, links, editable forms, and document metadata will be removed. The original is kept.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if let image {
                        HStack {
                            Button("Previous") { page -= 1; renderPage() }.disabled(busy || page == 0)
                            Spacer(); Text("Page \(page + 1) of \(pageCount)"); Spacer()
                            Button("Next") { page += 1; renderPage() }.disabled(busy || page + 1 >= pageCount)
                        }
                        RedactionCanvas(image: image, areas: areas.filter { $0.page == page }) { rect in
                            areas.append(RedactionArea(page: page, rect: rect)); preview = nil
                        }.frame(height: 400).disabled(busy).accessibilityLabel("Page preview. Use the percentage controls below to mark an area without dragging.")
                        GroupBox("Find text to redact") {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Folik scans searchable text on this device. Review every suggestion before adding it; pattern matches can be wrong.")
                                    .font(.footnote).foregroundStyle(.secondary)
                                HStack {
                                    TextField("Text to find", text: $searchText)
                                        .textFieldStyle(.roundedBorder)
                                        .textInputAutocapitalization(.never)
                                        .accessibilityIdentifier("redaction.searchText")
                                    Button("Find Text") { findText() }
                                        .disabled(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                        .accessibilityIdentifier("redaction.findText")
                                }
                                Menu("Find Sensitive Information") {
                                    Button("Email Addresses") { findSensitive([.email]) }
                                    Button("Phone Numbers") { findSensitive([.phone]) }
                                    Button("Social Security Numbers") { findSensitive([.socialSecurityNumber]) }
                                    Button("All Common Patterns") { findSensitive(RedactionSuggestionKind.sensitiveInformation) }
                                }
                                .accessibilityIdentifier("redaction.findSensitive")
                            }
                            .disabled(busy)
                        }
                        GroupBox("Add area by percentage") {
                            VStack {
                                HStack { Text("Left %"); TextField("Left", value: $left, format: .number); Text("Top %"); TextField("Top", value: $top, format: .number) }
                                HStack { Text("Width %"); TextField("Width", value: $width, format: .number); Text("Height %"); TextField("Height", value: $height, format: .number) }
                                Button("Add Area") { addArea() }.accessibilityIdentifier("redaction.addArea")
                            }.textFieldStyle(.roundedBorder).keyboardType(.decimalPad).disabled(busy)
                        }
                        ForEach(Array(areas.enumerated()), id: \.element.id) { index, area in
                            HStack { Text("Area \(index + 1) · Page \(area.page + 1)"); Spacer(); Button("Remove") { areas.removeAll { $0.id == area.id } }.disabled(busy) }
                        }
                        TextField("New copy filename", text: $filename).textFieldStyle(.roundedBorder).disabled(busy)
                    }
                    if busy { ProgressView(status); Button("Cancel Processing") { task?.cancel() } }
                    if let error { Text(error).foregroundStyle(.red) }
                }.padding()
            }
            .navigationTitle("Redact PDF").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { task?.cancel(); dismiss() } } }
            .safeAreaInset(edge: .bottom) {
                Button("Create Redacted Preview", action: prepare).buttonStyle(.borderedProminent)
                    .frame(minHeight: 48).padding().disabled(busy || areas.isEmpty || (try? PDFConverter.fileName(filename)) == nil)
                    .accessibilityIdentifier("redaction.preview")
            }
            .fileImporter(isPresented: $showFiles, allowedContentTypes: [.pdf]) { result in
                switch result { case .success(let url): load(url); case .failure(let failure): error = failure.localizedDescription }
            }
            .sheet(item: $preview) { OfficePreviewView(preview: $0, filename: filename, complete: complete) }
            .sheet(isPresented: $showSuggestions) {
                SmartRedactionReviewView(suggestions: suggestions) { selected in
                    addSuggestions(selected)
                }
            }
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
                if let index = args.firstIndex(of: "--ui-test-pdf-source"), index + 1 < args.count, source == nil,
                   let data = Data(base64Encoded: args[index + 1]) { source = data; filename = "Redacted Test"; renderPage() }
                #endif
            }
        }
    }
    private func addArea() {
        let candidate = RedactionArea(page: page, rect: CGRect(x: left / 100, y: top / 100, width: width / 100, height: height / 100))
        do { try PDFRedaction.validate(areas + [candidate], pages: pageCount); areas.append(candidate); error = nil }
        catch { self.error = error.localizedDescription }
    }
    private func findText() {
        scan { try SmartRedaction.findText(in: $0, query: searchText) }
    }
    private func findSensitive(_ kinds: Set<RedactionSuggestionKind>) {
        scan { try SmartRedaction.findSensitiveInformation(in: $0, kinds: kinds) }
    }
    private func scan(_ operation: @escaping @Sendable (Data) throws -> [RedactionSuggestion]) {
        guard let source else { return }
        busy = true; error = nil; status = "Finding text…"
        task = Task {
            defer { busy = false }
            let worker = Task.detached { try operation(source) }
            do {
                let result = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
                try Task.checkCancellation(); suggestions = result; showSuggestions = true
            } catch is CancellationError { } catch { self.error = error.localizedDescription }
        }
    }
    private func addSuggestions(_ selected: [RedactionSuggestion]) {
        let newAreas = selected.map(\.area).filter { candidate in
            !areas.contains { existing in
                existing.page == candidate.page &&
                    abs(existing.rect.minX - candidate.rect.minX) < 0.0001 &&
                    abs(existing.rect.minY - candidate.rect.minY) < 0.0001 &&
                    abs(existing.rect.width - candidate.rect.width) < 0.0001 &&
                    abs(existing.rect.height - candidate.rect.height) < 0.0001
            }
        }
        let candidates = areas + newAreas
        do {
            try PDFRedaction.validate(candidates, pages: pageCount)
            areas = candidates; preview = nil; error = nil
        } catch { self.error = error.localizedDescription }
    }
    private func load(_ url: URL) {
        busy = true; error = nil; status = "Reading PDF…"
        source = nil; sourceName = nil; image = nil; areas = []; preview = nil
        suggestions = []; page = 0; pageCount = 0
        task = Task {
            do {
                let data = try await Task.detached { try PDFConverter.readFile(url, maximumBytes: PDFProcessing.maximumBytes) }.value
                try Task.checkCancellation(); source = data; sourceName = url.lastPathComponent; areas = []; page = 0; filename = url.deletingPathExtension().lastPathComponent + " Redacted"
                busy = false; renderPage()
            } catch { busy = false; if !(error is CancellationError) { self.error = error.localizedDescription } }
        }
    }
    private func renderPage() {
        guard let source else { return }
        busy = true; error = nil; status = "Rendering page…"; image = nil
        let index = page
        task = Task {
            defer { busy = false }
            do {
                let result = try await Task.detached {
                    let pdf = try PDFProcessing.document(source)
                    guard let page = pdf.page(at: index) else { throw PDFProcessingError.invalid }
                    return (try PDFRedaction.bitmap(page), pdf.pageCount)
                }.value
                try Task.checkCancellation(); image = result.0; pageCount = result.1
            } catch is CancellationError { } catch { self.error = error.localizedDescription }
        }
    }
    private func prepare() {
        guard let source else { return }
        busy = true; error = nil; let marks = areas
        task = Task {
            defer { busy = false }
            let worker = Task.detached { try await PDFRedaction.redact(source, areas: marks) { index, count in
                await MainActor.run { status = "Redacting page \(index) of \(count)…" }
            } }
            do {
                let result = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
                try Task.checkCancellation(); preview = result
            } catch is CancellationError { } catch { self.error = error.localizedDescription }
        }
    }
}

private struct SmartRedactionReviewView: View {
    let suggestions: [RedactionSuggestion]
    let add: ([RedactionSuggestion]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<UUID>

    init(suggestions: [RedactionSuggestion], add: @escaping ([RedactionSuggestion]) -> Void) {
        self.suggestions = suggestions
        self.add = add
        _selected = State(initialValue: Set(suggestions.map(\.id)))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Check each match before adding it. Nothing is changed until you create the redacted copy.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Suggestions") {
                    ForEach(suggestions) { suggestion in
                        Button {
                            if selected.contains(suggestion.id) { selected.remove(suggestion.id) }
                            else { selected.insert(suggestion.id) }
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: selected.contains(suggestion.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selected.contains(suggestion.id) ? Color.accentColor : .secondary)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(suggestion.matchedText).foregroundStyle(.primary).lineLimit(2)
                                    Text("\(suggestion.kind.title) · Page \(suggestion.area.page + 1)")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .accessibilityLabel("\(suggestion.matchedText), \(suggestion.kind.title), page \(suggestion.area.page + 1)")
                        .accessibilityValue(selected.contains(suggestion.id) ? "Selected" : "Not selected")
                    }
                }
            }
            .navigationTitle("Review Suggestions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Menu("Selection") {
                        Button("Select All") { selected = Set(suggestions.map(\.id)) }
                        Button("Clear All") { selected.removeAll() }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button("Add \(selected.count) Suggested Area\(selected.count == 1 ? "" : "s")") {
                    add(suggestions.filter { selected.contains($0.id) }); dismiss()
                }
                .buttonStyle(.borderedProminent).frame(minHeight: 48).padding()
                .disabled(selected.isEmpty)
                .accessibilityIdentifier("redaction.addSuggestions")
            }
        }
    }
}

private struct RedactionCanvas: View {
    let image: CGImage
    let areas: [RedactionArea]
    let add: (CGRect) -> Void
    @State private var drag: CGRect?
    var body: some View {
        GeometryReader { geometry in
            let scale = min(geometry.size.width / CGFloat(image.width), geometry.size.height / CGFloat(image.height))
            let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
            let origin = CGPoint(x: (geometry.size.width - size.width) / 2, y: (geometry.size.height - size.height) / 2)
            ZStack(alignment: .topLeading) {
                Image(decorative: image, scale: 1).resizable().frame(width: size.width, height: size.height).offset(x: origin.x, y: origin.y)
                ForEach(areas) { area in
                    Rectangle().fill(.black.opacity(0.8)).frame(width: area.rect.width * size.width, height: area.rect.height * size.height)
                        .offset(x: origin.x + area.rect.minX * size.width, y: origin.y + area.rect.minY * size.height)
                }
                if let drag {
                    Rectangle().stroke(.red, lineWidth: 2).frame(width: drag.width * size.width, height: drag.height * size.height)
                        .offset(x: origin.x + drag.minX * size.width, y: origin.y + drag.minY * size.height)
                }
            }.frame(width: geometry.size.width, height: geometry.size.height).contentShape(Rectangle())
                .highPriorityGesture(DragGesture(minimumDistance: 5).onChanged { value in
                    func normalized(_ point: CGPoint) -> CGPoint { CGPoint(x: min(1, max(0, (point.x - origin.x) / size.width)), y: min(1, max(0, (point.y - origin.y) / size.height))) }
                    let a = normalized(value.startLocation); let b = normalized(value.location)
                    drag = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
                }.onEnded { _ in
                    if let drag, drag.width > 0.005, drag.height > 0.005 { add(drag) }; drag = nil
                })
        }
    }
}

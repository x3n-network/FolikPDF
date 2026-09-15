import SwiftUI
import UniformTypeIdentifiers

struct ComparePDFView: View {
    var initialURL: URL? = nil

    private enum Slot { case original, revised }

    @Environment(\.dismiss) private var dismiss
    @State private var loadedInitialSource = false
    @State private var originalData: Data?
    @State private var revisedData: Data?
    @State private var originalName: String?
    @State private var revisedName: String?
    @State private var choosingOriginal = false
    @State private var choosingRevised = false
    @State private var busy = false
    @State private var status = ""
    @State private var error: String?
    @State private var task: Task<Void, Never>?
    @State private var report: PDFComparisonReport?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Compare selectable text locally. Folik aligns unchanged pages even when pages were inserted or removed, then reports added, removed, and changed pages.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Label("Purely visual changes are not checked", systemImage: "info.circle")
                        .font(.footnote.weight(.semibold))
                }
                sourceSection("Original", name: originalName) { choosingOriginal = true }
                sourceSection("Revised", name: revisedName) { choosingRevised = true }
                if busy {
                    Section {
                        ProgressView(status)
                        Button("Cancel Comparison") { task?.cancel() }
                    }
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
                if originalData != nil || revisedData != nil {
                    Section {
                        Text("Protected PDFs are not accepted. Scanned pages need searchable text from OCR before their wording can be compared.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Compare PDFs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { task?.cancel(); dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button("Compare PDFs", action: compare)
                    .buttonStyle(.borderedProminent)
                    .frame(minHeight: 48)
                    .padding()
                    .background(.regularMaterial)
                    .disabled(busy || originalData == nil || revisedData == nil)
                    .accessibilityIdentifier("compare.run")
            }
            .fileImporter(isPresented: $choosingOriginal, allowedContentTypes: [.pdf]) { handle($0, slot: .original) }
            .fileImporter(isPresented: $choosingRevised, allowedContentTypes: [.pdf]) { handle($0, slot: .revised) }
            .sheet(item: $report) {
                PDFComparisonReportView(
                    report: $0,
                    originalName: originalName ?? "Original",
                    revisedName: revisedName ?? "Revised",
                    originalData: originalData,
                    revisedData: revisedData
                )
            }
            .interactiveDismissDisabled(busy)
            .onDisappear { task?.cancel() }
            .onAppear(perform: loadInitialSource)
        }
    }

    private func sourceSection(_ title: String, name: String?, choose: @escaping () -> Void) -> some View {
        Section(title) {
            if let name {
                Label(name, systemImage: "doc.text")
                    .font(.subheadline.weight(.semibold))
                    .accessibilityIdentifier(title == "Original" ? "compare.original" : "compare.revised")
            }
            Button(name == nil ? "Choose \(title) PDF" : "Choose Another PDF", action: choose)
                .frame(minHeight: 44)
                .disabled(busy)
        }
    }

    private func handle(_ result: Result<URL, Error>, slot: Slot) {
        switch result {
        case .success(let url): load(url, slot: slot)
        case .failure(let failure): error = failure.localizedDescription
        }
    }

    private func load(_ url: URL, slot: Slot) {
        busy = true
        error = nil
        status = "Reading \(slot == .original ? "original" : "revised") PDF…"
        report = nil
        task = Task {
            defer { busy = false }
            do {
                let data = try await Task.detached { try PDFConverter.readFile(url, maximumBytes: PDFProcessing.maximumBytes) }.value
                _ = try await Task.detached { try PDFProcessing.document(data) }.value
                try Task.checkCancellation()
                if slot == .original { originalData = data; originalName = url.lastPathComponent }
                else { revisedData = data; revisedName = url.lastPathComponent }
            } catch is CancellationError { }
            catch { self.error = error.localizedDescription }
        }
    }

    private func compare() {
        guard let originalData, let revisedData, !busy else { return }
        busy = true
        error = nil
        status = "Aligning and comparing pages…"
        task = Task {
            defer { busy = false }
            do {
                let result = try await Task.detached { try PDFComparison.compare(originalData, revisedData) }.value
                try Task.checkCancellation()
                report = result
            } catch is CancellationError { }
            catch { self.error = error.localizedDescription }
        }
    }

    private func loadInitialSource() {
        guard !loadedInitialSource else { return }
        loadedInitialSource = true
        if let initialURL { load(initialURL, slot: .original) }
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let oldIndex = arguments.firstIndex(of: "--ui-test-compare-original"), oldIndex + 1 < arguments.count,
           let newIndex = arguments.firstIndex(of: "--ui-test-compare-revised"), newIndex + 1 < arguments.count,
           let old = Data(base64Encoded: arguments[oldIndex + 1]),
           let new = Data(base64Encoded: arguments[newIndex + 1]) {
            originalData = old; originalName = "Original.pdf"
            revisedData = new; revisedName = "Revised.pdf"
            busy = false
        }
        #endif
    }
}

private struct PDFComparisonReportView: View {
    let report: PDFComparisonReport
    let originalName: String
    let revisedName: String
    let originalData: Data?
    let revisedData: Data?
    @Environment(\.dismiss) private var dismiss
    @State private var preview: ComparisonPreviewRequest?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if report.isIdentical {
                        Label("No selectable-text changes found", systemImage: "checkmark.circle.fill")
                            .font(.headline)
                            .foregroundStyle(.green)
                    } else {
                        LabeledContent("Changed pages", value: report.modifiedCount.formatted())
                        LabeledContent("Added pages", value: report.addedCount.formatted())
                        LabeledContent("Removed pages", value: report.removedCount.formatted())
                        LabeledContent("Unchanged aligned pages", value: report.unchangedPageCount.formatted())
                    }
                    Text("Text-based result only. Review both PDFs for image, layout, color, annotation, and other visual changes.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if !report.changes.isEmpty {
                    Section("Page changes") {
                        ForEach(report.changes) { change in
                            DisclosureGroup {
                                if let original = change.originalExcerpt {
                                    comparisonExcerpt("Original", text: original)
                                }
                                if let revised = change.revisedExcerpt {
                                    comparisonExcerpt("Revised", text: revised)
                                }
                                Button {
                                    preview = ComparisonPreviewRequest(
                                        originalData: originalData,
                                        revisedData: revisedData,
                                        originalPageIndex: change.originalPage.map { $0 - 1 },
                                        revisedPageIndex: change.revisedPage.map { $0 - 1 },
                                        title: change.title
                                    )
                                } label: {
                                    Label("Preview changed pages", systemImage: "rectangle.split.2x1")
                                        .frame(minHeight: 44)
                                }
                                .disabled(originalData == nil && revisedData == nil)
                            } label: {
                                Label(change.title, systemImage: change.kind.icon)
                                    .font(.subheadline.weight(.semibold))
                            }
                        }
                    }
                }
                Section("Compared") {
                    LabeledContent("Original", value: originalName)
                    LabeledContent("Revised", value: revisedName)
                }
            }
            .navigationTitle("Comparison Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(item: $preview) { request in
                ComparisonPagePreview(
                    request: request,
                    originalName: originalName,
                    revisedName: revisedName
                )
            }
        }
    }

    private func comparisonExcerpt(_ label: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(text).font(.footnote)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 3)
    }
}

private struct ComparisonPreviewRequest: Identifiable {
    let id = UUID()
    let originalData: Data?
    let revisedData: Data?
    let originalPageIndex: Int?
    let revisedPageIndex: Int?
    let title: String
}

private struct ComparisonPagePreview: View {
    enum Side: String, CaseIterable, Identifiable {
        case original = "Original"
        case revised = "Revised"
        var id: Self { self }
    }

    let request: ComparisonPreviewRequest
    let originalName: String
    let revisedName: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var side: Side

    init(request: ComparisonPreviewRequest, originalName: String, revisedName: String) {
        self.request = request
        self.originalName = originalName
        self.revisedName = revisedName
        _side = State(initialValue: request.originalPageIndex == nil ? .revised : .original)
    }

    var body: some View {
        NavigationStack {
            Group {
                if horizontalSizeClass == .regular,
                   request.originalData != nil,
                   request.revisedData != nil {
                    HStack(spacing: 0) {
                        pagePreview(.original)
                        Divider()
                        pagePreview(.revised)
                    }
                } else {
                    VStack(spacing: 0) {
                        if request.originalData != nil && request.revisedData != nil {
                            Picker("Document", selection: $side) {
                                ForEach(Side.allCases) { Text($0.rawValue).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            .padding()
                        }
                        pagePreview(availableSide)
                    }
                }
            }
            .background(FolikTheme.canvas)
            .navigationTitle(request.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private var availableSide: Side {
        if side == .original, request.originalData != nil { return .original }
        if side == .revised, request.revisedData != nil { return .revised }
        return request.originalData == nil ? .revised : .original
    }

    @ViewBuilder
    private func pagePreview(_ side: Side) -> some View {
        let data = side == .original ? request.originalData : request.revisedData
        let pageIndex = side == .original ? request.originalPageIndex : request.revisedPageIndex
        let name = side == .original ? originalName : revisedName
        VStack(spacing: 8) {
            Text("\(side.rawValue): \(name)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(FolikTheme.mutedInk)
                .lineLimit(2)
                .padding(.horizontal)
            if let data, let pageIndex {
                ReadOnlyPDFPreview(data: data, pageIndex: pageIndex)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(side.rawValue) preview, page \(pageIndex + 1)")
                    .accessibilityIdentifier("compare.preview.\(side.rawValue.lowercased()).\(pageIndex + 1)")
            } else {
                ContentUnavailableView(
                    side == .original ? "No Original Page" : "No Revised Page",
                    systemImage: side == .original ? "minus.circle" : "plus.circle",
                    description: Text("This page exists only in the other document.")
                )
            }
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

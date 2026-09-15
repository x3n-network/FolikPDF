import PDFKit
import SwiftUI

struct ReaderInspector: View {
    let panel: ReaderPanel
    @ObservedObject var session: DocumentSession
    let close: () -> Void
    let organizePages: () -> Void
    @State private var showingContents = false

    var body: some View {
        Group {
            switch panel {
            case .pages:
                VStack(spacing: 0) {
                    Picker("Browse document", selection: $showingContents) {
                        Text("Pages").tag(false)
                        Text("Contents").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .padding()
                    .accessibilityIdentifier("reader.pages.contents")
                    if showingContents {
                        OutlineNavigator(session: session, close: close)
                    } else {
                        PageNavigator(session: session, close: close, organizePages: organizePages)
                    }
                }
            case .outline:
                OutlineNavigator(session: session, close: close)
            case .search:
                SearchNavigator(session: session, close: close)
            case .annotations:
                AnnotationNavigator(session: session, close: close)
            case .forms:
                FormNavigator(session: session, close: close)
            }
        }
        .background(FolikTheme.surface)
        .navigationTitle(panel.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done", action: close)
            }
        }
    }
}

private struct SignDocumentButton: View {
    @ObservedObject var session: DocumentSession
    let close: () -> Void
    let capture: () -> Void

    var body: some View {
        Button {
            if let asset = session.savedSignatureAsset(for: .signature) {
                session.beginSignaturePlacement(asset)
                close()
            } else {
                capture()
            }
        } label: {
            Label("Sign", systemImage: "signature")
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("reader.sign")
        .accessibilityHint("Place your saved signature or create one on this device")
    }
}

private struct AnnotationNavigator: View {
    @ObservedObject var session: DocumentSession
    let close: () -> Void
    @State private var textPlacementKind: AnnotationPlacementKind?
    @State private var signatureCaptureKind: SignatureKind?
    @State private var signaturePlaced = false
    @State private var draftText = ""

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(session.annotations.count) annotation\(session.annotations.count == 1 ? "" : "s")")
                            .font(.headline)
                        Text("Draw, stamp, or mark selected text.")
                            .font(.subheadline)
                            .foregroundStyle(FolikTheme.mutedInk)
                    }
                    Spacer(minLength: 8)
                    HStack(spacing: 0) {
                        Button(action: session.undoAnnotationAction) {
                            Image(systemName: "arrow.uturn.backward")
                                .frame(width: 44, height: 44)
                        }
                        .disabled(!session.canUndoAnnotation)
                        .accessibilityLabel("Undo annotation change")
                        Button(action: session.redoAnnotationAction) {
                            Image(systemName: "arrow.uturn.forward")
                                .frame(width: 44, height: 44)
                        }
                        .disabled(!session.canRedoAnnotation)
                        .accessibilityLabel("Redo annotation change")
                    }
                }

                SignDocumentButton(session: session, close: close, capture: { signatureCaptureKind = .signature })

                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    spacing: 8
                ) {
                    Button {
                        session.setDrawingEnabled(true)
                        close()
                    } label: {
                        Label("Draw", systemImage: "pencil.tip")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(FolikTheme.cobalt)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("reader.annotation.draw")

                    Menu {
                        ForEach(AnnotationPlacementKind.allCases.filter {
                            !$0.requiresSignatureAsset && !$0.requiresStamp
                        }) { kind in
                            Button {
                                if kind.requiresText {
                                    draftText = ""
                                    textPlacementKind = kind
                                } else {
                                    session.beginAnnotationPlacement(kind)
                                    close()
                                }
                            } label: {
                                Label(kind.title, systemImage: kind.icon)
                            }
                        }
                        Menu {
                            ForEach(AnnotationStamp.allCases) { stamp in
                                Button {
                                    session.beginStampPlacement(stamp)
                                    close()
                                } label: {
                                    Label(stamp.title, systemImage: stamp.icon)
                                }
                            }
                        } label: {
                            Label("Stamp", systemImage: "seal")
                        }
                        Divider()
                        ForEach(SignatureKind.allCases) { kind in
                            Menu {
                                if let asset = session.savedSignatureAsset(for: kind) {
                                    Button {
                                        session.beginSignaturePlacement(asset)
                                        close()
                                    } label: {
                                        Label("Place saved \(kind.title.lowercased())", systemImage: kind.icon)
                                    }
                                    Button("Replace \(kind.title.lowercased())") {
                                        signatureCaptureKind = kind
                                    }
                                    Button("Forget \(kind.title.lowercased())", role: .destructive) {
                                        session.deleteSavedSignature(for: kind)
                                    }
                                } else {
                                    Button("Create \(kind.title.lowercased())") {
                                        signatureCaptureKind = kind
                                    }
                                }
                            } label: {
                                Label(kind.title, systemImage: kind.icon)
                            }
                        }
                    } label: {
                        Label("Add", systemImage: "plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("reader.annotation.add")

                    Button {
                        session.beginAnnotationEditing()
                        close()
                    } label: {
                        Label("Edit", systemImage: "square.dashed")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .frame(minHeight: 44)
                    .disabled(session.annotations.isEmpty)
                    .accessibilityHint(session.annotations.isEmpty ? "Add an annotation first" : "Select, move, resize, or delete an annotation")
                    .accessibilityIdentifier("reader.annotation.edit")

                    Menu {
                        ForEach(MarkupKind.allCases) { kind in
                            Button {
                                session.applyMarkup(kind)
                                close()
                            } label: {
                                Label(kind.title, systemImage: kind.icon)
                            }
                        }
                    } label: {
                        Label("Mark", systemImage: "highlighter")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .frame(minHeight: 44)
                    .disabled(!session.hasTextSelection)
                    .accessibilityHint(session.hasTextSelection ? "Choose a markup style" : "Select text in the PDF first")
                }
            }
            .padding(16)

            Divider()

            if session.annotations.isEmpty {
                ContentUnavailableView(
                    "No annotations yet",
                    systemImage: "pencil.and.scribble",
                    description: Text("Draw, add a stamp, or select text to highlight, underline, or strike it out.")
                )
            } else {
                List(session.annotations) { item in
                    Button {
                        session.goToAnnotation(item)
                        close()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: item.icon)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Color(uiColor: item.color))
                                .frame(width: 28, height: 28)
                                .background(Color(uiColor: item.color).opacity(0.12), in: Circle())
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title)
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(FolikTheme.ink)
                                Text(item.excerpt)
                                    .font(.subheadline)
                                    .foregroundStyle(FolikTheme.mutedInk)
                                    .lineLimit(2)
                                Text("Page \(item.pageIndex + 1)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(FolikTheme.mutedInk)
                            }
                            Spacer(minLength: 4)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(FolikTheme.mutedInk)
                                .accessibilityHidden(true)
                        }
                        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("reader.annotation.\(item.id)")
                    .accessibilityLabel("\(item.title), \(item.excerpt), page \(item.pageIndex + 1)")
                    .swipeActions {
                        Button("Delete", role: .destructive) {
                            session.deleteAnnotation(item)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .alert(textPlacementKind?.title ?? "Add text", isPresented: textAlertIsPresented) {
            TextField("Text", text: $draftText, axis: .vertical)
            Button("Cancel", role: .cancel) {
                textPlacementKind = nil
                draftText = ""
            }
            Button("Place on page") {
                guard let kind = textPlacementKind else { return }
                session.beginAnnotationPlacement(kind, text: draftText)
                textPlacementKind = nil
                draftText = ""
                close()
            }
            .disabled(draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("Enter the text, then tap the page where it should appear.")
        }
        .sheet(item: $signatureCaptureKind, onDismiss: {
            if signaturePlaced { signaturePlaced = false; close() }
        }) { kind in
            SignatureCaptureView(
                kind: kind,
                existingAsset: session.savedSignatureAsset(for: kind)
            ) { asset in
                session.saveSignatureAsset(asset)
                session.beginSignaturePlacement(asset)
                signaturePlaced = true
            }
        }
        .onAppear {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--open-signature-capture") {
                signatureCaptureKind = .signature
            }
            #endif
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility5)
    }

    private var textAlertIsPresented: Binding<Bool> {
        Binding(
            get: { textPlacementKind != nil },
            set: { if !$0 { textPlacementKind = nil } }
        )
    }
}

private struct PageNavigator: View {
    private enum Filter: String, CaseIterable, Identifiable {
        case all = "All"
        case bookmarks = "Bookmarks"

        var id: Self { self }
    }

    @ObservedObject var session: DocumentSession
    let close: () -> Void
    let organizePages: () -> Void
    @State private var filter: Filter = .all
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let columns = [GridItem(.adaptive(minimum: 92, maximum: 132), spacing: 14)]

    private var displayedPageIndices: [Int] {
        switch filter {
        case .all:
            Array(0..<session.pageCount)
        case .bookmarks:
            session.bookmarkedPageIndices.sorted()
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 12) {
                        pageSummary
                        organizeButton
                            .frame(maxWidth: .infinity)
                    }
                } else {
                    HStack {
                        pageSummary
                        Spacer(minLength: 8)
                        organizeButton
                    }
                }
            }
            .padding(16)

            Picker("Page filter", selection: $filter) {
                ForEach(Filter.allCases) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            .accessibilityIdentifier("reader.pages.filter")

            Divider()

            if filter == .bookmarks && displayedPageIndices.isEmpty {
                ContentUnavailableView {
                    Label("No Bookmarks", systemImage: "bookmark")
                } description: {
                    Text("Use the bookmark button beside the page number to save a page here.")
                }
                .accessibilityIdentifier("reader.pages.bookmarks.empty")
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 18) {
                        if let document = session.document {
                            ForEach(displayedPageIndices, id: \.self) { index in
                                if let page = document.page(at: index) {
                                    Button {
                                        session.goToPage(index)
                                        close()
                                    } label: {
                                        VStack(spacing: 7) {
                                            Group {
                                                if document.isEncrypted {
                                                    PDFPageThumbnail(page: page)
                                                } else {
                                                    FilePDFThumbnail(url: session.item.url, page: index, size: CGSize(width: 132, height: 180), revision: "\(session.documentRevision)")
                                                }
                                            }
                                                .aspectRatio(page.bounds(for: .cropBox).size, contentMode: .fit)
                                                .overlay(alignment: .topTrailing) {
                                                    if session.bookmarkedPageIndices.contains(index) {
                                                        Image(systemName: "bookmark.fill")
                                                            .font(.system(size: 14, weight: .bold))
                                                            .foregroundStyle(.white)
                                                            .padding(7)
                                                            .background(FolikTheme.cobalt, in: Circle())
                                                            .padding(6)
                                                            .accessibilityHidden(true)
                                                    }
                                                }
                                            Text("\(index + 1)")
                                                .font(.caption.monospacedDigit().weight(.semibold))
                                                .foregroundStyle(index == session.pageIndex ? FolikTheme.cobalt : FolikTheme.mutedInk)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("reader.pages.page.\(index)")
                                    .accessibilityLabel("Page \(index + 1)")
                                    .accessibilityValue(pageAccessibilityValue(for: index))
                                }
                            }
                        }
                    }
                    .padding(16)
                }
            }
        }
    }

    private var pageSummary: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(session.pageCount) page\(session.pageCount == 1 ? "" : "s")")
                .font(.headline)
            Text("Jump to a page or create an organized copy.")
                .font(.subheadline)
                .foregroundStyle(FolikTheme.mutedInk)
        }
    }

    private var organizeButton: some View {
        Button(action: organizePages) {
            Label("Organize", systemImage: "rectangle.3.group")
                .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil)
        }
        .buttonStyle(.borderedProminent)
        .tint(FolikTheme.cobalt)
        .frame(minHeight: 44)
        .disabled(session.isLocked || session.pageCount == 0)
        .accessibilityIdentifier("reader.pages.organize")
    }

    private func pageAccessibilityValue(for index: Int) -> String {
        var values: [String] = []
        if index == session.pageIndex { values.append("Current page") }
        if session.bookmarkedPageIndices.contains(index) { values.append("Bookmarked") }
        return values.joined(separator: ", ")
    }
}

struct PDFPageThumbnail: View {
    let page: PDFPage
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color.white
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                ProgressView()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .stroke(FolikTheme.separator, lineWidth: 0.5)
        }
        .onAppear {
            guard image == nil else { return }
            image = page.thumbnail(of: CGSize(width: 220, height: 300), for: .cropBox)
        }
        .accessibilityHidden(true)
    }
}

private struct OutlineNavigator: View {
    @ObservedObject var session: DocumentSession
    let close: () -> Void

    var body: some View {
        if session.outlineEntries.isEmpty {
            ContentUnavailableView(
                "No table of contents",
                systemImage: "list.bullet.indent",
                description: Text("This PDF doesn’t include an outline.")
            )
        } else {
            List(session.outlineEntries) { entry in
                Button {
                    session.goToOutline(entry)
                    close()
                } label: {
                    Text(entry.title)
                        .font(.body)
                        .foregroundStyle(FolikTheme.ink)
                        .padding(.leading, CGFloat(entry.level) * 14)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
        }
    }
}

private struct SearchNavigator: View {
    @ObservedObject var session: DocumentSession
    let close: () -> Void
    @State private var query: String

    init(session: DocumentSession, close: @escaping () -> Void) {
        self.session = session
        self.close = close
        _query = State(initialValue: session.searchQuery)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(FolikTheme.mutedInk)
                    .accessibilityHidden(true)
                TextField("Find in document", text: $query)
                    .accessibilityIdentifier("reader.find.query")
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit { session.search(for: query) }
                if !query.isEmpty {
                    Button {
                        query = ""
                        session.search(for: "")
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(FolikTheme.mutedInk)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.leading, 14)
            .background(FolikTheme.raisedSurface, in: RoundedRectangle(cornerRadius: 12))
            .padding(16)

            Divider()

            if !session.searchMatches.isEmpty {
                HStack(spacing: 8) {
                    Text(session.searchPositionLabel)
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                        .foregroundStyle(FolikTheme.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button { session.moveToSearchMatch(offset: -1) } label: {
                        Image(systemName: "chevron.up")
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Previous result")
                    .accessibilityIdentifier("reader.find.previous")

                    Button { session.moveToSearchMatch(offset: 1) } label: {
                        Image(systemName: "chevron.down")
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Next result")
                    .accessibilityIdentifier("reader.find.next")
                }
                .padding(.horizontal, 16)

                if session.isSearching {
                    ProgressView(value: session.searchProgress)
                        .tint(FolikTheme.cobalt)
                        .padding(.horizontal, 16)
                        .accessibilityLabel("Search progress")
                        .accessibilityValue("\(Int(session.searchProgress * 100)) percent")
                }

                Divider()
            }

            if query.isEmpty {
                ContentUnavailableView(
                    "Find text",
                    systemImage: "text.magnifyingglass",
                    description: Text("Search every page of this PDF.")
                )
            } else if session.isSearching && session.searchMatches.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Searching every page…")
                        .font(.subheadline)
                        .foregroundStyle(FolikTheme.mutedInk)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Searching every page")
            } else if session.searchMatches.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                List(session.searchMatches) { match in
                    Button {
                        session.goToMatch(match)
                        close()
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(match.excerpt)
                                    .font(.body)
                                    .foregroundStyle(FolikTheme.ink)
                                    .lineLimit(3)
                                Text("Page \(match.pageIndex + 1)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(FolikTheme.mutedInk)
                            }
                            Spacer(minLength: 4)
                            if session.selectedSearchMatchIndex == session.searchMatches.firstIndex(where: { $0.id == match.id }) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(FolikTheme.cobalt)
                                    .accessibilityHidden(true)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(
                        session.selectedSearchMatchIndex == session.searchMatches.firstIndex(where: { $0.id == match.id })
                            ? "Current result" : ""
                    )
                }
                .listStyle(.plain)
            }
        }
        .task(id: query) {
            guard !query.isEmpty else { return }
            try? await Task.sleep(for: .milliseconds(280))
            guard !Task.isCancelled, query != session.searchQuery else { return }
            session.search(for: query)
        }
    }
}

private struct FormNavigator: View {
    @ObservedObject var session: DocumentSession
    let close: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var fieldSetupKind: FormFieldPlacementKind?
    @State private var signatureCaptureKind: SignatureKind?
    @State private var signaturePlaced = false
    @State private var suggestions: [FormFieldSuggestion] = []
    @State private var suggestionData: Data?
    @State private var selectedSuggestionIDs: Set<UUID> = []
    @State private var isSuggestingFields = false
    @State private var suggestionMessage: String?
    @State private var suggestionTask: Task<Void, Never>?
    @State private var fieldPendingDeletion: FormField?
    @State private var savingTemplate = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Form mode", selection: Binding(get: { session.formMode }, set: session.setFormMode)) {
                    ForEach(FormWorkspaceMode.allCases) { mode in Text(mode.title).tag(mode) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("reader.form.mode")
                if dynamicTypeSize.isAccessibilitySize {
                    formSummary
                    if !session.formFields.isEmpty {
                        saveButton(fullWidth: true)
                            .controlSize(.large)
                    }
                } else {
                    HStack(alignment: .firstTextBaseline) {
                        formSummary
                        Spacer(minLength: 12)
                        if !session.formFields.isEmpty {
                            saveButton(fullWidth: false)
                        }
                    }
                }

                if session.formMode == .fill {
                    SignDocumentButton(session: session, close: close, capture: { signatureCaptureKind = .signature })
                    if session.formFields.isEmpty {
                        Button("Build a fillable form") { session.setFormMode(.build) }
                            .frame(minHeight: 44)
                            .accessibilityIdentifier("reader.form.startBuilding")
                    }
                }

                if session.formMode == .fill && session.fillableFormFieldCount > 0 {
                    ProgressView(value: Double(session.completedFormFieldCount), total: Double(session.fillableFormFieldCount))
                        .tint(FolikTheme.cobalt)
                        .accessibilityLabel("Form completion")
                        .accessibilityValue("\(session.completedFormFieldCount) of \(session.fillableFormFieldCount) fields filled")

                    if session.incompleteFormFieldCount > 0 {
                        Button {
                            close()
                            DispatchQueue.main.async {
                                session.goToNextIncompleteFormField()
                            }
                        } label: {
                            Label(
                                session.remainingRequiredFormFieldCount > 0 ? "Next required field" : "Next empty field",
                                systemImage: "arrow.down.circle"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(FolikTheme.cobalt)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("reader.form.nextIncomplete")
                        .accessibilityHint("Moves to the next field that still needs a value")
                    }
                }

                if let notice = session.formCompatibilityNotice {
                    Label(notice, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if session.formMode == .build {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) { formAuthoringButtons }
                        VStack(spacing: 8) { formAuthoringButtons }
                    }

                    if isSuggestingFields {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Looking for labels, boxes, and checkboxes…")
                                .font(.footnote)
                                .foregroundStyle(FolikTheme.mutedInk)
                            Spacer(minLength: 4)
                            Button("Cancel") { suggestionTask?.cancel() }
                                .frame(minHeight: 44)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Looking for suggested form fields")
                    } else if let suggestionMessage {
                        Label(suggestionMessage, systemImage: "info.circle")
                            .font(.footnote)
                            .foregroundStyle(FolikTheme.mutedInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Button("Save as My Template") { savingTemplate = true }
                    .frame(minHeight: 44)
                    .disabled(session.isLocked || !session.canFillForms)
                    .accessibilityIdentifier("reader.form.saveTemplate")

                if session.isModified {
                    Button("Revert unsaved form changes", role: .destructive, action: session.revertFormChanges)
                        .font(.subheadline.weight(.semibold))
                }
            }
            .padding(16)

            Divider()

            List(session.formFields) { field in
                HStack(spacing: 4) {
                    Button {
                        close()
                        DispatchQueue.main.async {
                            if session.formMode == .build {
                                session.beginFormLayoutEditing()
                                session.selectAnnotation(field.annotation, pageIndex: field.pageIndex)
                            } else { session.goToFormField(field) }
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: field.isFilled ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(field.isFilled ? FolikTheme.cobalt : FolikTheme.mutedInk)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Text(field.title)
                                        .font(.body.weight(.medium))
                                        .foregroundStyle(FolikTheme.ink)
                                    if field.isRequired {
                                        Text("Required")
                                            .font(.caption2.weight(.bold))
                                            .foregroundStyle(FolikTheme.cobalt)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(FolikTheme.cobalt.opacity(0.1), in: Capsule())
                                    }
                                }
                                Text("\(field.kind.title) · Page \(field.pageIndex + 1)\(field.limitation.map { " · \($0)" } ?? "")")
                                    .font(.caption)
                                    .foregroundStyle(FolikTheme.mutedInk)
                                if session.formMode == .fill && field.limitation == nil {
                                    Text(field.statusText)
                                        .font(.caption)
                                        .foregroundStyle(field.isFilled ? FolikTheme.cobalt : FolikTheme.mutedInk)
                                        .lineLimit(1)
                                }
                            }
                            Spacer(minLength: 4)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(FolikTheme.mutedInk)
                                .accessibilityHidden(true)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .disabled((session.formMode == .fill && !field.isEditable) || !session.canFillForms)
                    .accessibilityIdentifier("reader.form.field.\(field.id)")
                    .accessibilityValue("\(field.isRequired ? "Required, " : "")\(field.statusText)")

                    if session.formMode == .build && field.isAuthoredByFolik {
                        Button(role: .destructive) {
                            fieldPendingDeletion = field
                        } label: {
                            Image(systemName: "trash")
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.red)
                        .accessibilityLabel("Delete \(field.title) form area")
                        .accessibilityHint("Asks for confirmation before removing this added field")
                        .accessibilityIdentifier("reader.form.delete.\(field.id)")
                    }
                }
            }
            .listStyle(.plain)
        }
        .sheet(item: $signatureCaptureKind, onDismiss: {
            if signaturePlaced { signaturePlaced = false; close() }
        }) { kind in
            SignatureCaptureView(kind: kind, existingAsset: session.savedSignatureAsset(for: kind)) { asset in
                session.saveSignatureAsset(asset)
                session.beginSignaturePlacement(asset)
                signaturePlaced = true
            }
        }
        .sheet(isPresented: $savingTemplate) { SavePersonalTemplateView(session: session) }
        .sheet(item: $fieldSetupKind) { kind in
            FormFieldSetupView(kind: kind) { label, isRequired in
                session.beginFormFieldPlacement(kind, label: label, isRequired: isRequired)
                fieldSetupKind = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { close() }
            }
        }
        .sheet(isPresented: Binding(
            get: { !suggestions.isEmpty },
            set: { if !$0 { suggestions = []; selectedSuggestionIDs = [] } }
        )) {
            FormSuggestionReviewView(
                suggestions: $suggestions,
                data: suggestionData,
                selectedIDs: $selectedSuggestionIDs,
                apply: applySelectedSuggestions
            )
        }
        .confirmationDialog(
            "Delete form area?",
            isPresented: Binding(
                get: { fieldPendingDeletion != nil },
                set: { if !$0 { fieldPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let field = fieldPendingDeletion {
                Button("Delete \(field.title)", role: .destructive) {
                    session.deleteAuthoredFormField(field)
                    fieldPendingDeletion = nil
                }
            }
            Button("Cancel", role: .cancel) { fieldPendingDeletion = nil }
        } message: {
            Text("This removes the added PDF field. You can undo it while this document remains open.")
        }
        .onDisappear { suggestionTask?.cancel() }
        .dynamicTypeSize(...DynamicTypeSize.accessibility5)
    }

    @ViewBuilder
    private var formAuthoringButtons: some View {
        Button(action: suggestFields) {
            Label("Suggest fields", systemImage: "wand.and.stars")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .frame(maxWidth: .infinity, minHeight: 44)
        .disabled(isSuggestingFields || session.isLocked || !session.canFillForms)
        .accessibilityHint("Scans this PDF on device and lets you review likely fields before adding them")
        .accessibilityIdentifier("reader.form.suggest")

        Menu {
            ForEach(FormFieldPlacementKind.allCases) { kind in
                Button { fieldSetupKind = kind } label: {
                    Label(kind.title, systemImage: kind.icon)
                }
            }
        } label: {
            Label("Add field", systemImage: "plus.rectangle.on.rectangle")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(FolikTheme.cobalt)
        .frame(maxWidth: .infinity, minHeight: 44)
        .disabled(session.isLocked || !session.canFillForms)
        .accessibilityHint(session.canFillForms ? "Choose a field type to place on the page" : "This PDF does not allow form editing")
        .accessibilityIdentifier("reader.form.add")

        Button {
            session.beginFormLayoutEditing()
            close()
        } label: {
            Label("Edit layout", systemImage: "square.dashed")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .frame(maxWidth: .infinity, minHeight: 44)
        .disabled(session.formFields.isEmpty)
        .accessibilityHint(session.formFields.isEmpty ? "Add a field first" : "Move, resize, or delete fields on the page")
        .accessibilityIdentifier("reader.form.editLayout")
    }

    private func suggestFields() {
        guard !isSuggestingFields else { return }
        isSuggestingFields = true
        suggestionMessage = nil
        suggestionTask = Task {
            defer { isSuggestingFields = false }
            do {
                let found = try await session.suggestFormFields()
                try Task.checkCancellation()
                guard !found.isEmpty else {
                    suggestionMessage = "No confident fields were found. You can still add fields manually."
                    return
                }
                suggestionData = session.document?.dataRepresentation()
                suggestions = found
                selectedSuggestionIDs = Set(found.map(\.id))
            } catch is CancellationError {
                suggestionMessage = "Field suggestions were canceled."
            } catch {
                suggestionMessage = "Folik couldn’t suggest fields. \(error.localizedDescription)"
            }
        }
    }

    private func applySelectedSuggestions() {
        let selected = suggestions.filter { selectedSuggestionIDs.contains($0.id) }
        suggestions = []
        selectedSuggestionIDs = []
        session.addFormFieldSuggestions(selected)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { close() }
    }

    private var formSummary: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(formSummaryTitle)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
            Text(formInstructions)
                .font(.subheadline)
                .foregroundStyle(FolikTheme.mutedInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var formSummaryTitle: String {
        if session.formMode == .build {
            return session.formFields.isEmpty ? "No fields yet" : "\(session.formFieldCount) field\(session.formFieldCount == 1 ? "" : "s") to arrange"
        }
        if session.formFields.isEmpty {
            return session.formCompatibilityNotice == nil ? "No fields yet" : "Form unavailable"
        }
        if session.fillableFormFieldCount > 0 {
            return "\(session.completedFormFieldCount) of \(session.fillableFormFieldCount) filled"
        }
        return "\(session.formFieldCount) field\(session.formFieldCount == 1 ? "" : "s")"
    }

    private var formInstructions: String {
        if session.formMode == .build { return "Add and arrange fields, then switch to Fill to try your form. Values entered in Fill are saved." }
        if session.formFields.isEmpty { return "Add fields to turn this PDF into a fillable form." }
        if session.remainingRequiredFormFieldCount > 0 {
            let count = session.remainingRequiredFormFieldCount
            return "\(count) required field\(count == 1 ? "" : "s") still \(count == 1 ? "needs" : "need") a value."
        }
        return session.canFillForms
            ? "Tap a field below, then enter its value directly on the page."
            : "This PDF does not allow form editing."
    }

    private func saveButton(fullWidth: Bool) -> some View {
        Button(action: session.requestSave) {
            Text("Save changes")
                .frame(maxWidth: fullWidth ? .infinity : nil)
        }
            .buttonStyle(.borderedProminent)
            .tint(FolikTheme.cobalt)
            .disabled(!session.isModified)
    }
}

private struct FormFieldSetupView: View {
    let kind: FormFieldPlacementKind
    let complete: (String, Bool) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var label = ""
    @State private var isRequired = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Field label", text: $label)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .onSubmit(place)
                    Toggle("Required", isOn: $isRequired)
                } header: {
                    Label(kind.title, systemImage: kind.icon)
                } footer: {
                    Text("After continuing, tap the page where the field belongs. You can move or resize it afterward with Edit layout.")
                }

                if kind == .signature {
                    Section {
                        Label(
                            "This creates a standard PDF signature field for compatible signing apps. In Folik, switch to Fill and use Sign to place a visual signature.",
                            systemImage: "info.circle"
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("New Field")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Continue", action: place)
                        .disabled(normalizedLabel.isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var normalizedLabel: String {
        String(label.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
    }

    private func place() {
        guard !normalizedLabel.isEmpty else { return }
        complete(normalizedLabel, isRequired)
    }
}

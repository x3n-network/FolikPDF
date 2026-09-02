import PDFKit
import SwiftUI

struct ReaderInspector: View {
    let panel: ReaderPanel
    @ObservedObject var session: DocumentSession
    let close: () -> Void
    let organizePages: () -> Void

    var body: some View {
        Group {
            switch panel {
            case .pages:
                PageNavigator(session: session, close: close, organizePages: organizePages)
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

private struct AnnotationNavigator: View {
    @ObservedObject var session: DocumentSession
    let close: () -> Void
    @State private var textPlacementKind: AnnotationPlacementKind?
    @State private var signatureCaptureKind: SignatureKind?
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
        .sheet(item: $signatureCaptureKind) { kind in
            SignatureCaptureView(
                kind: kind,
                existingAsset: session.savedSignatureAsset(for: kind)
            ) { asset in
                session.saveSignatureAsset(asset)
                session.beginSignaturePlacement(asset)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { close() }
            }
        }
        .onAppear {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--open-signature-capture") {
                signatureCaptureKind = .signature
            }
            #endif
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
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
                                            PDFPageThumbnail(page: page)
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
            guard !Task.isCancelled else { return }
            session.search(for: query)
        }
    }
}

private struct FormNavigator: View {
    @ObservedObject var session: DocumentSession
    let close: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
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

                if session.fillableFormFieldCount > 0 {
                    ProgressView(value: Double(session.completedFormFieldCount), total: Double(session.fillableFormFieldCount))
                        .tint(FolikTheme.cobalt)
                        .accessibilityLabel("Form completion")
                        .accessibilityValue("\(session.completedFormFieldCount) of \(session.fillableFormFieldCount) fields filled")

                    if session.incompleteFormFieldCount > 0 {
                        Button {
                            session.goToNextIncompleteFormField()
                            close()
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

                if session.isModified {
                    Button("Revert unsaved form changes", role: .destructive, action: session.revertFormChanges)
                        .font(.subheadline.weight(.semibold))
                }
            }
            .padding(16)

            Divider()

            List(session.formFields) { field in
                Button {
                    session.goToFormField(field)
                    close()
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
                            if field.limitation == nil {
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
                .disabled(!field.isEditable || !session.canFillForms)
                .accessibilityIdentifier("reader.form.field.\(field.id)")
                .accessibilityValue("\(field.isRequired ? "Required, " : "")\(field.statusText)")
            }
            .listStyle(.plain)
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }

    private var formSummary: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(session.fillableFormFieldCount > 0 ? "\(session.completedFormFieldCount) of \(session.fillableFormFieldCount) filled" : "Form unavailable")
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
            Text(formInstructions)
                .font(.subheadline)
                .foregroundStyle(FolikTheme.mutedInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var formInstructions: String {
        if session.formFields.isEmpty { return "Folik found no standard fields it can edit." }
        if session.remainingRequiredFormFieldCount > 0 {
            return "\(session.remainingRequiredFormFieldCount) required field\(session.remainingRequiredFormFieldCount == 1 ? "" : "s") still need a value."
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

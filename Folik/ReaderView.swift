import PDFKit
import SwiftUI
import UIKit

enum ReaderPanel: String, Identifiable {
    case pages
    case outline
    case search
    case annotations
    case forms

    var id: Self { self }
    var title: String {
        switch self {
        case .pages: "Pages"
        case .outline: "Contents"
        case .search: "Find"
        case .annotations: "Annotations"
        case .forms: "Forms"
        }
    }
    var icon: String {
        switch self {
        case .pages: "square.grid.2x2"
        case .outline: "list.bullet.indent"
        case .search: "magnifyingglass"
        case .annotations: "pencil.and.list.clipboard"
        case .forms: "list.clipboard"
        }
    }
}

struct ReaderView: View {
    @StateObject private var session: DocumentSession
    @State private var presentedPanel: ReaderPanel?
    @State private var passwordPromptPresented = false
    @State private var isExporting = false
    @State private var preparedExport: PreparedExport?
    @State private var pageOrganizerPresented = false
    @State private var pageOrganizerPending = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(item: LibraryDocument) {
        _session = StateObject(wrappedValue: DocumentSession(item: item))
    }

    var body: some View {
        HStack(spacing: 0) {
            if horizontalSizeClass == .regular, let presentedPanel {
                ReaderInspector(
                    panel: presentedPanel,
                    session: session,
                    close: { self.presentedPanel = nil },
                    organizePages: requestPageOrganizer
                )
                .frame(width: 330)
                Divider()
            }

            documentCanvas
        }
        .background(FolikTheme.canvas)
        .navigationTitle(session.item.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { readerToolbar }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ReaderBottomChrome(session: session, presentedPanel: $presentedPanel)
        }
        .sheet(item: compactPanelBinding, onDismiss: presentPendingPageOrganizer) { panel in
            NavigationStack {
                ReaderInspector(
                    panel: panel,
                    session: session,
                    close: { presentedPanel = nil },
                    organizePages: requestPageOrganizer
                )
            }
            .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $passwordPromptPresented) {
            PasswordPrompt(session: session)
                .interactiveDismissDisabled(session.isLocked)
        }
        .sheet(item: $preparedExport) { export in
            ActivityView(items: [export.url])
                .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $pageOrganizerPresented) {
            PageOrganizerView(sourceURL: session.item.url)
        }
        .onAppear {
            passwordPromptPresented = session.isLocked
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--clear-saved-signatures") {
                session.deleteSavedSignature(for: .signature)
                session.deleteSavedSignature(for: .initials)
            }
            if ProcessInfo.processInfo.arguments.contains("--clear-bookmarks") {
                session.clearBookmarks()
            }
            if ProcessInfo.processInfo.arguments.contains("--bookmark-current-page"),
               !session.isCurrentPageBookmarked {
                session.toggleCurrentPageBookmark()
            }
            if let screenshotQuery = ProcessInfo.processInfo.arguments.value(after: "--find-query") {
                session.search(for: screenshotQuery)
                presentedPanel = .search
            } else if ProcessInfo.processInfo.arguments.contains("--open-page-organizer") {
                pageOrganizerPresented = true
            } else if ProcessInfo.processInfo.arguments.contains("--open-pages-panel") {
                presentedPanel = .pages
            } else if ProcessInfo.processInfo.arguments.contains("--open-forms-panel") {
                presentedPanel = .forms
            } else if ProcessInfo.processInfo.arguments.contains("--open-annotations-panel") {
                presentedPanel = .annotations
            } else if ProcessInfo.processInfo.arguments.contains("--open-find-panel") {
                session.search(for: "searchable")
                presentedPanel = .search
            }
            if ProcessInfo.processInfo.arguments.contains("--place-test-signature") {
                let asset = SignatureAsset(kind: .signature, strokes: [], typedText: "Joseph Spears")
                session.beginSignaturePlacement(asset)
                session.placeAnnotationAtCurrentPageCenter()
            } else if ProcessInfo.processInfo.arguments.contains("--start-drawing") {
                presentedPanel = nil
                session.setDrawingEnabled(true)
            } else if ProcessInfo.processInfo.arguments.contains("--start-rectangle-placement") {
                presentedPanel = nil
                session.beginAnnotationPlacement(.rectangle)
            } else if ProcessInfo.processInfo.arguments.contains("--start-annotation-editing") {
                presentedPanel = nil
                var annotationToSelect: DocumentAnnotation?
                if ProcessInfo.processInfo.arguments.contains("--add-editable-test-annotation") {
                    let existingAnnotations = Set(session.annotations.map { ObjectIdentifier($0.annotation) })
                    session.beginAnnotationPlacement(.rectangle)
                    session.placeAnnotationAtCurrentPageCenter()
                    annotationToSelect = session.annotations.first {
                        !existingAnnotations.contains(ObjectIdentifier($0.annotation))
                    }
                }
                session.beginAnnotationEditing()
                if ProcessInfo.processInfo.arguments.contains("--select-first-annotation"),
                   let annotation = annotationToSelect ?? session.annotations.first {
                    session.selectAnnotation(annotation.annotation, pageIndex: annotation.pageIndex)
                }
            }
            if ProcessInfo.processInfo.arguments.contains("--fill-form-for-export-qa") {
                session.formFields.first(where: { $0.kind == .text })?.annotation.widgetStringValue = "Folik Real PDF Test"
                session.formFields.first(where: { $0.kind == .checkbox })?.annotation.buttonWidgetState = .onState
                session.noteFormEditing()
                session.persistChanges()
            }
            if ProcessInfo.processInfo.arguments.contains("--prepare-flattened-export") {
                prepareExport(.flattened)
            }
            #endif
        }
        .onChange(of: session.isLocked) { _, isLocked in
            passwordPromptPresented = isLocked
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active, session.isModified { session.requestSave() }
        }
        .onDisappear {
            if session.isModified { session.requestSave() }
        }
        .alert("Document problem", isPresented: errorIsPresented) {
            Button("OK", role: .cancel) { session.errorMessage = nil }
        } message: {
            Text(session.errorMessage ?? "The PDF could not be opened.")
        }
    }

    private func requestPageOrganizer() {
        if horizontalSizeClass == .compact {
            pageOrganizerPending = true
            presentedPanel = nil
        } else {
            pageOrganizerPresented = true
        }
    }

    private func presentPendingPageOrganizer() {
        guard pageOrganizerPending else { return }
        pageOrganizerPending = false
        pageOrganizerPresented = true
    }

    @ViewBuilder
    private var documentCanvas: some View {
        if session.document != nil {
            PDFKitView(session: session)
                .accessibilityLabel("PDF document")
                .accessibilityValue(selectedAnnotationCanvasDescription)
        } else {
            ContentUnavailableView(
                "Unable to open PDF",
                systemImage: "doc.badge.ellipsis",
                description: Text("This file may be damaged or use a format PDFKit cannot read.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(FolikTheme.surface)
        }
    }

    private var selectedAnnotationCanvasDescription: String {
        guard
            let selected = session.selectedAnnotation,
            let page = session.document?.page(at: selected.pageIndex)
        else { return "" }
        let pageBounds = page.bounds(for: .cropBox)
        guard pageBounds.width > 0, pageBounds.height > 0 else {
            return "\(selected.title) selected"
        }
        let center = CGPoint(x: selected.annotation.bounds.midX, y: selected.annotation.bounds.midY)
        let horizontal = Int(((center.x - pageBounds.minX) / pageBounds.width * 100).rounded())
        let vertical = Int(((center.y - pageBounds.minY) / pageBounds.height * 100).rounded())
        return "\(selected.title) selected, \(horizontal) percent across, \(vertical) percent up"
    }

    @ToolbarContentBuilder
    private var readerToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            if !session.formFields.isEmpty {
                Button("Save", action: session.requestSave)
                    .disabled(!session.isModified)
                    .accessibilityHint(session.isModified ? "Saves form and annotation changes" : "No unsaved changes")
            }

            Menu {
                ForEach(ReaderLayout.allCases) { layout in
                    Button {
                        session.setLayout(layout)
                    } label: {
                        Label(layout.title, systemImage: layout == session.layout ? "checkmark" : layout.icon)
                    }
                }
                Button(action: session.fitPage) {
                    Label("Fit Page", systemImage: "arrow.up.left.and.arrow.down.right")
                }
            } label: {
                Image(systemName: "rectangle.on.rectangle")
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Page layout")

            Menu {
                Section("Keep editable") {
                    Button { prepareExport(.original) } label: {
                        Label("Share Original", systemImage: "doc")
                    }
                    Button { prepareExport(.editable) } label: {
                        Label("Editable Copy", systemImage: "doc.on.doc")
                    }
                }
                Section("Make marks permanent") {
                    Button { prepareExport(.flattened) } label: {
                        Label("Flattened Copy", systemImage: "doc.badge.checkmark")
                    }
                }
            } label: {
                Group {
                    if isExporting {
                        ProgressView()
                    } else {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
                .frame(width: 44, height: 44)
            }
            .disabled(isExporting)
            .accessibilityIdentifier("reader.export")
            .accessibilityLabel(isExporting ? "Preparing PDF" : "Export and share")
        }
    }

    private func prepareExport(_ mode: DocumentExportMode) {
        guard !isExporting else { return }
        isExporting = true
        session.requestSave()
        Task {
            try? await Task.sleep(for: .milliseconds(200))
            do {
                let sourceURL = session.item.url
                let url = try await Task.detached(priority: .userInitiated) {
                    try DocumentExporter.export(sourceURL: sourceURL, mode: mode)
                }.value
                preparedExport = PreparedExport(url: url)
            } catch {
                session.errorMessage = "Folik couldn’t prepare this PDF copy. \(error.localizedDescription)"
            }
            isExporting = false
        }
    }

    private var compactPanelBinding: Binding<ReaderPanel?> {
        Binding(
            get: { horizontalSizeClass == .compact ? presentedPanel : nil },
            set: { presentedPanel = $0 }
        )
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { session.errorMessage != nil },
            set: { if !$0 { session.errorMessage = nil } }
        )
    }
}

#if DEBUG
private extension [String] {
    func value(after flag: String) -> String? {
        guard let flagIndex = firstIndex(of: flag) else { return nil }
        let valueIndex = index(after: flagIndex)
        guard indices.contains(valueIndex) else { return nil }
        return self[valueIndex]
    }
}
#endif

private struct PreparedExport: Identifiable {
    let id = UUID()
    let url: URL
}

private struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct ReaderBottomChrome: View {
    @ObservedObject var session: DocumentSession
    @Binding var presentedPanel: ReaderPanel?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button(action: session.previousPage) {
                    Image(systemName: "chevron.left")
                        .frame(width: 44, height: 44)
                }
                .disabled(session.pageIndex == 0)
                .accessibilityIdentifier("reader.previousPage")
                .accessibilityLabel("Previous page")

                Text(session.pageLabel)
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                    .foregroundStyle(FolikTheme.ink)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("reader.pageStatus")
                    .accessibilityLabel("Page \(session.pageLabel)")

                Button(action: session.toggleCurrentPageBookmark) {
                    Image(systemName: session.isCurrentPageBookmarked ? "bookmark.fill" : "bookmark")
                        .foregroundStyle(session.isCurrentPageBookmarked ? FolikTheme.cobalt : FolikTheme.ink)
                        .frame(width: 44, height: 44)
                }
                .disabled(session.pageCount == 0)
                .accessibilityIdentifier("reader.bookmarkCurrentPage")
                .accessibilityLabel(
                    session.isCurrentPageBookmarked
                        ? "Remove bookmark from page \(session.pageIndex + 1)"
                        : "Bookmark page \(session.pageIndex + 1)"
                )
                .accessibilityValue(session.isCurrentPageBookmarked ? "Bookmarked" : "Not bookmarked")
                .accessibilityAddTraits(session.isCurrentPageBookmarked ? .isSelected : [])

                Button(action: session.nextPage) {
                    Image(systemName: "chevron.right")
                        .frame(width: 44, height: 44)
                }
                .disabled(session.pageIndex >= session.pageCount - 1)
                .accessibilityIdentifier("reader.nextPage")
                .accessibilityLabel("Next page")
            }
            .padding(.horizontal, 12)

            Divider()

            if session.isDrawingEnabled {
                DrawingToolbar(session: session)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
            } else if session.isAnnotationEditingEnabled {
                AnnotationEditingToolbar(session: session)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
            } else if session.annotationPlacement != nil {
                PlacementToolbar(session: session)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
            } else {
                readerTools
                    .padding(.horizontal, 10)
                    .padding(.top, 4)
                    .padding(.bottom, 6)
            }
        }
        .background(FolikTheme.raisedSurface.opacity(0.98))
        .overlay(alignment: .top) { Divider() }
    }

    @ViewBuilder
    private var readerTools: some View {
        if dynamicTypeSize.isAccessibilitySize && verticalSizeClass != .compact {
            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: 8
            ) {
                toolButtons
            }
        } else {
            HStack(spacing: 8) {
                toolButtons
            }
        }
    }

    @ViewBuilder
    private var toolButtons: some View {
        ForEach(availablePanels) { panel in
            ReaderToolButton(
                title: panel.title,
                icon: panel.icon,
                isSelected: presentedPanel == panel
            ) {
                presentedPanel = presentedPanel == panel ? nil : panel
            }
        }

    }

    private var availablePanels: [ReaderPanel] {
        var panels: [ReaderPanel] = [.pages, .outline, .search, .annotations]
        if !session.formFields.isEmpty || session.formCompatibilityNotice != nil { panels.append(.forms) }
        return panels
    }
}

private struct AnnotationEditingToolbar: View {
    @ObservedObject var session: DocumentSession
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 4) {
                    HStack {
                        modeLabel
                        Spacer()
                        doneButton
                    }
                    if session.selectedAnnotation != nil {
                        HStack(spacing: 8) {
                            if session.selectedAnnotationCanMove {
                                moveMenu.frame(maxWidth: .infinity)
                            }
                            if session.selectedAnnotationCanResize {
                                sizeMenu.frame(maxWidth: .infinity)
                            }
                            if session.selectedAnnotationCanChangeColor {
                                appearanceMenu.frame(maxWidth: .infinity)
                            }
                            deleteButton
                        }
                    } else {
                        selectionHint
                    }
                }
            } else {
                HStack(spacing: 8) {
                    modeLabel
                    Spacer(minLength: 0)
                    if session.selectedAnnotation != nil {
                        if session.selectedAnnotationCanMove { moveMenu }
                        if session.selectedAnnotationCanResize { sizeMenu }
                        if session.selectedAnnotationCanChangeColor { appearanceMenu }
                        deleteButton
                    } else {
                        selectionHint
                    }
                    doneButton
                }
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }

    private var modeLabel: some View {
        Label(
            session.selectedAnnotation?.title ?? "Edit annotations",
            systemImage: "square.dashed"
        )
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(FolikTheme.ink)
    }

    private var selectionHint: some View {
        Text("Tap or drag an annotation")
            .font(.caption)
            .foregroundStyle(FolikTheme.mutedInk)
            .frame(minHeight: 44)
    }

    private var moveMenu: some View {
        Menu {
            Button { session.moveSelectedAnnotation(horizontal: 0, vertical: 12) } label: {
                Label("Move up", systemImage: "arrow.up")
            }
            Button { session.moveSelectedAnnotation(horizontal: 0, vertical: -12) } label: {
                Label("Move down", systemImage: "arrow.down")
            }
            Button { session.moveSelectedAnnotation(horizontal: -12, vertical: 0) } label: {
                Label("Move left", systemImage: "arrow.left")
            }
            Button { session.moveSelectedAnnotation(horizontal: 12, vertical: 0) } label: {
                Label("Move right", systemImage: "arrow.right")
            }
        } label: {
            Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel("Move selected annotation")
        .accessibilityHint("Move in twelve-point steps")
        .accessibilityIdentifier("reader.annotation.move")
    }

    private var sizeMenu: some View {
        Menu {
            Button { session.resizeSelectedAnnotation(by: 10) } label: {
                Label("Make larger", systemImage: "plus.magnifyingglass")
            }
            Button { session.resizeSelectedAnnotation(by: -10) } label: {
                Label("Make smaller", systemImage: "minus.magnifyingglass")
            }
        } label: {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel("Resize selected annotation")
        .accessibilityIdentifier("reader.annotation.size")
    }

    private var appearanceMenu: some View {
        Menu {
            Section("Color") {
                ForEach(InkColor.allCases) { color in
                    Button { session.setSelectedAnnotationColor(color) } label: {
                        Label(
                            session.selectedAnnotationUsesColor(color) ? "\(color.title), selected" : color.title,
                            systemImage: session.selectedAnnotationUsesColor(color) ? "checkmark.circle.fill" : "circle.fill"
                        )
                    }
                }
            }
            if session.selectedAnnotationCanChangeLineWidth {
                Section("Line width") {
                    lineWidthButton("Fine", width: 1)
                    lineWidthButton("Medium", width: 3)
                    lineWidthButton("Bold", width: 6)
                }
            }
        } label: {
            Image(systemName: "paintpalette")
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel("Change annotation appearance")
        .accessibilityHint(
            session.selectedAnnotationCanChangeLineWidth
                ? "Choose a color or line width"
                : "Choose a color"
        )
        .accessibilityIdentifier("reader.annotation.appearance")
    }

    private func lineWidthButton(_ title: String, width: CGFloat) -> some View {
        let isSelected = abs((session.selectedAnnotationLineWidth ?? 0) - width) < 0.01
        return Button { session.setSelectedAnnotationLineWidth(width) } label: {
            Label(
                isSelected ? "\(title), selected" : title,
                systemImage: isSelected ? "checkmark" : "line.diagonal"
            )
        }
        .accessibilityLabel("\(title), \(Int(width)) point line")
    }

    private var deleteButton: some View {
        Button(role: .destructive, action: session.deleteSelectedAnnotation) {
            Image(systemName: "trash")
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel("Delete selected annotation")
        .accessibilityIdentifier("reader.annotation.deleteSelected")
    }

    private var doneButton: some View {
        Button("Done", action: session.finishAnnotationEditing)
            .frame(minHeight: 44)
            .accessibilityIdentifier("reader.annotation.doneEditing")
    }
}

private struct PlacementToolbar: View {
    @ObservedObject var session: DocumentSession
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 4) {
                    HStack {
                        modeLabel
                        Spacer()
                        cancelButton
                    }
                    placeButton
                        .frame(maxWidth: .infinity)
                }
            } else {
                HStack(spacing: 8) {
                    modeLabel
                    Spacer(minLength: 0)
                    Text("Tap the page")
                        .font(.caption)
                        .foregroundStyle(FolikTheme.mutedInk)
                    placeButton
                    cancelButton
                }
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }

    private var modeLabel: some View {
        Label(session.annotationPlacement?.title ?? "Place", systemImage: session.annotationPlacement?.icon ?? "plus")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(FolikTheme.ink)
    }

    private var placeButton: some View {
        Button("Place center", action: session.placeAnnotationAtCurrentPageCenter)
            .buttonStyle(.borderedProminent)
            .tint(FolikTheme.cobalt)
            .frame(minHeight: 44)
            .accessibilityHint("Places the annotation in the center of the current page")
            .accessibilityIdentifier("reader.annotation.placeCenter")
    }

    private var cancelButton: some View {
        Button("Cancel", role: .cancel, action: session.cancelAnnotationPlacement)
            .frame(minHeight: 44)
            .accessibilityIdentifier("reader.annotation.cancelPlacement")
    }
}

private struct DrawingToolbar: View {
    @ObservedObject var session: DocumentSession
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 4) {
                    HStack {
                        modeLabel
                        Spacer()
                        doneButton
                    }
                    HStack(spacing: 12) {
                        colorMenu
                            .frame(maxWidth: .infinity)
                        widthMenu
                            .frame(maxWidth: .infinity)
                    }
                }
            } else {
                HStack(spacing: 6) {
                    modeLabel
                    Spacer(minLength: 0)
                    colorMenu
                    widthMenu
                    doneButton
                }
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }

    private var modeLabel: some View {
        Text("Draw")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(FolikTheme.ink)
            .padding(.horizontal, 6)
    }

    private var colorMenu: some View {
        Menu {
            ForEach(InkColor.allCases) { color in
                Button {
                    session.inkColor = color
                } label: {
                    Label(color.title, systemImage: session.inkColor == color ? "checkmark.circle.fill" : "circle.fill")
                }
            }
        } label: {
            HStack(spacing: 7) {
                Circle()
                    .fill(session.inkColor.color)
                    .frame(width: 20, height: 20)
                Text("Color")
            }
            .frame(minHeight: 44)
        }
        .accessibilityLabel("Ink color")
        .accessibilityValue(session.inkColor.title)
    }

    private var widthMenu: some View {
        Menu {
            ForEach([CGFloat(2), 3, 5, 8], id: \.self) { width in
                Button {
                    session.inkLineWidth = width
                } label: {
                    Label("\(Int(width)) point", systemImage: session.inkLineWidth == width ? "checkmark" : "line.diagonal")
                }
            }
        } label: {
            Label("\(Int(session.inkLineWidth)) pt", systemImage: "lineweight")
                .frame(minHeight: 44)
        }
        .accessibilityLabel("Ink width")
        .accessibilityValue("\(Int(session.inkLineWidth)) point")
    }

    private var doneButton: some View {
        Button("Done") {
            session.setDrawingEnabled(false)
        }
        .font(.subheadline.weight(.bold))
        .buttonStyle(.borderedProminent)
        .tint(FolikTheme.cobalt)
        .frame(minHeight: 44)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityIdentifier("reader.drawing.done")
    }
}

private struct ReaderToolButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ReaderToolLabel(
                title: title,
                icon: icon,
                foregroundStyle: isSelected ? FolikTheme.cobalt : FolikTheme.mutedInk
            )
            .background(
                isSelected ? FolikTheme.cobalt.opacity(0.12) : Color.clear,
                in: RoundedRectangle(cornerRadius: 11, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("reader.panel.\(title.lowercased())")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }
}

private struct ReaderToolLabel: View {
    let title: String
    let icon: String
    let foregroundStyle: Color
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 6) {
                    iconView
                    Text(title)
                        .font(.headline.weight(.semibold))
                        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .padding(.horizontal, 8)
            } else {
                VStack(spacing: 4) {
                    iconView
                    Text(title)
                        .font(.caption2.weight(.semibold))
                }
            }
        }
        .foregroundStyle(foregroundStyle)
        .frame(maxWidth: .infinity, minHeight: dynamicTypeSize.isAccessibilitySize ? 64 : 52)
        .contentShape(Rectangle())
    }

    private var iconView: some View {
        Image(systemName: icon)
            .font(.system(size: 18, weight: .semibold))
            .frame(width: 24)
            .accessibilityHidden(true)
    }
}

private struct PasswordPrompt: View {
    @ObservedObject var session: DocumentSession
    @State private var password = ""
    @State private var showsIncorrectPassword = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                Image(systemName: "lock.doc.fill")
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(FolikTheme.cobalt)
                    .accessibilityHidden(true)
                Text("This PDF is locked")
                    .font(.title2.weight(.bold))
                Text("Enter its password to read it. Folik does not store the password.")
                    .font(.body)
                    .foregroundStyle(FolikTheme.mutedInk)
                    .multilineTextAlignment(.center)

                SecureField("PDF password", text: $password)
                    .textContentType(.password)
                    .submitLabel(.go)
                    .padding(12)
                    .background(FolikTheme.raisedSurface, in: RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(showsIncorrectPassword ? Color.red : FolikTheme.separator, lineWidth: 1)
                    }
                    .onSubmit(unlock)

                if showsIncorrectPassword {
                    Text("That password didn’t unlock this PDF.")
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button("Unlock", action: unlock)
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.roundedRectangle(radius: 12))
                    .controlSize(.large)
                    .tint(FolikTheme.cobalt)
                    .disabled(password.isEmpty)
                    .frame(maxWidth: .infinity)
            }
            .padding(28)
            .frame(maxWidth: 460, maxHeight: .infinity)
            .navigationTitle("Protected Document")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func unlock() {
        showsIncorrectPassword = !session.unlock(with: password)
        if !showsIncorrectPassword { password = "" }
    }
}

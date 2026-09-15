import Combine
import PDFKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers

@MainActor
final class PageOrganizerDraft: ObservableObject {
    @Published private(set) var document: PDFDocument
    @Published private(set) var revision = UUID()
    @Published private(set) var canUndo = false
    @Published private(set) var hasUnsavedChanges = false
    @Published var errorMessage: String?

    let sourceURL: URL
    private var stateID = UUID()
    private var savedStateID: UUID
    private var undoSnapshots: [(data: Data, stateID: UUID)] = []

    init(sourceURL: URL) {
        self.sourceURL = sourceURL
        document = PDFDocument(url: sourceURL) ?? PDFDocument()
        savedStateID = stateID
    }

    var pageCount: Int { document.pageCount }

    func page(at index: Int) -> PDFPage? {
        document.page(at: index)
    }

    func move(from offsets: IndexSet, to destination: Int) {
        guard offsets.count == 1, let sourceIndex = offsets.first,
              sourceIndex >= 0, sourceIndex < pageCount else { return }
        let insertionIndex = destination > sourceIndex ? destination - 1 : destination
        guard insertionIndex != sourceIndex,
              insertionIndex >= 0, insertionIndex < pageCount else { return }
        performChange {
            guard let page = document.page(at: sourceIndex) else { return }
            document.removePage(at: sourceIndex)
            document.insert(page, at: insertionIndex)
        }
    }

    func rotate(indices: Set<Int>, by degrees: Int) {
        let validIndices = validated(indices)
        guard !validIndices.isEmpty else { return }
        performChange {
            for index in validIndices {
                guard let page = document.page(at: index) else { continue }
                page.rotation = Self.normalizedRotation(page.rotation + degrees)
            }
        }
    }

    func duplicate(indices: Set<Int>) {
        let validIndices = validated(indices)
        guard !validIndices.isEmpty else { return }
        performChange {
            for index in validIndices.sorted(by: >) {
                guard let page = document.page(at: index)?.copy() as? PDFPage else { continue }
                document.insert(page, at: index + 1)
            }
        }
    }

    func insertBlankPage(after index: Int?) {
        let insertionIndex = min(max((index ?? (pageCount - 1)) + 1, 0), pageCount)
        let pageBounds = document.page(at: max(0, min(index ?? 0, pageCount - 1)))?
            .bounds(for: .mediaBox) ?? CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: pageBounds)
        let data = renderer.pdfData { context in context.beginPage() }
        guard let page = PDFDocument(data: data)?.page(at: 0) else {
            errorMessage = PageOrganizerError.couldNotCreatePage.localizedDescription
            return
        }
        performChange {
            document.insert(page, at: insertionIndex)
        }
    }

    func appendPages(from url: URL) {
        let accessingSecurityScopedResource = url.startAccessingSecurityScopedResource()
        defer {
            if accessingSecurityScopedResource { url.stopAccessingSecurityScopedResource() }
        }
        guard let imported = PDFDocument(url: url), imported.pageCount > 0 else {
            errorMessage = PageOrganizerError.couldNotOpenImportedPDF.localizedDescription
            return
        }
        let pages = (0..<imported.pageCount).compactMap {
            imported.page(at: $0)?.copy() as? PDFPage
        }
        guard !pages.isEmpty else {
            errorMessage = PageOrganizerError.couldNotOpenImportedPDF.localizedDescription
            return
        }
        performChange {
            for page in pages { document.insert(page, at: document.pageCount) }
        }
    }

    func delete(indices: Set<Int>) {
        let validIndices = validated(indices)
        guard !validIndices.isEmpty, validIndices.count < pageCount else { return }
        performChange {
            for index in validIndices.sorted(by: >) {
                document.removePage(at: index)
            }
        }
    }

    func undo() {
        guard let snapshot = undoSnapshots.popLast(), let restored = PDFDocument(data: snapshot.data) else { return }
        document = restored
        stateID = snapshot.stateID
        canUndo = !undoSnapshots.isEmpty
        hasUnsavedChanges = stateID != savedStateID
        revision = UUID()
    }

    func saveOrganizedCopy() throws -> URL {
        let destination = uniqueDestination(suffix: "Organized")
        guard document.write(to: destination) else { throw PageOrganizerError.couldNotWrite }
        try repairFormTree(at: destination)
        savedStateID = stateID
        hasUnsavedChanges = false
        return destination
    }

    func extract(indices: Set<Int>) throws -> URL {
        let validIndices = validated(indices).sorted()
        guard !validIndices.isEmpty else { throw PageOrganizerError.noPagesSelected }
        let extracted = PDFDocument()
        for (destinationIndex, sourceIndex) in validIndices.enumerated() {
            guard let page = document.page(at: sourceIndex)?.copy() as? PDFPage else { continue }
            extracted.insert(page, at: destinationIndex)
        }
        guard extracted.pageCount > 0 else { throw PageOrganizerError.noPagesSelected }
        let destination = uniqueDestination(suffix: "Extracted Pages")
        guard extracted.write(to: destination) else { throw PageOrganizerError.couldNotWrite }
        try repairFormTree(at: destination)
        return destination
    }

    private func repairFormTree(at url: URL) throws {
        let serialized = try Data(contentsOf: url)
        let repaired = PDFAcroFormRepair.repair(serialized)
        if repaired != serialized { try repaired.write(to: url) }
    }

    private func performChange(_ change: () -> Void) {
        guard let snapshot = document.dataRepresentation() else {
            errorMessage = PageOrganizerError.couldNotSnapshot.localizedDescription
            return
        }
        undoSnapshots.append((snapshot, stateID))
        change()
        stateID = UUID()
        canUndo = true
        hasUnsavedChanges = true
        revision = UUID()
    }

    private func validated(_ indices: Set<Int>) -> Set<Int> {
        Set(indices.filter { $0 >= 0 && $0 < pageCount })
    }

    private func uniqueDestination(suffix: String) -> URL {
        let directory = sourceURL.deletingLastPathComponent()
        let stem = sourceURL.deletingPathExtension().lastPathComponent
        let baseName = "\(stem) - \(suffix)"
        var destination = directory.appendingPathComponent(baseName).appendingPathExtension("pdf")
        var copyNumber = 2
        while FileManager.default.fileExists(atPath: destination.path) {
            destination = directory
                .appendingPathComponent("\(baseName) \(copyNumber)")
                .appendingPathExtension("pdf")
            copyNumber += 1
        }
        return destination
    }

    private static func normalizedRotation(_ rotation: Int) -> Int {
        let normalized = rotation % 360
        return normalized >= 0 ? normalized : normalized + 360
    }
}

private enum PageOrganizerError: LocalizedError {
    case couldNotSnapshot
    case couldNotWrite
    case couldNotCreatePage
    case couldNotOpenImportedPDF
    case noPagesSelected

    var errorDescription: String? {
        switch self {
        case .couldNotSnapshot: "Folik couldn’t prepare an undo point for this change."
        case .couldNotWrite: "Folik couldn’t save the new PDF copy."
        case .couldNotCreatePage: "Folik couldn’t create a blank page."
        case .couldNotOpenImportedPDF: "Folik couldn’t add pages from that PDF. Try another file."
        case .noPagesSelected: "Select at least one page first."
        }
    }
}

struct PageOrganizerView: View {
    @StateObject private var draft: PageOrganizerDraft
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var selection: Set<Int> = []
    @State private var pendingDeletion = false
    @State private var isSaving = false
    @State private var importerPresented = false
    @State private var moreActionsPresented = false
    @State private var sharedDocument: SharedOrganizerDocument?
    @State private var confirmingDiscard = false

    init(sourceURL: URL) {
        _draft = StateObject(wrappedValue: PageOrganizerDraft(sourceURL: sourceURL))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(0..<draft.pageCount, id: \.self) { index in
                        pageRow(at: index)
                    }
                    .onMove { offsets, destination in
                        draft.move(from: offsets, to: destination)
                        selection.removeAll()
                    }
                } header: {
                    Text(selectionSummary)
                } footer: {
                    Text("Drag the reorder handles, or select pages and use the controls below. The original PDF stays unchanged.")
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Organize")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: requestDismissal) {
                        if dynamicTypeSize.isAccessibilitySize {
                            Image(systemName: "xmark")
                                .frame(width: 44, height: 44)
                        } else {
                            Text("Cancel")
                        }
                    }
                    .accessibilityLabel("Cancel")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        saveCopy()
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else if dynamicTypeSize.isAccessibilitySize {
                            Image(systemName: "square.and.arrow.down")
                                .frame(width: 44, height: 44)
                        } else {
                            Text("Save Copy")
                        }
                    }
                    .disabled(isSaving || draft.pageCount == 0)
                    .accessibilityIdentifier("organizer.saveCopy")
                    .accessibilityLabel("Save organized copy")
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button {
                        moreActionsPresented = true
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("More page actions")
                    .accessibilityIdentifier("organizer.more")
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                organizerControls
            }
            .sheet(item: $sharedDocument) { document in
                OrganizerActivityView(items: [document.url])
                    .ignoresSafeArea()
            }
            .fileImporter(
                isPresented: $importerPresented,
                allowedContentTypes: [.pdf],
                allowsMultipleSelection: false
            ) { result in
                guard case .success(let urls) = result, let url = urls.first else { return }
                draft.appendPages(from: url)
                selection.removeAll()
            }
            .confirmationDialog("More page actions", isPresented: $moreActionsPresented) {
                Button(selection.count == draft.pageCount ? "Deselect All" : "Select All") {
                    selection = selection.count == draft.pageCount ? [] : Set(0..<draft.pageCount)
                }
                Button("Insert Blank Page") {
                    draft.insertBlankPage(after: selection.sorted().last)
                    selection.removeAll()
                }
                Button("Add Pages from PDF") {
                    importerPresented = true
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Select pages, insert a blank page, or add pages from another PDF.")
            }
            .alert("Delete selected pages?", isPresented: $pendingDeletion) {
                Button("Cancel", role: .cancel) {}
                Button("Delete Pages", role: .destructive) {
                    draft.delete(indices: selection)
                    selection.removeAll()
                }
            } message: {
                Text("The pages are removed only from this draft. You can still undo before saving the copy.")
            }
            .alert("Page organizer problem", isPresented: errorIsPresented) {
                Button("OK", role: .cancel) { draft.errorMessage = nil }
            } message: {
                Text(draft.errorMessage ?? "Folik couldn’t complete that page operation.")
            }
            .confirmationDialog("Discard page changes?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
                Button("Discard Changes", role: .destructive) { dismiss() }
                Button("Keep Editing") {}
            } message: {
                Text("Your original PDF is unchanged, but edits in this organizer will be lost.")
            }
            .interactiveDismissDisabled(isSaving || draft.hasUnsavedChanges)
        }
    }

    @ViewBuilder
    private func pageRow(at index: Int) -> some View {
        if let page = draft.page(at: index) {
            Button {
                toggleSelection(index)
            } label: {
                OrganizerPageRow(
                    page: page,
                    index: index,
                    isSelected: selection.contains(index),
                    revision: draft.revision
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("organizer.page.\(index)")
            .accessibilityAddTraits(selection.contains(index) ? .isSelected : [])
            .accessibilityAction(named: "Move earlier") {
                guard index > 0 else { return }
                draft.move(from: IndexSet(integer: index), to: index - 1)
                selection.removeAll()
            }
            .accessibilityAction(named: "Move later") {
                guard index < draft.pageCount - 1 else { return }
                draft.move(from: IndexSet(integer: index), to: index + 2)
                selection.removeAll()
            }
        }
    }

    @ViewBuilder
    private var organizerControls: some View {
        let controls = HStack(spacing: 4) {
            organizerButton("Undo", icon: "arrow.uturn.backward", enabled: draft.canUndo) {
                draft.undo()
                selection.removeAll()
            }
            organizerButton("Left", icon: "rotate.left", enabled: !selection.isEmpty) {
                draft.rotate(indices: selection, by: -90)
            }
            organizerButton("Right", icon: "rotate.right", enabled: !selection.isEmpty) {
                draft.rotate(indices: selection, by: 90)
            }
            organizerButton("Duplicate", icon: "plus.square.on.square", enabled: !selection.isEmpty) {
                draft.duplicate(indices: selection)
                selection.removeAll()
            }
            organizerButton("Extract", icon: "square.and.arrow.up.on.square", enabled: !selection.isEmpty) {
                extractSelection()
            }
            organizerButton(
                "Delete",
                icon: "trash",
                enabled: !selection.isEmpty && selection.count < draft.pageCount,
                role: .destructive
            ) {
                pendingDeletion = true
            }
        }

        Group {
            if dynamicTypeSize.isAccessibilitySize {
                ScrollView(.horizontal, showsIndicators: false) { controls }
            } else {
                controls
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
        .dynamicTypeSize(...DynamicTypeSize.accessibility5)
    }

    private func organizerButton(
        _ title: String,
        icon: String,
        enabled: Bool,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon)
                Text(title).font(.caption2)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .disabled(!enabled)
        .accessibilityIdentifier("organizer.\(title.lowercased())")
    }

    private var selectionSummary: String {
        selection.isEmpty
            ? "\(draft.pageCount) page\(draft.pageCount == 1 ? "" : "s")"
            : "\(selection.count) of \(draft.pageCount) selected"
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { draft.errorMessage != nil },
            set: { if !$0 { draft.errorMessage = nil } }
        )
    }

    private func toggleSelection(_ index: Int) {
        if selection.contains(index) { selection.remove(index) } else { selection.insert(index) }
    }

    private func requestDismissal() {
        if draft.hasUnsavedChanges {
            confirmingDiscard = true
        } else {
            dismiss()
        }
    }

    private func saveCopy() {
        guard !isSaving else { return }
        isSaving = true
        Task {
            await Task.yield()
            do {
                sharedDocument = SharedOrganizerDocument(url: try draft.saveOrganizedCopy())
            } catch {
                draft.errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }

    private func extractSelection() {
        do {
            sharedDocument = SharedOrganizerDocument(url: try draft.extract(indices: selection))
        } catch {
            draft.errorMessage = error.localizedDescription
        }
    }
}

private struct OrganizerPageRow: View {
    let page: PDFPage
    let index: Int
    let isSelected: Bool
    let revision: UUID
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        pageTitle
                        Spacer(minLength: 8)
                        selectionIcon
                    }
                    HStack(alignment: .top, spacing: 12) {
                        thumbnail
                        if page.rotation != 0 {
                            Text("Rotated \(page.rotation)°")
                                .font(.subheadline)
                                .foregroundStyle(FolikTheme.mutedInk)
                        }
                        Spacer(minLength: 0)
                    }
                }
                .padding(.vertical, 8)
            } else {
                HStack(spacing: 14) {
                    thumbnail
                    VStack(alignment: .leading, spacing: 4) {
                        pageTitle
                        Text(page.rotation == 0 ? "Original orientation" : "Rotated \(page.rotation)°")
                            .font(.subheadline)
                            .foregroundStyle(FolikTheme.mutedInk)
                    }
                    Spacer(minLength: 8)
                    selectionIcon
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var thumbnail: some View {
        PDFPageThumbnail(page: page)
            .id("\(revision)-\(index)")
            .frame(width: 62, height: 82)
            .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
    }

    private var pageTitle: some View {
        Text("Page \(index + 1)")
            .font(.body.weight(.semibold))
            .foregroundStyle(FolikTheme.ink)
    }

    private var selectionIcon: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.title3)
            .foregroundStyle(isSelected ? FolikTheme.cobalt : FolikTheme.mutedInk)
            .accessibilityHidden(true)
    }
}

private struct SharedOrganizerDocument: Identifiable {
    let id = UUID()
    let url: URL
}

private struct OrganizerActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

import QuickLookThumbnailing
import SwiftUI

nonisolated enum LibrarySortOrder: String, CaseIterable, Identifiable {
    case newest, oldest, name, size

    var id: Self { self }
    var title: String {
        switch self {
        case .newest: "Newest"
        case .oldest: "Oldest"
        case .name: "Name"
        case .size: "File Size"
        }
    }
}

private struct LibraryDocumentSelection: Identifiable {
    let id = UUID()
    let documents: [LibraryDocument]
}

struct LibraryView: View {
    @EnvironmentObject private var library: DocumentLibrary
    @AppStorage("folik.librarySortOrder") private var sortOrderRawValue = LibrarySortOrder.newest.rawValue
    @State private var organizing: LibraryDocumentSelection?
    @State private var renaming: LibraryDocument?
    @State private var merging: LibraryDocumentSelection?
    @State private var selection: Set<LibraryDocument.ID> = []
    @State private var isSelecting = false
    @State private var confirmBulkDelete = false
    @State private var selectedFolder = "\u{0}"
    @State private var selectedTag = "\u{0}"
    @State private var favoritesOnly = false
    @State private var choosingOCRSource = false
    @State private var pendingOCRSource: LibraryDocument?
    var searchStatus: String? = nil
    var searchHits: [URL: LibrarySearchHit] = [:]
    var isSearching = false
    var hasSearchQuery = false
    var noTextDocuments: [LibraryDocument] = []
    var clearSearch: () -> Void = {}
    private var visibleDocuments: [LibraryDocument] {
        documents.filter {
            let value = library.metadata(for: $0)
            return (selectedFolder == "\u{0}" || value.folder == selectedFolder) && (selectedTag == "\u{0}" || value.tags.contains(selectedTag)) && (!favoritesOnly || value.isFavorite)
        }
        .sorted(by: documentSort)
    }
    private var selectedDocuments: [LibraryDocument] { visibleDocuments.filter { selection.contains($0.id) } }
    private var selectedShouldFavorite: Bool {
        selectedDocuments.contains { !library.metadata(for: $0).isFavorite }
    }
    private var sortOrder: LibrarySortOrder { LibrarySortOrder(rawValue: sortOrderRawValue) ?? .newest }
    let documents: [LibraryDocument]
    let isImporting: Bool
    let importStatus: String?
    let canScan: Bool
    let openImporter: () -> Void
    let openScanner: () -> Void
    let openTools: () -> Void
    let openSettings: () -> Void
    let openDocument: (LibraryDocument) -> Void
    let deleteDocument: (LibraryDocument) -> Void
    let openDocumentTool: (LibraryPDFTool, LibraryDocument) -> Void

    var body: some View {
        Group {
            if library.documents.isEmpty {
                emptyLibrary
            } else {
                documentList
            }
        }
        .onChange(of: library.folders) { _, folders in
            if selectedFolder != "\u{0}" && selectedFolder != "" && !folders.contains(selectedFolder) { selectedFolder = "\u{0}" }
        }
        .onChange(of: library.tags) { _, tags in
            if selectedTag != "\u{0}" && !tags.contains(selectedTag) { selectedTag = "\u{0}" }
        }
        .onChange(of: selectedFolder) { _, _ in selection.removeAll() }
        .onChange(of: selectedTag) { _, _ in selection.removeAll() }
        .onChange(of: favoritesOnly) { _, _ in selection.removeAll() }
        .onChange(of: visibleDocuments.map(\.id)) { _, ids in
            selection.formIntersection(ids)
        }
        .sheet(isPresented: $choosingOCRSource, onDismiss: {
            if let document = pendingOCRSource {
                pendingOCRSource = nil
                openDocumentTool(.searchable, document)
            }
        }) {
            NavigationStack {
                List(matchingOCRDocuments) { document in
                    Button {
                        pendingOCRSource = document
                        choosingOCRSource = false
                    } label: {
                        Label(document.displayName, systemImage: "doc")
                            .frame(minHeight: 44)
                    }
                }
                .navigationTitle("Choose a PDF")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { choosingOCRSource = false } } }
            }
        }
        .sheet(item: $organizing) { DocumentOrganizationView(documents: $0.documents) }
        .sheet(item: $renaming) { RenameDocumentView(document: $0) }
        .sheet(item: $merging) { selection in
            BatchConversionView(libraryDocuments: selection.documents) {
                self.selection.removeAll()
                isSelecting = false
            }
        }
        .confirmationDialog(
            "Remove \(selectedDocuments.count) document\(selectedDocuments.count == 1 ? "" : "s") from Folik?",
            isPresented: $confirmBulkDelete,
            titleVisibility: .visible
        ) {
            Button("Remove from Folik", role: .destructive) {
                library.delete(selectedDocuments)
                selection.removeAll()
                isSelecting = false
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the local copies. This action cannot be undone.")
        }
        .background(FolikTheme.surface)
        .navigationTitle("Library")
        .navigationBarTitleDisplayMode(.large)
        .safeAreaInset(edge: .bottom) {
            if isImporting, let importStatus {
                HStack(spacing: 12) {
                    ProgressView()
                    Text(importStatus)
                        .font(.subheadline.weight(.semibold))
                }
                .padding(.horizontal, 18)
                .frame(minHeight: 50)
                .background(.regularMaterial, in: Capsule())
                .shadow(color: .black.opacity(0.1), radius: 14, y: 6)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("library.importStatus")
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if !library.documents.isEmpty {
                    Button(isSelecting ? "Done" : "Select") {
                        isSelecting.toggle()
                        if !isSelecting { selection.removeAll() }
                    }
                    .accessibilityIdentifier("library.select")
                }
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: openSettings) {
                    Label("Settings", systemImage: "gearshape")
                }
                .accessibilityIdentifier("library.settings")

                Button(action: openTools) {
                    if isImporting {
                        ProgressView()
                    } else {
                        Label("Add Document", systemImage: "plus")
                    }
                }
                .disabled(isImporting)
                .accessibilityIdentifier("library.addDocument")
                .accessibilityHint("Scan paper, choose PDFs, or convert images and text to PDF")
            }
        }
    }

    private var matchingOCRDocuments: [LibraryDocument] {
        noTextDocuments.filter { document in
            let metadata = library.metadata(for: document)
            return (selectedFolder == "\u{0}" || metadata.folder == selectedFolder)
                && (selectedTag == "\u{0}" || metadata.tags.contains(selectedTag))
                && (!favoritesOnly || metadata.isFavorite)
        }
    }

    private var hasFilters: Bool {
        favoritesOnly || selectedFolder != "\u{0}" || selectedTag != "\u{0}"
    }

    private var filterSummary: String {
        var labels: [String] = []
        if favoritesOnly { labels.append("Favorites") }
        if selectedFolder != "\u{0}" { labels.append(selectedFolder.isEmpty ? "Unfiled" : selectedFolder) }
        if selectedTag != "\u{0}" { labels.append("#" + selectedTag) }
        return labels.joined(separator: " · ")
    }

    private func clearFilters() {
        favoritesOnly = false
        selectedFolder = "\u{0}"
        selectedTag = "\u{0}"
    }

    private var documentList: some View {
        let visible = visibleDocuments
        let favorites = visible.filter { library.metadata(for: $0).isFavorite }
        let otherDocuments = visible.filter { !library.metadata(for: $0).isFavorite }
        return List {
            Section {
                libraryControls
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            if !hasFilters && !hasSearchQuery && !isSelecting, let resume = library.readingResume {
                Section {
                    HStack(alignment: .top, spacing: 8) {
                        Button { openDocument(resume.document) } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Label("Continue Reading", systemImage: "book")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(FolikTheme.cobalt)
                                Text(resume.document.displayName)
                                    .font(.headline)
                                    .foregroundStyle(FolikTheme.ink)
                                    .lineLimit(2)
                                Text("Page \(resume.pageIndex + 1) of \(resume.document.pageCount)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("library.resume")
                        .accessibilityLabel("Continue reading \(resume.document.displayName), page \(resume.pageIndex + 1) of \(resume.document.pageCount)")
                        Button(action: library.dismissReadingResume) {
                            Image(systemName: "xmark")
                                .font(.body)
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Dismiss Continue Reading")
                        .accessibilityIdentifier("library.dismissResume")
                    }
                    .padding(.vertical, 4)
                }
            }

            if !favorites.isEmpty {
                Section("Favorites (\(favorites.count))") {
                    documentRows(favorites)
                }
            }
            if !otherDocuments.isEmpty {
                Section(favorites.isEmpty ? "Documents (\(otherDocuments.count))" : "Other Documents (\(otherDocuments.count))") {
                    documentRows(otherDocuments)
                }
            }
            if visible.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(isSearching ? "Searching your library…" : "No matching documents")
                            .font(.headline)
                        Text(hasFilters ? "Try another search or clear your filters to see more documents." : "Try a different filename, folder, tag, or phrase from a searchable PDF.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if hasSearchQuery && !isSearching {
                            Button("Clear search", action: clearSearch)
                                .frame(minHeight: 44)
                                .accessibilityIdentifier("library.clearSearch")
                        }
                        if hasFilters {
                            Button("Clear filters", action: clearFilters)
                                .frame(minHeight: 44)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            if hasSearchQuery && !isSearching && !matchingOCRDocuments.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Some PDFs have no searchable text", systemImage: "text.viewfinder")
                            .font(.subheadline.weight(.semibold))
                        Text("\(matchingOCRDocuments.count) PDF\(matchingOCRDocuments.count == 1 ? "" : "s") in this view can only be found by name, folder, or tag. Make a searchable copy to find words on scanned pages.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button("Make PDF Searchable") {
                            if matchingOCRDocuments.count == 1, let document = matchingOCRDocuments.first {
                                openDocumentTool(.searchable, document)
                            } else { choosingOCRSource = true }
                        }
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("library.searchOCR")
                    }
                    .padding(.vertical, 4)
                }
            }
            Section {
                Label("On-device & private", systemImage: "lock.shield")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("On-device and private. Documents are processed locally and never uploaded by Folik.")
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(16)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if isSelecting { bulkActionBar }
        }
    }

    private var libraryControls: some View {
        VStack(alignment: .leading, spacing: 4) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) {
                    sortMenu
                    Spacer(minLength: 8)
                    filterMenu
                }
                VStack(alignment: .leading, spacing: 4) {
                    sortMenu
                    filterMenu
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            if hasFilters {
                HStack(alignment: .center, spacing: 8) {
                    Text(filterSummary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button(action: clearFilters) {
                        Image(systemName: "xmark.circle.fill")
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Clear filters")
                    .accessibilityIdentifier("library.clearFilters")
                }
            }
            if let searchStatus {
                Text(searchStatus).font(.footnote).foregroundStyle(.secondary)
            }
            if isSearching { ProgressView("Searching document text…").font(.footnote) }
        }
        .buttonStyle(.borderless)
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort documents", selection: $sortOrderRawValue) {
                ForEach(LibrarySortOrder.allCases) { order in
                    Text(order.title).tag(order.rawValue)
                }
            }
        } label: {
            Label(sortOrder.title, systemImage: "arrow.up.arrow.down")
                .font(.subheadline.weight(.semibold))
                .fixedSize()
                .frame(minHeight: 44)
        }
        .labelStyle(.titleAndIcon)
        .accessibilityLabel("Sort: \(sortOrder.title)")
        .accessibilityIdentifier("library.sort")
    }

    private var filterMenu: some View {
        Menu {
            Toggle("Favorites only", isOn: $favoritesOnly)
            Picker("Folder", selection: $selectedFolder) {
                Text("All folders").tag("\u{0}")
                Text("Unfiled").tag("")
                ForEach(library.folders, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.menu)
            Picker("Tag", selection: $selectedTag) {
                Text("All tags").tag("\u{0}")
                ForEach(library.tags, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.menu)
            if hasFilters { Button("Clear filters", action: clearFilters) }
        } label: {
            Label(hasFilters ? "Filtered" : "Filter", systemImage: hasFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                .font(.subheadline.weight(.semibold))
                .fixedSize()
                .frame(minHeight: 44)
        }
        .labelStyle(.titleAndIcon)
        .accessibilityLabel("Filter documents")
        .accessibilityValue(hasFilters ? filterSummary : "All documents")
        .accessibilityIdentifier("library.filter")
    }

    private func documentRows(_ items: [LibraryDocument]) -> some View {
        ForEach(items) { document in
            DocumentRow(
                document: document,
                metadata: library.metadata(for: document),
                hit: searchHits[document.url],
                isSelecting: isSelecting,
                isSelected: selection.contains(document.id),
                toolsDisabled: isImporting,
                toggleSelection: {
                    if selection.contains(document.id) { selection.remove(document.id) }
                    else { selection.insert(document.id) }
                },
                organize: { organizing = LibraryDocumentSelection(documents: [document]) },
                rename: { renaming = document },
                toggleFavorite: { updateFavorites(!library.metadata(for: document).isFavorite, for: [document]) },
                open: { openDocument(document) },
                delete: { deleteDocument(document) },
                openTool: { openDocumentTool($0, document) }
            )
        }
    }

    private var emptyLibrary: some View {
        ScrollView {
            VStack(spacing: 0) {
                Spacer(minLength: 68)
                FolikWordmark()
                    .padding(.bottom, 36)

                ZStack {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(FolikTheme.raisedSurface)
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(FolikTheme.separator, lineWidth: 0.5)
                    Image(systemName: "doc.richtext")
                        .font(.system(size: 52, weight: .light))
                        .foregroundStyle(FolikTheme.cobalt)
                        .accessibilityHidden(true)
                }
                .frame(width: 132, height: 132)
                .padding(.bottom, 28)

                Text("Your documents, without the tollbooth.")
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)

                Text("Scan paper, open a PDF, or use the Add menu to convert images and text. Read, search, organize, and mark up your documents on this device.")
                    .font(.body)
                    .foregroundStyle(FolikTheme.mutedInk)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.top, 10)

                Button(action: openScanner) {
                    HStack(spacing: 10) {
                        if isImporting {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "doc.viewfinder")
                                .accessibilityHidden(true)
                        }
                        Text(isImporting ? (importStatus ?? "Working…") : "Scan a Document")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle(radius: 14))
                .tint(FolikTheme.cobalt)
                .disabled(isImporting || !canScan)
                .padding(.horizontal, 32)
                .padding(.top, 30)
                .accessibilityHint(
                    canScan
                        ? "Uses the camera to find page edges and create a PDF"
                        : "Scanning requires an iPhone or iPad with a camera"
                )

                Button(action: openImporter) {
                    Label("Choose PDFs from Files", systemImage: "folder")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.roundedRectangle(radius: 14))
                .disabled(isImporting)
                .padding(.horizontal, 32)
                .padding(.top, 10)

                Label("No account · No ads · No uploads", systemImage: "lock.shield")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(FolikTheme.mutedInk)
                    .padding(.top, 20)
                    .padding(.bottom, 44)
            }
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
    }

    private var bulkActionBar: some View {
        HStack(spacing: 6) {
            Button(!visibleDocuments.isEmpty && selection.count == visibleDocuments.count ? "Deselect All" : "Select All") {
                selection = selection.count == visibleDocuments.count ? [] : Set(visibleDocuments.map(\.id))
            }
            .frame(minHeight: 44)
            .disabled(visibleDocuments.isEmpty)

            Spacer(minLength: 0)

            Menu {
                Button {
                    merging = LibraryDocumentSelection(documents: selectedDocuments)
                } label: {
                    Label("Merge PDFs", systemImage: "doc.on.doc")
                }
                .disabled(selection.count < 2 || selection.count > 20 || isImporting)
                .accessibilityHint("Select between 2 and 20 PDFs to merge")
                Button {
                    organizing = LibraryDocumentSelection(documents: selectedDocuments)
                } label: {
                    Label("Organize", systemImage: "folder")
                }
                Button {
                    updateFavorites(selectedShouldFavorite, for: selectedDocuments)
                } label: {
                    Label(
                        selectedShouldFavorite ? "Favorite" : "Remove Favorite",
                        systemImage: selectedShouldFavorite ? "star" : "star.slash"
                    )
                }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
                    .frame(minWidth: 44, minHeight: 44)
            }
            .disabled(selection.isEmpty)

            ShareLink(items: selectedDocuments.map(\.url)) {
                Image(systemName: "square.and.arrow.up").frame(width: 44, height: 44)
            }
            .accessibilityLabel("Share selected documents")
            .disabled(selection.isEmpty)

            Button(role: .destructive) { confirmBulkDelete = true } label: {
                Image(systemName: "trash").frame(width: 44, height: 44)
            }
            .accessibilityLabel("Remove selected documents")
            .disabled(selection.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private func documentSort(_ lhs: LibraryDocument, _ rhs: LibraryDocument) -> Bool {
        let leftFavorite = library.metadata(for: lhs).isFavorite
        let rightFavorite = library.metadata(for: rhs).isFavorite
        if leftFavorite != rightFavorite { return leftFavorite }
        switch sortOrder {
        case .newest: return lhs.modifiedAt > rhs.modifiedAt
        case .oldest: return lhs.modifiedAt < rhs.modifiedAt
        case .name: return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
        case .size:
            return lhs.fileSize == rhs.fileSize
                ? lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
                : lhs.fileSize > rhs.fileSize
        }
    }

    private func updateFavorites(_ isFavorite: Bool, for documents: [LibraryDocument]) {
        do {
            try library.setFavorite(isFavorite, for: documents)
        } catch {
            library.errorMessage = "Folik couldn’t update those favorites. \(error.localizedDescription)"
        }
    }
}

private struct DocumentRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let document: LibraryDocument
    let metadata: LibraryMetadata
    let hit: LibrarySearchHit?
    let isSelecting: Bool
    let isSelected: Bool
    let toolsDisabled: Bool
    let toggleSelection: () -> Void
    let organize: () -> Void
    let rename: () -> Void
    let toggleFavorite: () -> Void
    let open: () -> Void
    let delete: () -> Void
    let openTool: (LibraryPDFTool) -> Void

    private var accessibilityDescription: String {
        var details = [document.displayName, document.pageDescription, document.fileSizeDescription]
        if metadata.isFavorite { details.append("Favorite") }
        if !metadata.folder.isEmpty { details.append("Folder: " + metadata.folder) }
        if !metadata.tags.isEmpty { details.append("Tags: " + metadata.tags.joined(separator: ", ")) }
        if let hit { details.append("Page \(hit.page): \(hit.excerpt)") }
        return details.joined(separator: ", ")
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button(action: isSelecting ? toggleSelection : open) {
                HStack(spacing: 12) {
                    if isSelecting {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(isSelected ? FolikTheme.cobalt : FolikTheme.mutedInk)
                            .frame(width: 30, height: 44)
                            .accessibilityHidden(true)
                    }
                    documentContent
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("library.document.\(document.url.lastPathComponent)")
            .accessibilityLabel(accessibilityDescription)
            .accessibilityValue(isSelecting ? (isSelected ? "Selected" : "Not selected") : "")
            .accessibilityHint(isSelecting ? "Toggles selection" : "Opens the PDF")
            .frame(maxWidth: .infinity, alignment: .leading)

            if !isSelecting {
                Menu {
                    Button(action: toggleFavorite) {
                        Label(metadata.isFavorite ? "Remove Favorite" : "Favorite", systemImage: metadata.isFavorite ? "star.slash" : "star")
                    }
                    Button("Rename", action: rename)
                    Button("Organize", action: organize)
                    Menu {
                        ForEach(LibraryPDFTool.allCases) { tool in
                            Button { openTool(tool) } label: {
                                Label(tool.title, systemImage: tool.icon)
                            }
                        }
                    } label: {
                        Label("Tools", systemImage: "wrench.and.screwdriver")
                    }
                    .disabled(toolsDisabled)
                    ShareLink(item: document.url) {
                        Label("Share a copy", systemImage: "square.and.arrow.up")
                    }
                    Button(role: .destructive, action: delete) {
                        Label("Remove from Folik", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.body.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Document actions")
                .accessibilityHint(document.displayName)
            }
        }
        .padding(.vertical, 8)
    }

    private var documentContent: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 14))
        return layout {
            PDFCoverThumbnail(url: document.url)
                .frame(width: 60, height: 80)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(document.displayName)
                        .font(.headline)
                        .foregroundStyle(FolikTheme.ink)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)
                    if metadata.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(FolikTheme.cobalt)
                            .accessibilityHidden(true)
                    }
                }
                Text("\(document.pageDescription) · \(document.fileSizeDescription)")
                    .font(.caption)
                    .foregroundStyle(FolikTheme.mutedInk)
                if !metadata.folder.isEmpty {
                    Label(metadata.folder, systemImage: "folder")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                }
                if !metadata.tags.isEmpty {
                    Text(metadata.tags.map { "#" + $0 }.joined(separator: "  "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                }
                if let hit {
                    Text("Page \(hit.page): \(hit.excerpt)")
                        .font(.caption)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 3)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct PDFCoverThumbnail: View {
    let url: URL
    @State private var image: UIImage?
    @State private var request: QLThumbnailGenerator.Request?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(FolikTheme.recessedSurface)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "doc.fill")
                    .font(.title2)
                    .foregroundStyle(FolikTheme.cobalt)
                    .accessibilityHidden(true)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(FolikTheme.separator, lineWidth: 0.5)
        }
        .onAppear(perform: loadThumbnail)
        .onDisappear {
            if let request { QLThumbnailGenerator.shared.cancel(request) }
        }
        .accessibilityHidden(true)
    }

    private func loadThumbnail() {
        guard image == nil, request == nil else { return }
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: 104, height: 136),
            scale: UIScreen.main.scale,
            representationTypes: .thumbnail
        )
        self.request = request
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { thumbnail, _ in
            guard let thumbnail else { return }
            Task { @MainActor in image = thumbnail.uiImage }
        }
    }
}

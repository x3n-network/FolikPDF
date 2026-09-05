import QuickLookThumbnailing
import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var library: DocumentLibrary
    @State private var organizing: LibraryDocument?
    @State private var selectedFolder = "\u{0}"
    @State private var selectedTag = "\u{0}"
    var searchStatus: String? = nil
    var searchHits: [URL: LibrarySearchHit] = [:]
    var isSearching = false
    private var visibleDocuments: [LibraryDocument] {
        documents.filter {
            let value = library.metadata(for: $0)
            return (selectedFolder == "\u{0}" || value.folder == selectedFolder) && (selectedTag == "\u{0}" || value.tags.contains(selectedTag))
        }
    }
    let documents: [LibraryDocument]
    let isImporting: Bool
    let importStatus: String?
    let canScan: Bool
    let openImporter: () -> Void
    let openScanner: () -> Void
    let openImageConverter: () -> Void
    let openTextConverter: () -> Void
    let openOfficeConverter: () -> Void
    var openSearchablePDF: () -> Void = {}
    var openCompression: () -> Void = {}
    let openSettings: () -> Void
    let openDocument: (LibraryDocument) -> Void
    let deleteDocument: (LibraryDocument) -> Void

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
        .sheet(item: $organizing) { DocumentOrganizationView(document: $0) }
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
                if !documents.isEmpty {
                    FolikWordmark(compact: true)
                }
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: openSettings) {
                    Label("Settings", systemImage: "gearshape")
                }
                .accessibilityIdentifier("library.settings")

                Menu {
                    Button(action: openScanner) {
                        Label("Scan Document", systemImage: "doc.viewfinder")
                    }
                    .disabled(!canScan || isImporting)
                    Button(action: openImporter) {
                        Label("Choose PDFs", systemImage: "folder")
                    }
                    .disabled(isImporting)
                    Button("Make PDF Searchable", action: openSearchablePDF)
                    Button("Compress PDF", action: openCompression)
                    Divider()
                    Button(action: openImageConverter) {
                        Label("Images to PDF", systemImage: "photo.on.rectangle")
                    }
                    Button(action: openOfficeConverter) {
                        Label("Documents to PDF", systemImage: "doc.richtext")
                    }
                    Button(action: openTextConverter) {
                        Label("Text/RTF to PDF", systemImage: "doc.text")
                    }
                } label: {
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

    private var documentList: some View {
        List {
            Section {
                PrivacyBanner()
                    .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 16, trailing: 16))
                    .listRowSeparator(.hidden)
            }

            Section("Find and organize") {
                Picker("Folder", selection: $selectedFolder) {
                    Text("All folders").tag("\u{0}"); Text("Unfiled").tag("")
                    ForEach(library.folders, id: \.self) { Text($0).tag($0) }
                }
                Picker("Tag", selection: $selectedTag) {
                    Text("All tags").tag("\u{0}")
                    ForEach(library.tags, id: \.self) { Text($0).tag($0) }
                }
                if let searchStatus { Text(searchStatus).font(.footnote).foregroundStyle(.secondary) }
                if isSearching { ProgressView("Searching document text…") }
            }
            Section("Documents (\(visibleDocuments.count))") {
                if visibleDocuments.isEmpty { Text("No matching documents").foregroundStyle(.secondary) }
                ForEach(visibleDocuments) { document in
                    DocumentRow(
                        document: document,
                        metadata: library.metadata(for: document),
                        hit: searchHits[document.url],
                        organize: { organizing = document },
                        open: { openDocument(document) },
                        delete: { deleteDocument(document) }
                    )
                }
            }
        }
        .listStyle(.insetGrouped)
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
}

private struct PrivacyBanner: View {
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "lock.shield.fill")
                .font(.title3)
                .foregroundStyle(FolikTheme.cobalt)
                .frame(width: 32, height: 32)
                .background(FolikTheme.cobalt.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Private by design")
                    .font(.headline)
                Text("Documents are processed locally and never uploaded by Folik.")
                    .font(.subheadline)
                    .foregroundStyle(FolikTheme.mutedInk)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(FolikTheme.raisedSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct DocumentRow: View {
    let document: LibraryDocument
    let metadata: LibraryMetadata
    let hit: LibrarySearchHit?
    let organize: () -> Void
    let open: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button(action: open) {
                HStack(spacing: 14) {
                    PDFCoverThumbnail(url: document.url)
                        .frame(width: 52, height: 68)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(document.displayName)
                            .font(.headline)
                            .foregroundStyle(FolikTheme.ink)
                            .lineLimit(2)
                        if !metadata.folder.isEmpty { Label(metadata.folder, systemImage: "folder").font(.caption).foregroundStyle(.secondary) }
                        if !metadata.tags.isEmpty { Text(metadata.tags.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary) }
                        if let hit { Text("Page \(hit.page): \(hit.excerpt)").font(.caption).lineLimit(3).foregroundStyle(.secondary) }
                        HStack(spacing: 6) {
                            Text(document.pageDescription)
                            Text("·")
                            Text(document.fileSizeDescription)
                        }
                        .font(.subheadline)
                        .foregroundStyle(FolikTheme.mutedInk)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("library.document.\(document.url.lastPathComponent)")
            .accessibilityLabel("\(document.displayName), \(document.pageDescription), \(document.fileSizeDescription)")
            .accessibilityHint("Opens the PDF")

            Menu {
                Button("Organize", action: organize)
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
        }
        .padding(.vertical, 5)
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

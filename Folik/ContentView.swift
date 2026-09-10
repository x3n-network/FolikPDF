import AVFoundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

private struct LibraryPDFToolRequest: Identifiable {
    let id = UUID()
    let tool: LibraryPDFTool
    var sourceURL: URL? = nil
}

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingDeleted = false
    @EnvironmentObject private var library: DocumentLibrary
    @State private var path: [LibraryDocument] = []
    @State private var isImporterPresented = false
    @State private var isScannerPresented = false
    @State private var cameraPermissionAlertPresented = false
    @State private var isSettingsPresented = false
    @State private var toolsPresented = false
    @State private var pendingTool: LibraryTool?
    @State private var conversionMode: PDFConversionView.Mode?
    @State private var convertedDocument: LibraryDocument?
    @State private var officeConverterPresented = false
    @State private var batchPresented = false
    @State private var pdfToolRequest: LibraryPDFToolRequest?
    @State private var searchText = ""
    @State private var searchResult = LibrarySearchResult()
    @State private var searchingText = false
    @State private var searchIndex = LibrarySearchIndex()
    @State private var handledDebugLaunch = false
    @State private var isDropTargeted = false
    @Environment(\.openWindow) private var openWindow
    @Environment(\.supportsMultipleWindows) private var supportsMultipleWindows

    var body: some View {
        NavigationStack(path: $path) {
            libraryRoot
                .navigationDestination(for: LibraryDocument.self) { item in
                    ReaderView(item: item)
                }
        }
        .pdfDropDestination(
            isEnabled: !library.isImporting,
            isTargeted: $isDropTargeted,
            action: importDroppedPDFs
        )
        .overlay {
            if isDropTargeted {
                PDFDropOverlay()
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .task(id: LibrarySearchRequest(query: searchText, documents: library.documents)) {
            searchResult = LibrarySearchResult(); searchingText = false
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { return }
            let documents = library.documents
            searchingText = true
            do {
                try await Task.sleep(for: .milliseconds(300))
                let result = try await searchIndex.search(query, documents: documents)
                try Task.checkCancellation(); searchResult = result; searchingText = false
            } catch { if !Task.isCancelled { searchingText = false } }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
            Task { await searchIndex.releaseMemory() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { Task { await searchIndex.releaseMemory() } }
        }
        .tint(FolikTheme.cobalt)
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: true
        ) { result in
            guard case .success(let urls) = result else { return }
            Task {
                let imported = await library.importDocuments(at: urls)
                if imported.count == 1, let document = imported.first {
                    path.append(document)
                }
            }
        }
        .fullScreenCover(isPresented: $isScannerPresented) {
            DocumentScannerView(
                complete: { pages in
                    isScannerPresented = false
                    Task {
                        if let document = await library.importScannedPages(pages) {
                            path.append(document)
                        }
                    }
                },
                cancel: { isScannerPresented = false },
                fail: { error in
                    isScannerPresented = false
                    library.errorMessage = "Folik couldn’t finish scanning. \(error.localizedDescription)"
                }
            )
            .ignoresSafeArea()
        }
        .sheet(isPresented: $isSettingsPresented) {
            SettingsView()
        }
        .sheet(isPresented: $toolsPresented, onDismiss: launchPendingTool) {
            LibraryToolsView(canScan: DocumentScannerView.isSupported) { tool in
                pendingTool = tool
                toolsPresented = false
            }
        }
        .sheet(item: $conversionMode, onDismiss: {
            if let document = convertedDocument {
                convertedDocument = nil
                path.append(document)
            }
        }) { mode in
            PDFConversionView(mode: mode) { document in
                convertedDocument = document
                conversionMode = nil
            }
        }
        .sheet(isPresented: $officeConverterPresented, onDismiss: {
            if let document = convertedDocument {
                convertedDocument = nil
                path.append(document)
            }
        }) {
            OfficeConversionView { document in
                convertedDocument = document
                officeConverterPresented = false
            }
        }
        .sheet(item: $pdfToolRequest, onDismiss: {
            if let document = convertedDocument { convertedDocument = nil; path.append(document) }
        }) { request in
            if request.tool == .fillable {
                FillablePDFView(initialURL: request.sourceURL) { document in
                    convertedDocument = document
                    pdfToolRequest = nil
                }
            } else if request.tool == .redact {
                RedactionView(initialURL: request.sourceURL) { document in
                    convertedDocument = document
                    pdfToolRequest = nil
                }
            } else if request.tool == .sanitize {
                PrivacyReportView(initialURL: request.sourceURL) { document in
                    convertedDocument = document
                    pdfToolRequest = nil
                }
            } else if request.tool == .protect {
                ProtectPDFView(initialURL: request.sourceURL) { document in
                    convertedDocument = document
                    pdfToolRequest = nil
                }
            } else if request.tool == .compare {
                ComparePDFView(initialURL: request.sourceURL)
            } else {
                PDFToolView(compress: request.tool == .compress, initialURL: request.sourceURL) { document in
                    convertedDocument = document
                    pdfToolRequest = nil
                }
            }
        }
        .sheet(isPresented: $batchPresented) { BatchConversionView() }
        .onOpenURL { url in
            Task {
                if let document = await library.importDocuments(at: [url]).first {
                    path.append(document)
                }
            }
        }
        .onChange(of: path.count) { _, count in
            if count == 0 { Task { await library.refreshInBackground() } }
        }
        .onAppear {
            #if DEBUG
            guard !handledDebugLaunch else { return }
            handledDebugLaunch = true
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("--ui-test-fixture") {
                library.prepareUITestFixture()
                if arguments.contains("--ui-test-empty-library") { library.delete(library.documents) }
                if arguments.contains("--ui-test-shared-inbox") {
                    Task { await library.importSharedInbox() }
                }
                if arguments.contains("--ui-test-dropped-pdf"),
                   let source = library.documents.first?.url,
                   let dropped = try? PDFTransferItem.temporaryCopy(of: source) {
                    importDroppedPDFs([dropped])
                }
            }
            if arguments.contains("--ui-test-make-fillable"), let source = library.documents.first {
                pdfToolRequest = LibraryPDFToolRequest(tool: .fillable, sourceURL: source.url)
            }
            if arguments.contains("--open-settings") {
                isSettingsPresented = true
            }
            if arguments.contains("--ui-test-drop-target") {
                isDropTargeted = true
            }
            if arguments.contains("--ui-test-scan-fixture") {
                Task {
                    if let document = await library.prepareUITestScanFixture() {
                        path.append(document)
                    }
                }
                return
            }
            if let requestedFilename = arguments.value(after: "--open-document-named"),
               let requestedDocument = library.documents.first(where: {
                   $0.url.lastPathComponent == requestedFilename
               }) {
                path.append(requestedDocument)
            } else if arguments.contains("--open-first-document"),
                      let firstDocument = library.documents.first {
                path.append(firstDocument)
            }
            #endif
        }
        .sheet(isPresented: $showingDeleted) {
            NavigationStack {
                RecentlyDeletedView()
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingDeleted = false } } }
            }
        }
        .alert("Couldn’t complete that action", isPresented: errorIsPresented) {
            Button("OK", role: .cancel) { library.errorMessage = nil }
        } message: {
            Text(library.errorMessage ?? "The document could not be opened.")
        }
        .alert("Camera Access Needed", isPresented: $cameraPermissionAlertPresented) {
            Button("Not Now", role: .cancel) {}
            Button("Open Settings") {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            }
        } message: {
            Text("Allow camera access in Settings to scan paper documents. You can still choose PDFs from Files.")
        }
    }

    @ViewBuilder
    private var libraryRoot: some View {
        let libraryView = LibraryView(
            searchStatus: searchResult.skipped > 0 ? "Skipped \(searchResult.skipped) protected, unreadable, or oversized documents." : nil,
            searchHits: searchResult.hits,
            searchMatchCounts: searchResult.matchingPageCounts,
            searchQuery: searchText,
            isSearching: searchingText,
            hasSearchQuery: !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            noTextDocuments: library.documents.filter { searchResult.noSearchableText.contains($0.url) },
            clearSearch: { searchText = "" },
            documents: filteredDocuments,
            isImporting: library.isImporting,
            importStatus: library.importStatus,
            canScan: DocumentScannerView.isSupported,
            openImporter: { isImporterPresented = true },
            openScanner: beginScanning,
            openTools: { toolsPresented = true },
            openSettings: { isSettingsPresented = true },
            openRecentlyDeleted: { showingDeleted = true },
            openDocument: { path.append($0) },
            openDocumentWindow: supportsMultipleWindows ? { document in
                openWindow(id: "pdf", value: document.id.uuidString)
            } : nil,
            deleteDocument: library.delete,
            openDocumentTool: { tool, document in
                pdfToolRequest = LibraryPDFToolRequest(tool: tool, sourceURL: document.url)
            }
        )

        if library.documents.isEmpty {
            libraryView
        } else {
            libraryView.searchable(text: $searchText, prompt: "Search your library")
        }
    }

    private var filteredDocuments: [LibraryDocument] {
        guard !searchText.isEmpty else { return library.documents }
        return library.documents.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText.trimmingCharacters(in: .whitespacesAndNewlines)) || library.metadata(for: $0).matches(searchText.trimmingCharacters(in: .whitespacesAndNewlines)) || !(searchResult.hits[$0.url]?.isEmpty ?? true)
        }
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { library.errorMessage != nil },
            set: { if !$0 { library.errorMessage = nil } }
        )
    }

    private func launchPendingTool() {
        guard let tool = pendingTool else { return }
        pendingTool = nil
        switch tool {
        case .scan: beginScanning()
        case .importPDF: isImporterPresented = true
        case .images: conversionMode = .images
        case .documents: officeConverterPresented = true
        case .text: conversionMode = .text
        case .searchable: pdfToolRequest = LibraryPDFToolRequest(tool: .searchable)
        case .fillable: pdfToolRequest = LibraryPDFToolRequest(tool: .fillable)
        case .compress: pdfToolRequest = LibraryPDFToolRequest(tool: .compress)
        case .batch: batchPresented = true
        case .redact: pdfToolRequest = LibraryPDFToolRequest(tool: .redact)
        case .sanitize: pdfToolRequest = LibraryPDFToolRequest(tool: .sanitize)
        case .protect: pdfToolRequest = LibraryPDFToolRequest(tool: .protect)
        case .compare: pdfToolRequest = LibraryPDFToolRequest(tool: .compare)
        }
    }

    private func beginScanning() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            isScannerPresented = true
        case .notDetermined:
            Task {
                if await AVCaptureDevice.requestAccess(for: .video) {
                    isScannerPresented = true
                } else {
                    cameraPermissionAlertPresented = true
                }
            }
        case .denied, .restricted:
            cameraPermissionAlertPresented = true
        @unknown default:
            cameraPermissionAlertPresented = true
        }
    }

    private func importDroppedPDFs(_ items: [PDFTransferItem]) {
        guard !items.isEmpty else { return }
        Task {
            defer { PDFTransferItem.removeTemporaryCopies(items) }
            let urls = items.map(\.url)
            do {
                let validation = Task.detached(priority: .userInitiated) {
                    try SharedPDFInbox.validate(urls)
                }
                try await withTaskCancellationHandler(
                    operation: { try await validation.value },
                    onCancel: { validation.cancel() }
                )
                let imported = await library.importDocuments(at: urls)
                if imported.count == 1, let document = imported.first {
                    path.append(document)
                } else if imported.isEmpty, library.errorMessage == nil {
                    library.errorMessage = "Folik is finishing another import. Drop those PDFs again in a moment."
                }
            } catch is CancellationError {
                return
            } catch {
                library.errorMessage = "Folik couldn’t import those dropped PDFs. \(error.localizedDescription)"
            }
        }
    }
}

private struct PDFDropOverlay: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.regularMaterial)
            VStack(spacing: 12) {
                Image(systemName: "arrow.down.document.fill")
                    .font(.largeTitle)
                    .foregroundStyle(FolikTheme.cobalt)
                Text("Drop PDFs to Import")
                    .font(.title2.weight(.bold))
                Text("Your originals stay unchanged.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .padding(24)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Drop PDFs to import. Your originals stay unchanged.")
        .accessibilityIdentifier("library.dropTarget")
    }
}

private extension View {
    @ViewBuilder
    func pdfDropDestination(
        isEnabled: Bool,
        isTargeted: Binding<Bool>,
        action: @escaping ([PDFTransferItem]) -> Void
    ) -> some View {
        if #available(iOS 26.0, *) {
            dropDestination(for: PDFTransferItem.self, isEnabled: isEnabled) { items, session in
                switch session.phase {
                case .entering, .active:
                    isTargeted.wrappedValue = true
                case .dataTransferCompleted:
                    isTargeted.wrappedValue = false
                    action(items)
                case .exiting, .ended:
                    isTargeted.wrappedValue = false
                @unknown default:
                    isTargeted.wrappedValue = false
                }
            }
        } else {
            modifier(LegacyPDFDropDestination(isEnabled: isEnabled, isTargeted: isTargeted, action: action))
        }
    }
}

@available(iOS, introduced: 16.0, obsoleted: 26.0)
private struct LegacyPDFDropDestination: ViewModifier {
    let isEnabled: Bool
    @Binding var isTargeted: Bool
    let action: ([PDFTransferItem]) -> Void

    func body(content: Content) -> some View {
        content.dropDestination(for: PDFTransferItem.self) { items, _ in
            guard isEnabled, !items.isEmpty else { return false }
            action(items)
            return true
        } isTargeted: { targeted in
            isTargeted = isEnabled && targeted
        }
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

#Preview {
    ContentView()
        .environmentObject(DocumentLibrary(previewDocuments: []))
}

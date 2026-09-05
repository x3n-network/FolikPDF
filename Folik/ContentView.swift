import AVFoundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var library: DocumentLibrary
    @State private var path: [LibraryDocument] = []
    @State private var isImporterPresented = false
    @State private var isScannerPresented = false
    @State private var cameraPermissionAlertPresented = false
    @State private var isSettingsPresented = false
    @State private var conversionMode: PDFConversionView.Mode?
    @State private var convertedDocument: LibraryDocument?
    @State private var officeConverterPresented = false
    @State private var searchablePDFPresented = false
    @State private var searchText = ""
    @State private var handledDebugLaunch = false

    var body: some View {
        NavigationStack(path: $path) {
            libraryRoot
                .navigationDestination(for: LibraryDocument.self) { item in
                    ReaderView(item: item)
                }
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
        .sheet(isPresented: $searchablePDFPresented, onDismiss: {
            if let document = convertedDocument { convertedDocument = nil; path.append(document) }
        }) {
            PDFToolView { document in convertedDocument = document; searchablePDFPresented = false }
        }
        .onOpenURL { url in
            Task {
                if let document = await library.importDocuments(at: [url]).first {
                    path.append(document)
                }
            }
        }
        .onChange(of: path.count) { _, count in
            if count == 0 { library.refresh() }
        }
        .onAppear {
            #if DEBUG
            guard !handledDebugLaunch else { return }
            handledDebugLaunch = true
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("--ui-test-fixture") {
                library.prepareUITestFixture()
            }
            if arguments.contains("--open-settings") {
                isSettingsPresented = true
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
            documents: filteredDocuments,
            isImporting: library.isImporting,
            importStatus: library.importStatus,
            canScan: DocumentScannerView.isSupported,
            openImporter: { isImporterPresented = true },
            openScanner: beginScanning,
            openImageConverter: { conversionMode = .images },
            openTextConverter: { conversionMode = .text },
            openOfficeConverter: { officeConverterPresented = true },
            openSearchablePDF: { searchablePDFPresented = true },
            openSettings: { isSettingsPresented = true },
            openDocument: { path.append($0) },
            deleteDocument: library.delete
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
            $0.displayName.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { library.errorMessage != nil },
            set: { if !$0 { library.errorMessage = nil } }
        )
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

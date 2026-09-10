import SwiftUI

@main
struct FolikApp: App {
    @StateObject private var library = DocumentLibrary()
    @StateObject private var appLock = AppLockManager()

    var body: some Scene {
        WindowGroup {
            FolikSceneRoot(appLock: appLock, becameActive: importSharedPDFsIfAppropriate) {
                ContentView()
            }
                .environmentObject(library)
        }

        WindowGroup("PDF", id: "pdf", for: String.self) { $documentReference in
            FolikSceneRoot(appLock: appLock, becameActive: {
                library.refresh()
                await importSharedPDFsIfAppropriate()
            }) {
                DocumentWindowView(reference: documentReference)
            }
                .environmentObject(library)
        }
    }

    @MainActor
    private func importSharedPDFsIfAppropriate() async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-test-fixture") &&
            !ProcessInfo.processInfo.arguments.contains("--ui-test-shared-inbox") {
            return
        }
        #endif
        await library.importSharedInbox()
    }
}

private struct FolikSceneRoot<Content: View>: View {
    @ObservedObject var appLock: AppLockManager
    let becameActive: () async -> Void
    @ViewBuilder let content: () -> Content
    @Environment(\.scenePhase) private var scenePhase
    @State private var sceneID = UUID()

    private var obscuresContent: Bool {
        appLock.isEnabled && (appLock.isLocked || scenePhase != .active)
    }

    var body: some View {
        ZStack {
            content()
                .allowsHitTesting(!obscuresContent)
                .accessibilityHidden(obscuresContent)
            if obscuresContent {
                AppLockView()
                    .environmentObject(appLock)
                    .transition(.opacity)
            }
        }
        .environmentObject(appLock)
        .task {
            appLock.sceneChanged(to: scenePhase, sceneID: sceneID)
            if scenePhase == .active { await becameActive() }
        }
        .onChange(of: scenePhase) { _, phase in
            appLock.sceneChanged(to: phase, sceneID: sceneID)
            if phase == .active { Task { await becameActive() } }
        }
        .onDisappear {
            appLock.sceneDisconnected(sceneID)
        }
    }
}

private struct DocumentWindowView: View {
    let reference: String?
    @EnvironmentObject private var library: DocumentLibrary
    @State private var handledDebugRename = false

    private var document: LibraryDocument? {
        guard let reference else { return nil }
        if let identifier = UUID(uuidString: reference) {
            return library.document(id: identifier)
        }
        // Supports filename-valued scenes created by early 1.0.3 development builds.
        return library.documents.first { $0.url.lastPathComponent == reference }
    }

    var body: some View {
        NavigationStack {
            if let document {
                ReaderView(item: document)
                    .id(document.url)
            } else {
                ContentUnavailableView(
                    "PDF Unavailable",
                    systemImage: "doc.badge.ellipsis",
                    description: Text("This PDF may have been removed from Folik.")
                )
                .navigationTitle("Folik")
            }
        }
        .tint(FolikTheme.cobalt)
        #if DEBUG
        .task {
            guard !handledDebugRename,
                  ProcessInfo.processInfo.arguments.contains("--ui-test-rename-window-document"),
                  let document else { return }
            handledDebugRename = true
            _ = try? library.rename(document, to: "Renamed Window Test")
        }
        #endif
    }
}

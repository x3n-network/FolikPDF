import SwiftUI

@main
struct FolikApp: App {
    @StateObject private var library = DocumentLibrary()
    @StateObject private var appLock = AppLockManager()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                    .environmentObject(library)
                    .allowsHitTesting(!appLock.obscuresContent)
                    .accessibilityHidden(appLock.obscuresContent)
                if appLock.obscuresContent {
                    AppLockView()
                        .environmentObject(appLock)
                        .transition(.opacity)
                }
            }
            .environmentObject(appLock)
            .task {
                await importSharedPDFsIfAppropriate()
            }
            .onChange(of: scenePhase) { _, phase in
                appLock.sceneChanged(to: phase)
                if phase == .active {
                    Task { await importSharedPDFsIfAppropriate() }
                }
            }
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

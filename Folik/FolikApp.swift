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
            .onChange(of: scenePhase) { _, phase in
                appLock.sceneChanged(to: phase)
            }
        }
    }
}

import SwiftUI

@main
struct FolikApp: App {
    @StateObject private var library = DocumentLibrary()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(library)
        }
    }
}

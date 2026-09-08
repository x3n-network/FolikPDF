import SwiftUI

struct RecentlyDeletedView: View {
    @EnvironmentObject private var library: DocumentLibrary
    @State private var deleting: DeletedDocument?
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                Text("Removed PDFs stay on this device until you restore them or delete them permanently.")
                    .foregroundStyle(.secondary)
                if library.unreadableDeletedCount > 0 {
                    Text("Some removed documents could not be read. Their files have been preserved.")
                        .foregroundStyle(.secondary)
                }
            }
            if library.recentlyDeleted.isEmpty {
                ContentUnavailableView("No Deleted Documents", systemImage: "trash", description: Text("Documents you remove from the library will appear here."))
            } else {
                Section {
                    ForEach(library.recentlyDeleted) { item in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(item.displayName).font(.headline)
                            Text("Removed \(item.deletedAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.footnote).foregroundStyle(.secondary)
                            HStack {
                                Button {
                                    do { try library.restoreDeleted(item) } catch { errorMessage = error.localizedDescription }
                                }
                                label: { Label("Restore", systemImage: "arrow.uturn.backward").frame(minHeight: 44) }
                                .accessibilityIdentifier("trash.restore.\(item.originalFilename)")
                                Spacer()
                                Button(role: .destructive) { deleting = item } label: {
                                    Label("Delete Permanently", systemImage: "trash")
                                        .labelStyle(.iconOnly)
                                        .frame(minWidth: 44, minHeight: 44)
                                }
                                    .accessibilityIdentifier("trash.delete.\(item.originalFilename)")
                            }
                            .buttonStyle(.borderless)
                            .frame(minHeight: 44)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle("Recently Deleted")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Delete this PDF permanently?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            if let item = deleting {
                Button("Delete Permanently", role: .destructive) {
                    do { try library.permanentlyDelete(item) } catch { errorMessage = error.localizedDescription }
                    deleting = nil
                }
            }
            Button("Cancel", role: .cancel) { deleting = nil }
        } message: { Text("This removes the PDF and its saved reading state from this device. This cannot be undone.") }
        .alert("Couldn’t Update Recently Deleted", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }
}

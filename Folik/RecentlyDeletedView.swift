import SwiftUI

struct RecentlyDeletedView: View {
    @EnvironmentObject private var library: DocumentLibrary
    @State private var deleting: DeletedDocument?
    @State private var errorMessage: String?
    @State private var selection: Set<DeletedDocument.ID> = []
    @State private var isSelecting = false
    @State private var deletionTargets: [DeletedDocument] = []
    @State private var confirmingBulkDeletion = false
    @State private var actionNotice: LibraryActionNotice?

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
                        deletedDocumentRow(item)
                    }
                }
            }
        }
        .navigationTitle("Recently Deleted")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: library.recentlyDeleted.map(\.id)) { _, ids in
            selection.formIntersection(ids)
            if selection.isEmpty && library.recentlyDeleted.isEmpty { isSelecting = false }
        }
        .toolbar {
            if !library.recentlyDeleted.isEmpty {
                ToolbarItem(placement: .topBarLeading) {
                    Button(isSelecting ? "Done" : "Select") {
                        isSelecting.toggle()
                        if !isSelecting { selection.removeAll() }
                    }
                    .accessibilityIdentifier("trash.select")
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Restore All") { restore(library.recentlyDeleted) }
                        Button("Delete All", role: .destructive) {
                            deletionTargets = library.recentlyDeleted
                            confirmingBulkDeletion = true
                        }
                    } label: {
                        Label("Recently Deleted Actions", systemImage: "ellipsis.circle")
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 8) {
                LibraryActionNoticeHost(notice: $actionNotice)
                    .padding(.horizontal, 16)
                if isSelecting {
                    HStack(spacing: 12) {
                        Text("\(selection.count) selected")
                            .font(.subheadline.weight(.semibold))
                            .accessibilityIdentifier("trash.selectionCount")
                        Spacer()
                        Button {
                            restore(selectedDocuments)
                        } label: {
                            Label("Restore", systemImage: "arrow.uturn.backward")
                                .frame(minHeight: 44)
                        }
                        .disabled(selection.isEmpty)
                        Button(role: .destructive) {
                            deletionTargets = selectedDocuments
                            confirmingBulkDeletion = true
                        } label: {
                            Image(systemName: "trash").frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("Delete selected documents permanently")
                        .disabled(selection.isEmpty)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.bar)
                    .overlay(alignment: .top) { Divider() }
                }
            }
        }
        .alert("Delete this PDF permanently?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            if let item = deleting {
                Button("Delete Permanently", role: .destructive) {
                    do { try library.permanentlyDelete(item) } catch { errorMessage = error.localizedDescription }
                    deleting = nil
                }
            }
            Button("Cancel", role: .cancel) { deleting = nil }
        } message: { Text("This removes the PDF and its saved reading state from this device. This cannot be undone.") }
        .alert("Delete \(deletionTargets.count) document\(deletionTargets.count == 1 ? "" : "s") permanently?", isPresented: $confirmingBulkDeletion) {
            Button("Delete Permanently", role: .destructive) {
                permanentlyDelete(deletionTargets)
            }
            Button("Cancel", role: .cancel) { deletionTargets = [] }
        } message: {
            Text("This cannot be undone.")
        }
        .alert("Couldn’t Update Recently Deleted", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private var selectedDocuments: [DeletedDocument] {
        library.recentlyDeleted.filter { selection.contains($0.id) }
    }

    @ViewBuilder
    private func deletedDocumentRow(_ item: DeletedDocument) -> some View {
        if isSelecting {
            Button {
                if selection.contains(item.id) { selection.remove(item.id) }
                else { selection.insert(item.id) }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: selection.contains(item.id) ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(selection.contains(item.id) ? FolikTheme.cobalt : .secondary)
                        .accessibilityHidden(true)
                    deletedDocumentDescription(item)
                }
                .frame(minHeight: 52)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.displayName)
            .accessibilityValue(selection.contains(item.id) ? "Selected" : "Not selected")
        } else {
            VStack(alignment: .leading, spacing: 8) {
                deletedDocumentDescription(item)
                HStack {
                    Button {
                        restore([item])
                    } label: {
                        Label("Restore", systemImage: "arrow.uturn.backward").frame(minHeight: 44)
                    }
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

    private func deletedDocumentDescription(_ item: DeletedDocument) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.displayName).font(.headline)
            Text("Removed \(item.deletedAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func restore(_ items: [DeletedDocument]) {
        do {
            var restoredURLs: [URL] = []
            try library.performBatch {
                for item in items { restoredURLs.append(try library.restoreDeleted(item)) }
            }
            selection.subtract(items.map(\.id))
            if selection.isEmpty { isSelecting = false }
            let restoredDocuments = library.documents.filter { restoredURLs.contains($0.url) }
            let subject = items.count == 1 ? items[0].displayName : "\(items.count) documents"
            showNotice("Restored \(subject)", actionTitle: restoredDocuments.isEmpty ? nil : "Undo") {
                library.delete(restoredDocuments)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func permanentlyDelete(_ items: [DeletedDocument]) {
        do {
            try library.performBatch { for item in items { try library.permanentlyDelete(item) } }
            selection.subtract(items.map(\.id))
            if selection.isEmpty { isSelecting = false }
        } catch {
            errorMessage = error.localizedDescription
        }
        deletionTargets = []
    }

    private func showNotice(_ message: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        actionNotice = LibraryActionNotice(message: message, actionTitle: actionTitle, action: action)
    }
}

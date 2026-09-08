import SwiftUI

struct DocumentOrganizationView: View {
    let documents: [LibraryDocument]
    @EnvironmentObject private var library: DocumentLibrary
    @Environment(\.dismiss) private var dismiss
    @State private var folder = ""
    @State private var tags = ""
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                if documents.count > 1 {
                    Section {
                        Label("Apply to \(documents.count) documents", systemImage: "doc.on.doc")
                        Text("Saving replaces the folder and tags on every selected document.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Section("Folder") {
                    TextField("Folder name (optional)", text: $folder).accessibilityIdentifier("organization.folder")
                    if !library.folders.isEmpty {
                        Menu("Choose Existing Folder") {
                            Button("Unfiled") { folder = "" }
                            ForEach(library.folders, id: \.self) { name in Button(name) { folder = name } }
                        }
                    }
                    Text("Folders organize your library without moving PDF files.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Tags") {
                    TextField("Tags separated by commas", text: $tags).accessibilityIdentifier("organization.tags")
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("Organize Document").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        do {
                            try library.organize(documents, folder: folder, tags: tags.components(separatedBy: ","))
                            dismiss()
                        } catch { self.error = error.localizedDescription }
                    }.accessibilityIdentifier("organization.save")
                }
            }
            .onAppear {
                guard documents.count == 1, let document = documents.first else { return }
                let value = library.metadata(for: document)
                folder = value.folder
                tags = value.tags.joined(separator: ", ")
            }
        }
    }
}

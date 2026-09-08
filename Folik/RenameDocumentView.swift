import SwiftUI

struct RenameDocumentView: View {
    let document: LibraryDocument
    @EnvironmentObject private var library: DocumentLibrary
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var error: String?

    init(document: LibraryDocument) {
        self.document = document
        _name = State(initialValue: document.displayName)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Filename") {
                    TextField("PDF filename", text: $name)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("rename.name")
                    Text("The PDF extension is added automatically. Folders, tags, bookmarks, and reading position stay with the document.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("Rename Document")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Rename") {
                        do {
                            try library.rename(document, to: name)
                            dismiss()
                        } catch {
                            self.error = error.localizedDescription
                        }
                    }
                    .accessibilityIdentifier("rename.save")
                }
            }
        }
    }
}

import SwiftUI

struct SavePersonalTemplateView: View {
    @ObservedObject var session: DocumentSession
    @EnvironmentObject private var library: DocumentLibrary
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var clearAnswers = true
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Template name") { TextField("Name", text: $name).accessibilityIdentifier("template.name") }
                Section {
                    Picker("Field answers", selection: $clearAnswers) {
                        Text("Clear answers").tag(true)
                        Text("Keep as defaults").tag(false)
                    }
                    Text(clearAnswers ? "Text, choices, and checkboxes start empty." : "New copies start with the current field answers. Keep only values you want to reuse.")
                        .font(.footnote).foregroundStyle(.secondary)
                } footer: {
                    Text("Page content, notes, and drawn signatures stay in the template. Review them before saving. Your working document stays unchanged.")
                }
                if let error { Text(error).foregroundStyle(.red) }
                if saving { ProgressView("Saving template…") }
            }
            .navigationTitle("Save My Template")
            .navigationBarTitleDisplayMode(.inline)
            .task { name = session.item.displayName }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saving = true
                        Task {
                            defer { saving = false }
                            guard await session.saveForSharing() else { error = session.saveStatus; return }
                            do {
                                let url = session.item.url
                                let data = try await Task.detached { try Data(contentsOf: url) }.value
                                try await library.saveTemplate(data, named: name, clearAnswers: clearAnswers)
                                dismiss()
                            } catch { self.error = error.localizedDescription }
                        }
                    }
                    .disabled(saving || library.isImporting || (try? PDFConverter.fileName(name)) == nil)
                    .accessibilityIdentifier("template.save")
                }
            }
            .interactiveDismissDisabled(saving)
        }
    }
}

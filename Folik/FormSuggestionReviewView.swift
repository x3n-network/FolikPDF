import SwiftUI

struct FormSuggestionReviewView: View {
    @Binding var suggestions: [FormFieldSuggestion]
    let data: Data?
    @Binding var selectedIDs: Set<UUID>
    let apply: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var pagePosition = 0
    @State private var editing: FormFieldSuggestion?
    private var pages: [Int] { Array(Set(suggestions.map(\.pageIndex))).sorted() }
    private var pageIndex: Int { pages.indices.contains(pagePosition) ? pages[pagePosition] : 0 }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if let data {
                        ReadOnlyPDFPreview(data: data, pageIndex: pageIndex, suggestions: suggestions, selectedIDs: selectedIDs, toggle: toggle)
                            .frame(height: 340)
                            .accessibilityLabel("Suggested fields on page \(pageIndex + 1). Use the controls below to include, skip, or edit each field.")
                            .accessibilityIdentifier("reader.form.suggestionPreview")
                    }
                    if pages.count > 1 {
                        HStack {
                            Button("Previous") { pagePosition -= 1 }.disabled(pagePosition == 0)
                            Spacer()
                            Text("Page \(pageIndex + 1)")
                            Spacer()
                            Button("Next") { pagePosition += 1 }.disabled(pagePosition + 1 >= pages.count)
                        }.buttonStyle(.borderless).frame(minHeight: 44)
                    }
                    Menu("Selection") {
                        Button("Select All") { selectedIDs = Set(suggestions.map(\.id)) }
                        Button("Select None") { selectedIDs = [] }
                    }.frame(minHeight: 44)
                    Text("Tap a box to include or skip it. Pinch to zoom. Changes are added only when you choose Add.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Fields on page \(pageIndex + 1)") {
                    ForEach(suggestions.filter { $0.pageIndex == pageIndex }) { suggestion in
                        VStack(alignment: .leading, spacing: 6) {
                            Toggle(isOn: Binding(get: { selectedIDs.contains(suggestion.id) }, set: { _ in toggle(suggestion.id) })) {
                                Text(suggestion.label).font(.headline)
                            }
                            .accessibilityIdentifier("reader.form.suggestion.\(suggestion.id)")
                            Text("\(suggestion.kind.title) · \(suggestion.reason)")
                                .font(.caption).foregroundStyle(.secondary)
                            Button("Edit label and type") { editing = suggestion }
                                .frame(minHeight: 44)
                                .accessibilityIdentifier("reader.form.editSuggestion")
                        }
                    }
                }
            }
            .navigationTitle("Suggested Fields")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add \(selectedIDs.count)", action: apply)
                        .disabled(selectedIDs.isEmpty)
                        .accessibilityIdentifier("reader.form.applySuggestions")
                }
            }
            .sheet(item: $editing) { suggestion in
                SuggestionEditor(suggestion: suggestion) { updated in
                    if let index = suggestions.firstIndex(where: { $0.id == updated.id }) { suggestions[index] = updated }
                    editing = nil
                }
            }
        }
    }
    private func toggle(_ id: UUID) {
        if selectedIDs.contains(id) { selectedIDs.remove(id) } else { selectedIDs.insert(id) }
    }
}

private struct SuggestionEditor: View {
    @State var suggestion: FormFieldSuggestion
    let save: (FormFieldSuggestion) -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                TextField("Field label", text: $suggestion.label)
                    .accessibilityIdentifier("suggestion.label")
                Picker("Field type", selection: $suggestion.kind) {
                    ForEach(FormFieldPlacementKind.allCases) { Text($0.title).tag($0) }
                }
            }
            .navigationTitle("Edit Suggested Field")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        suggestion.label = String(suggestion.label.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
                        save(suggestion)
                    }.disabled(suggestion.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

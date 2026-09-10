import SwiftUI

struct FormLayoutToolsView: View {
    @ObservedObject var session: DocumentSession
    @Environment(\.dismiss) private var dismiss
    @State private var orderMode = false
    @State private var pageIndex = 0
    @State private var selected: Set<String> = []
    @State private var message: String?
    private var pageFields: [FormField] { session.formFields.filter { $0.pageIndex == pageIndex && !$0.isReadOnly } }

    var body: some View {
        NavigationStack {
            List {
                Picker("Tools", selection: $orderMode) {
                    Text("Layout").tag(false)
                    Text("Fill order").tag(true)
                }.pickerStyle(.segmented)
                if orderMode {
                    Section {
                        ForEach(session.formFields) { field in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(field.title)
                                    Text("Page \(field.pageIndex + 1)").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button { move(field.id, by: -1) } label: { Image(systemName: "arrow.up").frame(width: 44, height: 44) }
                                    .disabled(field.id == session.formFields.first?.id)
                                    .accessibilityLabel("Move \(field.title) earlier")
                                Button { move(field.id, by: 1) } label: { Image(systemName: "arrow.down").frame(width: 44, height: 44) }
                                    .disabled(field.id == session.formFields.last?.id)
                                    .accessibilityLabel("Move \(field.title) later")
                            }.buttonStyle(.borderless)
                        }
                        .onMove { indices, destination in
                            var ids = session.formFields.map(\.id)
                            ids.move(fromOffsets: indices, toOffset: destination)
                            session.setFormFillOrder(ids)
                        }
                    } header: { Text("Order in Folik") } footer: {
                        Text("Controls Folik’s field list and next-empty-field navigation. Required fields still come first when unfinished. Other PDF apps may use their own order.")
                    }
                } else {
                    Section {
                        Picker("Page", selection: $pageIndex) {
                            ForEach(0..<session.pageCount, id: \.self) { Text("Page \($0 + 1)").tag($0) }
                        }
                        Button("Select all on page") { selected = Set(pageFields.map(\.id)) }
                        Button("Clear selection") { selected = [] }
                        ForEach(pageFields) { field in
                            Toggle(field.title, isOn: Binding(get: { selected.contains(field.id) }, set: { on in
                                if on { selected.insert(field.id) } else { selected.remove(field.id) }
                            })).accessibilityIdentifier("layout.field." + field.title)
                        }
                    } header: { Text("Select fields") } footer: {
                        if let reference = pageFields.first(where: { selected.contains($0.id) }) {
                            Text("Alignment and size use \(reference.title) as the reference. Changes stay inside the page.")
                        }
                    }
                    Section("Arrange selected fields") {
                        ForEach(FormLayoutAction.allCases) { action in
                            Button(action.title) {
                                message = session.arrangeFormFields(ids: selected, action: action) ? "Fields arranged. You can undo this change." : "There isn’t enough room for that arrangement. Try fewer fields or move them farther apart."
                            }
                            .disabled(selected.count < action.minimumCount)
                            .accessibilityIdentifier("layout." + action.rawValue)
                        }
                    }
                    if let message { Text(message).font(.footnote).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle("Form Layout Tools")
            .navigationBarTitleDisplayMode(.inline)
            .task { pageIndex = session.pageIndex }
            .onChange(of: pageIndex) { _, _ in selected = []; message = nil }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button("Undo", action: session.undoAnnotationAction).disabled(!session.canUndoAnnotation)
                }
            }
        }
    }
    private func move(_ id: String, by offset: Int) {
        var ids = session.formFields.map(\.id)
        guard let index = ids.firstIndex(of: id), ids.indices.contains(index + offset) else { return }
        ids.swapAt(index, index + offset)
        session.setFormFillOrder(ids)
    }
}

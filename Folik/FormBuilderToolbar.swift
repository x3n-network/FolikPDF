import PDFKit
import SwiftUI

struct FormBuilderToolbar: View {
    @ObservedObject var session: DocumentSession
    let showFields: () -> Void
    let fill: () -> Void
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var editingProperties = false
    @State private var layoutTools = false
    @State private var label = ""
    @State private var required = false

    var body: some View {
        Group {
            if verticalSizeClass == .compact || dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 6) {
                    if verticalSizeClass != .compact, session.formFieldPlacement != nil {
                        Button("Place center", action: session.placeAnnotationAtCurrentPageCenter)
                            .buttonStyle(.borderedProminent)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .accessibilityIdentifier("reader.annotation.placeCenter")
                    }
                    ScrollView(.horizontal) {
                        HStack(spacing: 12) {
                            if verticalSizeClass == .compact, session.formFieldPlacement != nil {
                                Button("Place center", action: session.placeAnnotationAtCurrentPageCenter)
                                    .accessibilityIdentifier("reader.annotation.placeCenter")
                            }
                            Button("Fields", action: showFields).accessibilityIdentifier("reader.panel.forms")
                            layoutButton
                            Button("Fill", action: fill).accessibilityIdentifier("builder.fill")
                            Button("Arrange", action: session.arrangeFormFields).accessibilityIdentifier("builder.arrange")
                            if verticalSizeClass == .compact {
                                Menu("Add field") {
                                    ForEach(FormFieldPlacementKind.allCases) { kind in
                                        Button(kind.title) { session.beginQuickFormFieldPlacement(kind) }
                                    }
                                }
                            } else {
                                ForEach(FormFieldPlacementKind.allCases) { kind in
                                    Button(kind.title) { session.beginQuickFormFieldPlacement(kind) }
                                        .accessibilityLabel("Add \(kind.title.lowercased())")
                                        .accessibilityIdentifier("builder.add.\(kind.rawValue)")
                                }
                            }
                            if let field = session.selectedAuthoredFormField {
                                Button("Edit label") {
                                    label = field.title; required = field.isRequired; editingProperties = true
                                }.accessibilityIdentifier("builder.properties")
                                Button("Duplicate", action: session.duplicateSelectedFormField).accessibilityIdentifier("builder.duplicate")
                            }
                            Button("Undo", action: session.undoAnnotationAction).disabled(!session.canUndoAnnotation)
                                .accessibilityIdentifier("builder.undo")
                            Button("Redo", action: session.redoAnnotationAction).disabled(!session.canRedoAnnotation)
                        }
                        .buttonStyle(.bordered)
                        .frame(minHeight: 44)
                    }
                }
            } else {
                VStack(spacing: 6) {
                    if session.formFields.isEmpty && session.formFieldPlacement == nil {
                        Label("Choose a field type, then tap the page.", systemImage: "hand.tap")
                            .font(.caption)
                            .foregroundStyle(FolikTheme.mutedInk)
                            .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                            .accessibilityIdentifier("builder.guidance")
                    }
                    HStack(spacing: 8) {
                        Button("Fields", action: showFields)
                            .accessibilityIdentifier("reader.panel.forms")
                        layoutButton
                        Spacer(minLength: 0)
                        Button(action: session.undoAnnotationAction) { Image(systemName: "arrow.uturn.backward").frame(width: 44, height: 44) }
                            .disabled(!session.canUndoAnnotation).accessibilityLabel("Undo form change")
                            .accessibilityIdentifier("builder.undo")
                        Button(action: session.redoAnnotationAction) { Image(systemName: "arrow.uturn.forward").frame(width: 44, height: 44) }
                            .disabled(!session.canRedoAnnotation).accessibilityLabel("Redo form change")
                        Button("Fill", action: fill).buttonStyle(.bordered)
                            .accessibilityIdentifier("builder.fill")
                    }
                    .buttonStyle(.plain)
                    .frame(minHeight: 44)

                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(FormFieldPlacementKind.allCases) { kind in
                                Button {
                                    session.beginQuickFormFieldPlacement(kind)
                                } label: {
                                    Label(shortTitle(kind), systemImage: kind.icon)
                                        .frame(minHeight: 44)
                                        .padding(.horizontal, 10)
                                        .background(session.formFieldPlacement?.kind == kind ? FolikTheme.cobalt.opacity(0.18) : FolikTheme.surface, in: RoundedRectangle(cornerRadius: 10))
                                }
                                .accessibilityLabel("Add \(kind.title.lowercased())")
                                .accessibilityAddTraits(session.formFieldPlacement?.kind == kind ? .isSelected : [])
                                .accessibilityIdentifier("builder.add.\(kind.rawValue)")
                            }
                        }
                    }
                    .scrollIndicators(.visible)
                    .buttonStyle(.plain)

                    if session.formFieldPlacement != nil {
                        ViewThatFits(in: .horizontal) {
                            HStack { placementActions }
                            VStack { placementActions }
                        }
                    } else if let field = session.selectedAuthoredFormField {
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 8) { selectedFieldActions(field) }
                            VStack(alignment: .leading, spacing: 6) { selectedFieldActions(field) }
                        }
                        .buttonStyle(.bordered)
                        .frame(minHeight: 44)
                    } else if !session.isAnnotationEditingEnabled {
                        Button("Arrange fields", action: session.arrangeFormFields)
                            .frame(minHeight: 44)
                            .accessibilityIdentifier("builder.arrange")
                    }
                }
            }
        }
        .font(.subheadline)
        .dynamicTypeSize(...DynamicTypeSize.accessibility5)
        .sheet(isPresented: $layoutTools) { FormLayoutToolsView(session: session) }
        .sheet(isPresented: $editingProperties) {
            NavigationStack {
                Form {
                    Section("Field details") {
                        TextField("Field label", text: $label)
                        Toggle("Required", isOn: $required)
                    }
                }
                .navigationTitle("Edit Field")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { editingProperties = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            session.updateSelectedFormField(label: label, isRequired: required)
                            editingProperties = false
                        }
                        .disabled(label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("builder.saveProperties")
                    }
                }
            }
        }
    }

    private var layoutButton: some View {
        Button("Layout tools") { layoutTools = true }
            .disabled(session.formFields.isEmpty)
            .accessibilityIdentifier("builder.layoutTools")
    }

    @ViewBuilder private var placementActions: some View {
        Text("Tap the page to add fields.").foregroundStyle(.secondary)
        Button("Place center", action: session.placeAnnotationAtCurrentPageCenter)
            .buttonStyle(.bordered)
            .frame(minHeight: 44)
            .accessibilityIdentifier("reader.annotation.placeCenter")
        Button("Arrange", action: session.arrangeFormFields)
            .frame(minHeight: 44)
            .accessibilityIdentifier("builder.arrange")
    }

    @ViewBuilder private func selectedFieldActions(_ field: FormField) -> some View {
        Label(field.isRequired ? "\(field.title) · Required" : field.title, systemImage: "list.clipboard")
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .foregroundStyle(FolikTheme.mutedInk)
            .accessibilityLabel("Selected field: \(field.title)\(field.isRequired ? ", required" : "")")
        Spacer(minLength: 0)
        Button("Edit") {
            label = field.title
            required = field.isRequired
            editingProperties = true
        }
        .accessibilityLabel("Edit field details")
        .accessibilityIdentifier("builder.properties")
        Button("Duplicate", action: session.duplicateSelectedFormField)
            .accessibilityIdentifier("builder.duplicate")
    }

    private func shortTitle(_ kind: FormFieldPlacementKind) -> String {
        switch kind {
        case .text: "Text"
        case .multilineText: "Paragraph"
        case .checkbox: "Checkbox"
        case .date: "Date"
        case .signature: "Signature"
        }
    }
}

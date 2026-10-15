import SwiftUI
import PDFKit

/// One real PDF field at a time. Selection belongs to the document session, not
/// this composition, so showing a pane or rebuilding the reader never navigates.
struct ReaderFillCompanion: View {
    @ObservedObject var session: DocumentSession
    let close: () -> Void
    @FocusState private var editorFocused: Bool
    @State private var mutationNotice: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Fill", systemImage: "text.badge.checkmark")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Button {
                    editorFocused = false
                    close()
                } label: {
                    Image(systemName: "xmark").frame(width: 44, height: 44)
                }
                .accessibilityLabel("Close Fill tools")
                .accessibilityIdentifier("reader.fill.close")
            }
            .padding(.horizontal, 16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    completion
                    if let notice = session.formCompatibilityNotice {
                        Label(notice, systemImage: "info.circle")
                            .font(.footnote)
                            .foregroundStyle(FolikTheme.mutedInk)
                    }
                    if !session.formFields.isEmpty {
                        fieldMenu
                    }
                    if let field = session.selectedFillField {
                        selectedEditor(field)
                            .id(field.id)
                    } else {
                        ContentUnavailableView(
                            session.isLocked ? "Document locked" : "No form fields",
                            systemImage: session.isLocked ? "lock.doc" : "doc.text",
                            description: Text(session.isLocked
                                ? "Unlock the document to review its form fields."
                                : "This PDF has no standard form fields to fill. Use the annotation tools to add text or a visual signature.")
                        )
                    }
                    if let mutationNotice {
                        Label(mutationNotice, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(FolikTheme.mutedInk)
                            .accessibilityIdentifier("reader.fill.editNotice")
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)

            // These remain reachable without scrolling through a long field.
            Divider()
            VStack(spacing: 4) {
                Button {
                    editorFocused = false
                    session.goToNextIncompleteFormField()
                } label: {
                    Label("Next unfinished", systemImage: "arrow.down.circle")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .disabled(session.isLocked || !session.canFillForms || session.incompleteFormFieldCount == 0)
                .accessibilityHint("Moves to the next unfinished field, with required fields first")
                .accessibilityIdentifier("reader.fill.nextUnfinished")

                Button(action: session.requestSave) {
                    Text(session.saveStatus).font(.footnote)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                    .disabled(session.isLocked || session.isSaving)
                    .accessibilityIdentifier("reader.fill.save")
            }
            .padding(16)
        }
        .background(FolikTheme.surface)
        .foregroundStyle(FolikTheme.ink)
        .tint(FolikTheme.cobalt)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("reader.fill.companion")
        .onAppear { session.prepareFillCompanion() }
        .onChange(of: session.formFields.map(\.id)) { _, _ in session.prepareFillCompanion() }
        .onChange(of: session.selectedFillFieldID) { _, _ in
            editorFocused = false
            mutationNotice = nil
        }
    }

    private var completion: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(session.completedFormFieldCount) of \(session.fillableFormFieldCount) fields completed")
                .font(.subheadline.weight(.medium))
                .accessibilityIdentifier("reader.fill.completion")
            if session.fillableFormFieldCount > 0 {
                ProgressView(value: Double(session.completedFormFieldCount), total: Double(session.fillableFormFieldCount))
                    .accessibilityLabel("Form completion")
                    .accessibilityValue("\(session.completedFormFieldCount) of \(session.fillableFormFieldCount)")
            }
            if session.remainingRequiredFormFieldCount > 0 {
                Text("\(session.remainingRequiredFormFieldCount) required fields unfinished")
                    .font(.footnote)
                    .foregroundStyle(FolikTheme.mutedInk)
            }
        }
    }

    private var fieldMenu: some View {
        Menu {
            ForEach(menuFields) { field in
                Button {
                    editorFocused = false
                    session.selectFillField(field.id)
                } label: {
                    Label("\(field.title) · Page \(field.pageIndex + 1)", systemImage: field.id == session.selectedFillFieldID ? "checkmark" : "circle")
                }
            }
        } label: {
            HStack {
                Text(session.selectedFillField?.title ?? "Choose a field")
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                Image(systemName: "chevron.up.chevron.down")
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .accessibilityLabel("Field")
        .accessibilityValue(session.selectedFillField?.title ?? "None selected")
        .accessibilityIdentifier("reader.fill.fieldMenu")
    }

    private var menuFields: [FormField] {
        var seen = Set<String>()
        return session.formFields.filter { seen.insert($0.logicalID).inserted }
    }

    @ViewBuilder
    private func selectedEditor(_ field: FormField) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(field.title)
                .font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Text("\(field.kind.title) · Page \(field.pageIndex + 1)\(field.isRequired ? " · Required" : "")")
                .font(.footnote)
                .foregroundStyle(FolikTheme.mutedInk)

            if session.isLocked || !session.canFillForms {
                Text("This document does not allow form field entry.")
                    .font(.callout)
            } else if field.isReadOnly {
                Text("Read only")
                    .font(.callout.weight(.medium))
                Text(field.statusText)
                    .foregroundStyle(FolikTheme.mutedInk)
            } else {
                fieldControl(field)
            }

            Button {
                editorFocused = false
                session.selectFillField(field.id)
            } label: {
                Label("Open on page", systemImage: "doc.text.magnifyingglass").frame(minHeight: 44)
            }
            .accessibilityIdentifier("reader.fill.openOnPage")
        }
    }

    @ViewBuilder
    private func fieldControl(_ field: FormField) -> some View {
        switch field.kind {
        case .text, .multilineText:
            if field.annotation.isPasswordField {
                SecureField(field.title, text: textBinding(field.id))
                    .textFieldStyle(.plain)
                    .padding(12)
                    .frame(minHeight: 52)
                    .background(FolikTheme.raisedSurface, in: RoundedRectangle(cornerRadius: 12))
                    .overlay { RoundedRectangle(cornerRadius: 12).stroke(FolikTheme.cobalt.opacity(0.5), lineWidth: 1) }
                    .focused($editorFocused)
                    .accessibilityIdentifier("reader.fill.value")
            } else {
                TextField(field.title, text: textBinding(field.id), axis: field.kind == .multilineText ? .vertical : .horizontal)
                    .lineLimit(field.kind == .multilineText ? 5...12 : 1...1)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .frame(minHeight: 52)
                    .background(FolikTheme.raisedSurface, in: RoundedRectangle(cornerRadius: 12))
                    .overlay { RoundedRectangle(cornerRadius: 12).stroke(FolikTheme.cobalt.opacity(0.5), lineWidth: 1) }
                    .focused($editorFocused)
                    .accessibilityIdentifier("reader.fill.value")
            }
        case .checkbox:
            Toggle(field.title, isOn: Binding(
                get: { session.formFields.first { $0.id == field.id }?.isSelected ?? false },
                set: { recordMutation(session.setFillFieldSelected(fieldID: field.id, selected: $0)) }
            ))
            .accessibilityIdentifier("reader.fill.checkbox")
        case .choice:
            let choices = session.fillFieldChoices(fieldID: field.id)
            if choices.isEmpty {
                Text("Review this choice field on the page. Multiple selections and custom choices are not edited in this pane.")
                    .font(.callout)
            } else {
                Picker(field.title, selection: Binding(
                    get: { choices.first { $0.title == session.formFields.first { $0.id == field.id }?.value }?.value ?? "" },
                    set: { recordMutation(session.setFillFieldValue(fieldID: field.id, value: $0)) }
                )) {
                    Text("Choose…").tag("").disabled(true)
                    ForEach(choices) { choice in Text(choice.title).tag(choice.value) }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("reader.fill.choice")
            }
        case .radio:
            Text("Select a radio option directly on the page. This keeps the PDF’s original option group and appearance intact.")
                .font(.callout)
        case .signature, .pushButton, .unknown:
            Text(field.limitation ?? "Review this field on the page.")
                .font(.callout)
        }
    }

    private func textBinding(_ fieldID: String) -> Binding<String> {
        Binding(
            get: { session.formFields.first { $0.id == fieldID }?.value ?? "" },
            set: { recordMutation(session.setFillFieldValue(fieldID: fieldID, value: $0)) }
        )
    }

    private func recordMutation(_ accepted: Bool) {
        mutationNotice = accepted ? nil : "This field cannot be changed here. Open it on the page to review its current settings."
    }
}

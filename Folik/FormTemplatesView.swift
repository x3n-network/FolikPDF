import PDFKit
import SwiftUI

struct FormTemplatesView: View {
    let complete: (LibraryDocument) -> Void
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var library: DocumentLibrary
    @State private var loadError: String?
    @State private var deleting: PersonalFormTemplate?
    @State private var renaming: PersonalFormTemplate?

    var body: some View {
        NavigationStack {
            List {
                Section("My Templates") {
                    if library.personalTemplates.isEmpty {
                        Text("Open a document’s Forms panel and choose Save as My Template to keep a reusable master.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    ForEach(library.personalTemplates) { template in
                        NavigationLink {
                            FormTemplatePreview(title: template.title, subtitle: "A new copy keeps the defaults saved in this template.", readData: { try Data(contentsOf: template.url) }, complete: complete)
                        } label: {
                            TemplateGalleryRow(
                                title: template.title,
                                subtitle: "Your reusable form",
                                fallbackIcon: "doc.text",
                                url: template.url
                            )
                        }
                        .accessibilityIdentifier("template.personal." + template.title)
                        .swipeActions {
                            Button("Delete", role: .destructive) { deleting = template }
                            Button("Rename") { renaming = template }.tint(FolikTheme.cobalt)
                        }
                        .contextMenu {
                            Button("Rename Template") { renaming = template }
                            Button("Delete Template", role: .destructive) { deleting = template }
                        }
                    }
                    if let loadError { Text(loadError).foregroundStyle(.red) }
                }
                Section {
                    ForEach(FormTemplate.allCases) { template in
                        NavigationLink {
                            FormTemplatePreview(title: template.title, subtitle: template.subtitle, readData: template.data, complete: complete)
                        } label: {
                            TemplateGalleryRow(
                                title: template.title,
                                subtitle: template.subtitle,
                                fallbackIcon: template.icon,
                                url: template.url
                            )
                        }
                        .accessibilityIdentifier("template.\(template.id)")
                    }
                } header: { Text("Included Templates") } footer: {
                    Text("Included on your device. Every form starts as a fresh copy, ready to fill and share. No downloads needed.")
                }
            }
            .task {
                do { try await library.refreshTemplates() } catch { loadError = error.localizedDescription }
            }
            .confirmationDialog("Delete template?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                Button("Delete Template", role: .destructive) {
                    if let deleting {
                        do { try library.deleteTemplate(deleting) } catch { loadError = error.localizedDescription }
                    }
                    deleting = nil
                }
            } message: { Text("Copies already in your library will remain.") }
            .sheet(item: $renaming) { template in
                RenamePersonalTemplateView(template: template) {
                    renaming = nil
                }
            }
            .navigationTitle("Form Templates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }
    }
}

private struct TemplateGalleryRow: View {
    let title: String
    let subtitle: String
    let fallbackIcon: String
    let url: URL?

    var body: some View {
        HStack(spacing: 14) {
            if let url {
                FilePDFThumbnail(url: url, size: CGSize(width: 104, height: 136), revision: "template-\(url.lastPathComponent)")
                    .frame(width: 52, height: 68)
            } else {
                Image(systemName: fallbackIcon)
                    .font(.title2)
                    .foregroundStyle(FolikTheme.cobalt)
                    .frame(width: 52, height: 68)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.headline)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 6)
    }
}

private struct RenamePersonalTemplateView: View {
    let template: PersonalFormTemplate
    let complete: () -> Void
    @EnvironmentObject private var library: DocumentLibrary
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var errorMessage: String?

    init(template: PersonalFormTemplate, complete: @escaping () -> Void) {
        self.template = template
        self.complete = complete
        _name = State(initialValue: template.title)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Template name") {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("template.rename.name")
                }
                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            }
            .navigationTitle("Rename Template")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Rename") {
                        do {
                            try library.renameTemplate(template, to: name)
                            complete()
                            dismiss()
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                    .disabled((try? PDFConverter.fileName(name)) == nil)
                    .accessibilityIdentifier("template.rename.save")
                }
            }
        }
    }
}

private struct FormTemplatePreview: View {
    let title: String
    let subtitle: String
    let readData: () throws -> Data
    let complete: (LibraryDocument) -> Void
    @EnvironmentObject private var library: DocumentLibrary
    @State private var preview: UIImage?
    @State private var pageIndex = 0
    @State private var pageCount = 1
    @State private var errorMessage: String?
    @State private var creating = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(subtitle).foregroundStyle(.secondary)
                if let preview {
                    Image(uiImage: preview)
                        .resizable().scaledToFit()
                        .accessibilityLabel("\(title) preview, page \(pageIndex + 1) of \(pageCount)")
                } else if let errorMessage {
                    ContentUnavailableView("Preview Unavailable", systemImage: "doc", description: Text(errorMessage))
                } else {
                    ProgressView("Loading preview").frame(maxWidth: .infinity)
                }
                if pageCount > 1 {
                    HStack {
                        Button("Previous") { pageIndex -= 1 }.disabled(pageIndex == 0)
                        Spacer()
                        Text("Page \(pageIndex + 1) of \(pageCount)")
                        Spacer()
                        Button("Next") { pageIndex += 1 }.disabled(pageIndex + 1 == pageCount)
                    }.frame(minHeight: 44)
                }
                Text("Fill the fields in Folik, or use Build to customize your copy.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .frame(maxWidth: 650)
            .padding()
            .frame(maxWidth: .infinity)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button(action: startForm) {
                HStack {
                    if creating { ProgressView().tint(.white) }
                    Text(creating ? "Creating Form…" : "Start Form").fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .disabled(creating || library.isImporting || preview == nil)
            .accessibilityIdentifier("template.start")
            .padding().background(.bar)
        }
        .interactiveDismissDisabled(creating)
        .navigationBarBackButtonHidden(creating)
        .task(id: pageIndex) {
            do {
                let document = PDFDocument(data: try readData())
                pageCount = document?.pageCount ?? 1
                guard let page = document?.page(at: pageIndex) else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                preview = page.thumbnail(of: CGSize(width: 1224, height: 1584), for: .mediaBox)
            } catch { errorMessage = error.localizedDescription }
        }
        .alert("Couldn’t Create Form", isPresented: Binding(
            get: { errorMessage != nil && preview != nil },
            set: { if !$0 { errorMessage = nil } }
        )) { Button("OK", role: .cancel) { errorMessage = nil } } message: {
            Text(errorMessage ?? "Please try again.")
        }
    }

    private func startForm() {
        guard !creating, !library.isImporting else { return }
        creating = true
        Task {
            do {
                let document = try await library.importConvertedPDF(.preparedPDF(readData()), named: title)
                complete(document)
            } catch {
                creating = false
                errorMessage = error.localizedDescription
            }
        }
    }
}

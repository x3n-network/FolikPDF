import PDFKit
import SwiftUI

struct FormTemplatesView: View {
    let complete: (LibraryDocument) -> Void
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var library: DocumentLibrary
    @State private var loadError: String?
    @State private var deleting: PersonalFormTemplate?

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
                            Label(template.title, systemImage: "doc.text")
                                .padding(.vertical, 8)
                        }
                        .accessibilityIdentifier("template.personal." + template.title)
                        .swipeActions { Button("Delete", role: .destructive) { deleting = template } }
                        .contextMenu { Button("Delete Template", role: .destructive) { deleting = template } }
                    }
                    if let loadError { Text(loadError).foregroundStyle(.red) }
                }
                Section {
                    ForEach(FormTemplate.allCases) { template in
                        NavigationLink {
                            FormTemplatePreview(title: template.title, subtitle: template.subtitle, readData: template.data, complete: complete)
                        } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(template.title).font(.headline)
                                    Text(template.subtitle).font(.subheadline).foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 8)
                            } icon: {
                                Image(systemName: template.icon).foregroundStyle(FolikTheme.cobalt)
                            }
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
            .navigationTitle("Form Templates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
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

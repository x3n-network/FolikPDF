import PDFKit
import SwiftUI

struct FormTemplatesView: View {
    let complete: (LibraryDocument) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(FormTemplate.allCases) { template in
                        NavigationLink {
                            FormTemplatePreview(template: template, complete: complete)
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
                } footer: {
                    Text("Included on your device. Every form starts as a fresh copy, ready to fill and share. No downloads needed.")
                }
            }
            .navigationTitle("Form Templates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }
    }
}

private struct FormTemplatePreview: View {
    let template: FormTemplate
    let complete: (LibraryDocument) -> Void
    @EnvironmentObject private var library: DocumentLibrary
    @State private var preview: UIImage?
    @State private var errorMessage: String?
    @State private var creating = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(template.subtitle).foregroundStyle(.secondary)
                if let preview {
                    Image(uiImage: preview)
                        .resizable().scaledToFit()
                        .accessibilityLabel("Blank \(template.title) preview, one page")
                } else if let errorMessage {
                    ContentUnavailableView("Preview Unavailable", systemImage: "doc", description: Text(errorMessage))
                } else {
                    ProgressView("Loading preview").frame(maxWidth: .infinity)
                }
                Text("Fill the fields in Folik, or use Build to customize your copy.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .frame(maxWidth: 650)
            .padding()
            .frame(maxWidth: .infinity)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(template.title)
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
        .task {
            do {
                guard let page = PDFDocument(data: try template.data())?.page(at: 0) else {
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
                let document = try await library.importConvertedPDF(.preparedPDF(template.data()), named: template.title)
                complete(document)
            } catch {
                creating = false
                errorMessage = error.localizedDescription
            }
        }
    }
}

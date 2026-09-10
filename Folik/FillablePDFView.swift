import PDFKit
import SwiftUI
import UniformTypeIdentifiers

nonisolated enum FillablePDFPreparation {
    static func prepare(_ data: Data) throws -> OfficePreview {
        let document = try PDFProcessing.document(data)
        return OfficePreview(
            data: data,
            warnings: [
                "The page artwork stays unchanged. Form fields are added separately in the reader.",
                "Review field placement and test the finished copy in the PDF apps your recipients use."
            ],
            pageCount: document.pageCount,
            recoveryNotice: "Fillable copy. Save it, then open Forms to add and arrange fields. Your source PDF remains unchanged."
        )
    }
}

struct FillablePDFView: View {
    var initialURL: URL? = nil
    let complete: (LibraryDocument) -> Void

    @EnvironmentObject private var library: DocumentLibrary
    @Environment(\.dismiss) private var dismiss
    @State private var loadedInitialSource = false
    @State private var showingFiles = false
    @State private var busy = false
    @State private var errorMessage: String?
    @State private var workingCopy: LibraryDocument?
    @State private var worker: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            if let workingCopy {
                ReaderView(item: workingCopy, startInFormBuilder: true, finishForm: complete)
            } else {
                Form {
                    Section {
                        Label("Turn a PDF into a form", systemImage: "rectangle.and.pencil.and.ellipsis")
                            .font(.headline)
                        Text("Choose a PDF or scan from Files. Add fields directly on a separate, autosaved copy. Your source stays unchanged.")
                            .foregroundStyle(.secondary)
                        Button("Choose PDF") { showingFiles = true }
                            .frame(minHeight: 44)
                            .disabled(busy)
                            .accessibilityIdentifier("fillable.choose")
                    }
                    if let errorMessage {
                        Section { ProcessingErrorView(message: errorMessage) }
                    }
                }
                .navigationTitle("Make Fillable Copy")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { worker?.cancel(); dismiss() }
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    if busy {
                        ProcessingStatusView(status: "Creating your working copy…") { worker?.cancel() }
                            .padding().background(.regularMaterial)
                    }
                }
            }
        }
        .interactiveDismissDisabled(busy || workingCopy != nil)
        .fileImporter(isPresented: $showingFiles, allowedContentTypes: [.pdf]) { result in
            switch result {
            case .success(let url): createWorkingCopy(from: url)
            case .failure(let error): errorMessage = error.localizedDescription
            }
        }
        .onDisappear { worker?.cancel() }
        .onAppear {
            guard !loadedInitialSource else { return }
            loadedInitialSource = true
            if let initialURL { createWorkingCopy(from: initialURL) }
        }
    }

    private func createWorkingCopy(from url: URL) {
        guard !busy else { return }
        busy = true
        errorMessage = nil
        worker = Task {
            defer { busy = false }
            do {
                let data = try await Task.detached(priority: .userInitiated) {
                    let data = try PDFConverter.readFile(url, maximumBytes: PDFProcessing.maximumBytes)
                    _ = try PDFProcessing.document(data)
                    return data
                }.cancellableValue
                try Task.checkCancellation()
                workingCopy = try await library.importConvertedPDF(
                    .preparedPDF(data), named: url.deletingPathExtension().lastPathComponent + " Fillable"
                )
            } catch is CancellationError {
            } catch {
                errorMessage = "Folik couldn’t create the working copy. \(error.localizedDescription)"
            }
        }
    }
}

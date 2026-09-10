import PDFKit
import SwiftUI

struct ExportPreviewView: View {
    @ObservedObject var session: DocumentSession
    let mode: DocumentExportMode
    let share: (URL) -> Void
    @State private var preparedURL: URL?
    @State private var previewReady = false
    @State private var pageIndex = 0
    @State private var pageCount = 1
    @State private var handedOff = false
    @State private var error: String?
    @State private var attempt = 0

    var body: some View {
        VStack(spacing: 12) {
            if previewReady, let preparedURL {
                ReadOnlyPDFPreview(url: preparedURL, pageIndex: pageIndex)
                    .accessibilityLabel("Export preview, page \(pageIndex + 1) of \(pageCount)")
                    .accessibilityIdentifier("export.preview.pdf")
                HStack {
                    Button("Previous") { pageIndex -= 1 }.disabled(pageIndex == 0)
                    Spacer()
                    Text("Page \(pageIndex + 1) of \(pageCount)")
                    Spacer()
                    Button("Next") { pageIndex += 1 }.disabled(pageIndex + 1 >= pageCount)
                }.frame(minHeight: 44).padding(.horizontal)
                Text(mode == .flattened ? "Visible entries and annotations are part of the pages in this copy." : "Fields and annotations remain editable in this copy.")
                    .font(.footnote).foregroundStyle(.secondary).padding(.horizontal)
            } else if let error {
                ContentUnavailableView("Couldn’t Prepare Preview", systemImage: "doc", description: Text(error))
                Button("Try Again") { attempt += 1 }.frame(minHeight: 44)
            } else {
                Spacer()
                ProgressView("Preparing your latest changes…")
                Text("You can go back to cancel.").font(.footnote).foregroundStyle(.secondary)
                Spacer()
            }
        }
        .navigationTitle("Preview Copy")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button {
                guard let preparedURL, !handedOff else { return }
                handedOff = true
                share(preparedURL)
            } label: {
                Text("Share PDF").fontWeight(.semibold).frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!previewReady || handedOff)
            .accessibilityIdentifier("export.preview.share")
            .padding().background(.bar)
        }
        .task(id: attempt) {
            error = nil
            do {
                let url = try await session.prepareShare(mode: mode)
                preparedURL = url
                let result = try await Task.detached {
                    guard let document = PDFDocument(url: url), document.pageCount > 0 else { throw CocoaError(.fileReadCorruptFile) }
                    return document.pageCount
                }.value
                try Task.checkCancellation()
                pageCount = result
                previewReady = true
            } catch {
                if let preparedURL { DocumentExporter.removeExport(at: preparedURL); self.preparedURL = nil }
                if !Task.isCancelled { self.error = error.localizedDescription }
            }
        }
        .onDisappear {
            if !handedOff, let preparedURL { DocumentExporter.removeExport(at: preparedURL) }
        }
    }
}

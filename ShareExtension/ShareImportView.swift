import Combine
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class ShareImportModel: ObservableObject {
    enum Phase {
        case loading
        case ready([URL])
        case saving([URL])
        case failed(String)
    }

    @Published private(set) var phase: Phase = .loading
    private weak var extensionContext: NSExtensionContext?
    private var temporaryDirectory: URL?
    private var operationTask: Task<Void, Never>?

    init(extensionContext: NSExtensionContext?) {
        self.extensionContext = extensionContext
        prepare()
    }

    func prepare() {
        operationTask?.cancel()
        cleanup()
        phase = .loading
        operationTask = Task {
            do {
                let directory = try SharedPDFInbox.temporaryDirectory()
                temporaryDirectory = directory
                let providers = pdfProviders()
                guard !providers.isEmpty else { throw SharedPDFInboxError.noPDFs }
                guard providers.count <= SharedPDFInbox.maximumFileCount else {
                    throw SharedPDFInboxError.tooManyFiles
                }
                var files: [URL] = []
                for (index, provider) in providers.enumerated() {
                    try Task.checkCancellation()
                    files.append(try await copyPDF(from: provider, index: index, into: directory))
                }
                let validation = Task.detached(priority: .userInitiated) {
                    try SharedPDFInbox.validate(files)
                }
                try await withTaskCancellationHandler(
                    operation: { try await validation.value },
                    onCancel: { validation.cancel() }
                )
                phase = .ready(files)
            } catch is CancellationError {
                cleanup()
            } catch {
                cleanup()
                phase = .failed(error.localizedDescription)
            }
        }
    }

    func addToFolik(_ files: [URL]) {
        guard case .ready = phase else { return }
        phase = .saving(files)
        operationTask = Task {
            do {
                guard let inbox = SharedPDFInbox.defaultInboxDirectory() else {
                    throw SharedPDFInboxError.unavailable
                }
                let enqueue = Task.detached(priority: .userInitiated) {
                    try SharedPDFInbox.enqueue(files, into: inbox)
                }
                _ = try await withTaskCancellationHandler(
                    operation: { try await enqueue.value },
                    onCancel: { enqueue.cancel() }
                )
                cleanup()
                extensionContext?.completeRequest(returningItems: nil)
            } catch is CancellationError {
                cleanup()
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    func cancel() {
        operationTask?.cancel()
        cleanup()
        extensionContext?.cancelRequest(withError: CocoaError(.userCancelled))
    }

    private func pdfProviders() -> [NSItemProvider] {
        (extensionContext?.inputItems as? [NSExtensionItem] ?? [])
            .flatMap { $0.attachments ?? [] }
            .filter { $0.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) }
    }

    private func copyPDF(from provider: NSItemProvider, index: Int, into directory: URL) async throws -> URL {
        let suggestedName = provider.suggestedName
        return try await withCheckedThrowingContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: UTType.pdf.identifier) { source, error in
                do {
                    if let error { throw error }
                    guard let source else { throw SharedPDFInboxError.noPDFs }
                    let filename = Self.pdfFilename(suggestedName ?? source.lastPathComponent, index: index)
                    let destination = Self.uniqueDestination(named: filename, in: directory)
                    try FileManager.default.copyItem(at: source, to: destination)
                    continuation.resume(returning: destination)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    nonisolated private static func pdfFilename(_ proposed: String, index: Int) -> String {
        let source = URL(fileURLWithPath: proposed).lastPathComponent
        let stem = URL(fileURLWithPath: source).deletingPathExtension().lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let safeStem = stem.isEmpty ? "Shared PDF \(index + 1)" : String(stem.prefix(170))
        return safeStem + ".pdf"
    }

    nonisolated private static func uniqueDestination(named filename: String, in directory: URL) -> URL {
        let first = directory.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: first.path) else { return first }
        let stem = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
        var number = 2
        while true {
            let candidate = directory.appendingPathComponent("\(stem) \(number).pdf")
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            number += 1
        }
    }

    private func cleanup() {
        if let temporaryDirectory { try? FileManager.default.removeItem(at: temporaryDirectory) }
        temporaryDirectory = nil
    }
}

struct ShareImportView: View {
    @ObservedObject var model: ShareImportModel

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label("Private, on-device import", systemImage: "lock.shield")
                    Text("Folik copies these PDFs into its private sharing space. They appear in your library the next time Folik is active.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                content
            }
            .navigationTitle("Add to Folik")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: model.cancel)
                        .frame(minHeight: 44)
                }
            }
            .safeAreaInset(edge: .bottom) { primaryAction }
        }
        .tint(.blue)
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            Section {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Reading shared PDFs…")
                }
                .accessibilityElement(children: .combine)
            }
        case .ready(let files), .saving(let files):
            Section(files.count == 1 ? "PDF" : "\(files.count) PDFs") {
                ForEach(files, id: \.self) { url in
                    Label(url.deletingPathExtension().lastPathComponent, systemImage: "doc.text")
                }
            }
        case .failed(let message):
            Section {
                Label("Couldn’t prepare these PDFs", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(.red)
                Text(message).font(.body)
                Button("Try Again", action: model.prepare)
                    .frame(minHeight: 44)
            }
        }
    }

    @ViewBuilder
    private var primaryAction: some View {
        switch model.phase {
        case .ready(let files):
            Button {
                model.addToFolik(files)
            } label: {
                Label(files.count == 1 ? "Add PDF to Folik" : "Add \(files.count) PDFs to Folik", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .padding()
            .background(.regularMaterial)
            .accessibilityIdentifier("share.addToFolik")
        case .saving:
            HStack(spacing: 12) {
                ProgressView()
                Text("Adding to Folik…")
            }
            .frame(maxWidth: .infinity, minHeight: 50)
            .padding()
            .background(.regularMaterial)
            .accessibilityElement(children: .combine)
        case .loading, .failed:
            EmptyView()
        }
    }
}

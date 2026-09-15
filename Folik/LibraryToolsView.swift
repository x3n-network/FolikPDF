import SwiftUI

nonisolated enum LibraryTool: String, Identifiable, CaseIterable {
    case scan, importPDF, images, documents, text, searchable, fillable, compress, batch, redact, sanitize, protect, compare, sample, templates
    var id: Self { self }

    var title: String {
        switch self {
        case .templates: "Form Templates"
        case .scan: "Scan Document"
        case .importPDF: "Choose PDFs"
        case .images: "Images to PDF"
        case .sample: "Try a Sample Form"
        case .documents: "Documents to PDF"
        case .text: "Text/RTF to PDF"
        case .batch: "Batch to PDF"
        case .searchable: "Make PDF Searchable"
        case .fillable: "Make Fillable Copy"
        case .compress: "Compress PDF"
        case .redact: "Redact PDF"
        case .sanitize: "Inspect & Sanitize"
        case .protect: "Protect PDF"
        case .compare: "Compare PDFs"
        }
    }

    var subtitle: String {
        switch self {
        case .templates: "Start a ready-made form, available offline"
        case .scan: "Capture paper with automatic edge detection"
        case .importPDF: "Add one or more PDFs from Files"
        case .images: "Create an ordered, searchable PDF"
        case .sample: "Practice filling, signing, and sharing"
        case .documents: "Convert DOCX, ODT, DOC, or Pages previews"
        case .text: "Turn plain or rich text into a paginated PDF"
        case .batch: "Prepare separate PDFs or combine several files"
        case .searchable: "Add an on-device OCR text layer"
        case .fillable: "Add editable fields over a scan or PDF"
        case .compress: "Reduce image-heavy file sizes"
        case .redact: "Permanently remove marked information in a new copy"
        case .sanitize: "See what a PDF carries, then make a safer copy"
        case .protect: "Require a password to open a new copy"
        case .compare: "Find text changes between two PDFs on-device"
        }
    }

    var icon: String {
        switch self {
        case .templates: "doc.on.doc"
        case .scan: "doc.viewfinder"
        case .importPDF: "folder"
        case .images: "photo.on.rectangle"
        case .sample: "doc.text"
        case .documents: "doc.richtext"
        case .text: "doc.text"
        case .batch: "square.stack.3d.up"
        case .searchable: "text.viewfinder"
        case .fillable: "list.clipboard"
        case .compress: "arrow.down.right.and.arrow.up.left"
        case .redact: "eye.slash"
        case .sanitize: "checkmark.shield"
        case .protect: "lock.doc"
        case .compare: "arrow.left.arrow.right"
        }
    }
}

nonisolated enum LibraryPDFTool: String, CaseIterable, Identifiable {
    case searchable, fillable, compress, redact, sanitize, protect, compare
    var id: Self { self }
    var title: String {
        switch self {
        case .searchable: "Make PDF Searchable"
        case .fillable: "Make Fillable Copy"
        case .compress: "Compress PDF"
        case .redact: "Redact PDF"
        case .sanitize: "Inspect & Sanitize"
        case .protect: "Protect PDF"
        case .compare: "Compare PDFs"
        }
    }
    var icon: String {
        switch self {
        case .searchable: "text.viewfinder"
        case .fillable: "list.clipboard"
        case .compress: "arrow.down.right.and.arrow.up.left"
        case .redact: "eye.slash"
        case .sanitize: "checkmark.shield"
        case .protect: "lock.doc"
        case .compare: "arrow.left.arrow.right"
        }
    }
}

struct LibraryToolsView: View {
    let canScan: Bool
    let choose: (LibraryTool) -> Void
    @Environment(\.dismiss) private var dismiss
    @AppStorage("folik.recentLibraryTools") private var recentToolNames = ""

    private var recentTools: [LibraryTool] {
        recentToolNames.split(separator: ",").compactMap { LibraryTool(rawValue: String($0)) }
    }

    var body: some View {
        NavigationStack {
            List {
                if !recentTools.isEmpty {
                    Section("Recent") {
                        ForEach(recentTools) { tool in
                            toolRow(tool, identifierPrefix: "tools.recent")
                                .disabled(tool == .scan && !canScan)
                        }
                    }
                }
                Section("Add a document") {
                    toolRow(.templates)
                    toolRow(.scan)
                        .disabled(!canScan)
                    toolRow(.importPDF)
                    toolRow(.images)
                }
                Section("Try Folik") {
                    toolRow(.sample)
                }
                Section("More ways to convert") {
                    toolRow(.documents)
                    toolRow(.text)
                    toolRow(.batch)
                }
                Section("Improve and protect") {
                    toolRow(.searchable)
                    toolRow(.fillable)
                    toolRow(.compress)
                    toolRow(.redact)
                    toolRow(.sanitize)
                    toolRow(.protect)
                    toolRow(.compare)
                }
            }
            .navigationTitle("Add & Tools")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }

    private func toolRow(_ tool: LibraryTool, identifierPrefix: String = "tools") -> some View {
        Button {
            remember(tool)
            choose(tool)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: tool.icon)
                    .font(.title3)
                    .foregroundStyle(FolikTheme.cobalt)
                    .frame(width: 32)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(tool.title).font(.body.weight(.semibold)).foregroundStyle(FolikTheme.ink)
                    Text(tool.subtitle).font(.footnote).foregroundStyle(FolikTheme.mutedInk)
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tool.title)
        .accessibilityHint(tool.subtitle)
        .accessibilityIdentifier("\(identifierPrefix).\(tool.rawValue)")
    }

    private func remember(_ tool: LibraryTool) {
        var values = recentTools.filter { $0 != tool }
        values.insert(tool, at: 0)
        recentToolNames = values.prefix(3).map(\.rawValue).joined(separator: ",")
    }
}

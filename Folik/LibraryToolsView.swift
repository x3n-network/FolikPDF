import SwiftUI

nonisolated enum LibraryTool: String, Identifiable {
    case scan, importPDF, images, documents, text, searchable, fillable, compress, batch, redact, sanitize, protect, compare
    var id: Self { self }
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

    var body: some View {
        NavigationStack {
            List {
                Section("Add a document") {
                    tool(.scan, title: "Scan Document", subtitle: "Capture paper with automatic edge detection", icon: "doc.viewfinder")
                        .disabled(!canScan)
                    tool(.importPDF, title: "Choose PDFs", subtitle: "Add one or more PDFs from Files", icon: "folder")
                    tool(.images, title: "Images to PDF", subtitle: "Create an ordered, searchable PDF", icon: "photo.on.rectangle")
                }
                Section("More ways to convert") {
                    tool(.documents, title: "Documents to PDF", subtitle: "Convert DOCX, ODT, DOC, or Pages previews", icon: "doc.richtext")
                    tool(.text, title: "Text/RTF to PDF", subtitle: "Turn plain or rich text into a paginated PDF", icon: "doc.text")
                    tool(.batch, title: "Batch to PDF", subtitle: "Prepare separate PDFs or combine several files", icon: "square.stack.3d.up")
                }
                Section("Improve and protect") {
                    tool(.searchable, title: "Make PDF Searchable", subtitle: "Add an on-device OCR text layer", icon: "text.viewfinder")
                    tool(.fillable, title: "Make Fillable Copy", subtitle: "Add editable fields over a scan or PDF", icon: "list.clipboard")
                    tool(.compress, title: "Compress PDF", subtitle: "Reduce image-heavy file sizes", icon: "arrow.down.right.and.arrow.up.left")
                    tool(.redact, title: "Redact PDF", subtitle: "Permanently remove marked information in a new copy", icon: "eye.slash")
                    tool(.sanitize, title: "Inspect & Sanitize", subtitle: "See what a PDF carries, then make a safer copy", icon: "checkmark.shield")
                    tool(.protect, title: "Protect PDF", subtitle: "Require a password to open a new copy", icon: "lock.doc")
                    tool(.compare, title: "Compare PDFs", subtitle: "Find text changes between two PDFs on-device", icon: "arrow.left.arrow.right")
                }
            }
            .navigationTitle("Add & Tools")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }

    private func tool(
        _ tool: LibraryTool,
        title: String,
        subtitle: String,
        icon: String
    ) -> some View {
        Button { choose(tool) } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(FolikTheme.cobalt)
                    .frame(width: 32)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.body.weight(.semibold)).foregroundStyle(FolikTheme.ink)
                    Text(subtitle).font(.footnote).foregroundStyle(FolikTheme.mutedInk)
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
    }
}

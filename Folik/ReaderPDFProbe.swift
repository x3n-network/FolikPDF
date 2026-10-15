#if DEBUG
import PDFKit
import Combine

/// Test-only inspection of the actual rendered UIView, never a model-derived continuity claim.
@MainActor
final class ReaderPDFProbe: ObservableObject {
    weak var view: PDFView?
    @Published private(set) var snapshot = "Awaiting PDF viewport"

    func seed() {
        guard let view, let document = view.document, let page = document.page(at: 0) else { return }
        view.autoScales = false
        view.scaleFactor = 1.25
        view.go(to: page)
        if let selection = document.findString("Folik", withOptions: []).first {
            view.setCurrentSelection(selection, animate: false)
        }
        inspect()
    }

    func inspect() {
        guard let view, let document = view.document else { snapshot = "Missing PDF viewport"; return }
        let page = view.currentPage.map { document.index(for: $0) } ?? -1
        snapshot = "view=\(ObjectIdentifier(view)) document=\(ObjectIdentifier(document)) page=\(page) scale=\(String(format: "%.3f", view.scaleFactor)) selection=\(view.currentSelection?.string ?? "nil")"
    }
}
#endif

import PDFKit
import SwiftUI

/// A disposable document copy: preview marks and field locking never touch the source.
struct ReadOnlyPDFPreview: UIViewRepresentable {
    var data: Data? = nil
    var url: URL? = nil
    var pageIndex = 0
    var suggestions: [FormFieldSuggestion] = []
    var selectedIDs: Set<UUID> = []
    var toggle: (UUID) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.document = url.flatMap { PDFDocument(url: $0) } ?? data.flatMap { PDFDocument(data: $0) }
        view.autoScales = true
        view.displayMode = .singlePage
        view.displayDirection = .vertical
        for index in 0..<(view.document?.pageCount ?? 0) {
            guard let page = view.document?.page(at: index) else { continue }
            for annotation in page.annotations {
                if annotation.type == "Widget" { annotation.isReadOnly = true }
                if annotation.type == "Link" { page.removeAnnotation(annotation) }
            }
        }
        context.coordinator.view = view
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        view.addGestureRecognizer(tap)
        return view
    }
    func updateUIView(_ view: PDFView, context: Context) {
        let coordinator = context.coordinator
        coordinator.toggle = toggle
        coordinator.suggestions = suggestions
        for annotation in coordinator.overlays { annotation.page?.removeAnnotation(annotation) }
        coordinator.overlays = []
        guard let document = view.document, let page = document.page(at: pageIndex) else { return }
        if coordinator.pageIndex != pageIndex { view.go(to: page); coordinator.pageIndex = pageIndex }
        for suggestion in suggestions where suggestion.pageIndex == pageIndex {
            let selected = selectedIDs.contains(suggestion.id)
            let overlay = PDFAnnotation(bounds: suggestion.bounds, forType: .square, withProperties: nil)
            overlay.color = selected ? .systemBlue : .darkGray
            overlay.interiorColor = overlay.color.withAlphaComponent(selected ? 0.12 : 0.03)
            let border = PDFBorder(); border.lineWidth = 2
            if !selected { border.style = .dashed; border.dashPattern = [4, 3] }
            overlay.border = border
            page.addAnnotation(overlay)
            coordinator.overlays.append(overlay)
            let tag = PDFAnnotation(bounds: CGRect(x: suggestion.bounds.minX, y: suggestion.bounds.maxY - 15, width: min(80, suggestion.bounds.width), height: 15), forType: .freeText, withProperties: nil)
            tag.contents = selected ? "+" : "−"
            tag.font = .boldSystemFont(ofSize: 10)
            tag.fontColor = .white
            tag.color = overlay.color
            tag.backgroundColor = overlay.color
            page.addAnnotation(tag)
            coordinator.overlays.append(tag)
        }
        view.setNeedsDisplay()
    }

    final class Coordinator: NSObject {
        weak var view: PDFView?
        var pageIndex: Int?
        var overlays: [PDFAnnotation] = []
        var suggestions: [FormFieldSuggestion] = []
        var toggle: (UUID) -> Void = { _ in }
        @objc func tapped(_ gesture: UITapGestureRecognizer) {
            guard let view, let document = view.document else { return }
            let location = gesture.location(in: view)
            guard let page = view.page(for: location, nearest: false) else { return }
            let point = view.convert(location, to: page)
            let index = document.index(for: page)
            if let suggestion = suggestions.last(where: { $0.pageIndex == index && $0.bounds.contains(point) }) {
                toggle(suggestion.id)
            }
        }
    }
}

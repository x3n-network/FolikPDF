import PDFKit
import SwiftUI

private final class LayoutAwarePDFView: PDFView {
    var didLayout: (() -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        didLayout?()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        didLayout?()
    }
}

struct PDFKitView: UIViewRepresentable {
    @ObservedObject var session: DocumentSession

    func makeCoordinator() -> Coordinator {
        Coordinator(session: session)
    }

    func makeUIView(context: Context) -> PDFView {
        let pdfView = context.coordinator.pdfView
        pdfView.document = session.document
        context.coordinator.startObserving()
        return pdfView
    }

    func updateUIView(_ pdfView: PDFView, context: Context) {
        if pdfView.document !== session.document {
            pdfView.document = session.document
            pdfView.autoScales = true
        }

        context.coordinator.updateDrawingState()

        if let command = session.command, command.id != context.coordinator.lastCommandID {
            context.coordinator.lastCommandID = command.id
            context.coordinator.perform(command.action)
        }
    }

    static func dismantleUIView(_ uiView: PDFView, coordinator: Coordinator) {
        coordinator.stopObserving()
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        fileprivate let pdfView = LayoutAwarePDFView()
        private var pendingRestore: (pageIndex: Int, layout: ReaderLayout)?
        private var isRestoreScheduled = false
        var lastCommandID: UUID?

        private let session: DocumentSession
        private var isObserving = false
        private var isPageReportScheduled = false
        private var isSelectionReportScheduled = false
        private var drawingPage: PDFPage?
        private var drawingPoints: [CGPoint] = []
        private var previewPath: UIBezierPath?
        private let previewLayer = CAShapeLayer()
        private let annotationSelectionLayer = CAShapeLayer()
        private let resizeHandleLayer = CAShapeLayer()
        private var transformStartPoint: CGPoint?
        private var transformStartBounds: CGRect?
        private var isResizingAnnotation = false
        private lazy var inkGesture = UIPanGestureRecognizer(target: self, action: #selector(handleInkGesture(_:)))
        private lazy var placementTap = UITapGestureRecognizer(target: self, action: #selector(handlePlacementTap(_:)))
        private lazy var annotationSelectionTap = UITapGestureRecognizer(target: self, action: #selector(handleAnnotationSelectionTap(_:)))
        private lazy var annotationTransformPan = UIPanGestureRecognizer(target: self, action: #selector(handleAnnotationTransformPan(_:)))

        init(session: DocumentSession) {
            self.session = session
            super.init()
            pdfView.didLayout = { [weak self] in self?.restoreAfterLayout() }
            pdfView.backgroundColor = FolikTheme.readerCanvasUIColor
            pdfView.clipsToBounds = true
            pdfView.autoScales = true
            pdfView.displayMode = .singlePageContinuous
            pdfView.displayDirection = .vertical
            pdfView.displaysPageBreaks = true
            pdfView.pageShadowsEnabled = true
            inkGesture.maximumNumberOfTouches = 1
            inkGesture.allowedTouchTypes = [
                NSNumber(value: UITouch.TouchType.direct.rawValue),
                NSNumber(value: UITouch.TouchType.pencil.rawValue)
            ]
            inkGesture.cancelsTouchesInView = true
            inkGesture.delegate = self
            inkGesture.isEnabled = false
            pdfView.addGestureRecognizer(inkGesture)
            placementTap.cancelsTouchesInView = true
            placementTap.delegate = self
            placementTap.isEnabled = false
            pdfView.addGestureRecognizer(placementTap)
            annotationSelectionTap.cancelsTouchesInView = true
            annotationSelectionTap.delegate = self
            annotationSelectionTap.isEnabled = false
            pdfView.addGestureRecognizer(annotationSelectionTap)
            annotationTransformPan.maximumNumberOfTouches = 1
            annotationTransformPan.cancelsTouchesInView = true
            annotationTransformPan.delegate = self
            annotationTransformPan.isEnabled = false
            pdfView.addGestureRecognizer(annotationTransformPan)
            previewLayer.fillColor = UIColor.clear.cgColor
            previewLayer.lineCap = .round
            previewLayer.lineJoin = .round
            pdfView.layer.addSublayer(previewLayer)
            annotationSelectionLayer.fillColor = UIColor.clear.cgColor
            annotationSelectionLayer.strokeColor = FolikTheme.annotationBlue.cgColor
            annotationSelectionLayer.lineWidth = 2
            annotationSelectionLayer.lineDashPattern = [6, 4]
            annotationSelectionLayer.isHidden = true
            pdfView.layer.addSublayer(annotationSelectionLayer)
            resizeHandleLayer.fillColor = FolikTheme.annotationBlue.cgColor
            resizeHandleLayer.strokeColor = UIColor.white.cgColor
            resizeHandleLayer.lineWidth = 2
            resizeHandleLayer.isHidden = true
            pdfView.layer.addSublayer(resizeHandleLayer)
        }

        func startObserving() {
            guard !isObserving else { return }
            isObserving = true
            let center = NotificationCenter.default
            center.addObserver(self, selector: #selector(pageChanged), name: .PDFViewPageChanged, object: pdfView)
            center.addObserver(self, selector: #selector(selectionChanged), name: .PDFViewSelectionChanged, object: pdfView)
            center.addObserver(self, selector: #selector(formAnnotationHit), name: .PDFViewAnnotationHit, object: pdfView)
            center.addObserver(self, selector: #selector(formTextChanged), name: UITextField.textDidChangeNotification, object: nil)
            center.addObserver(self, selector: #selector(formTextChanged), name: UITextField.textDidEndEditingNotification, object: nil)
        }

        func stopObserving() {
            pendingRestore = nil
            NotificationCenter.default.removeObserver(self)
            isObserving = false
        }

        func updateDrawingState() {
            previewLayer.frame = CGRect(origin: .zero, size: pdfView.bounds.size)
            inkGesture.isEnabled = session.isDrawingEnabled
            placementTap.isEnabled = session.annotationPlacement != nil
            annotationSelectionTap.isEnabled = session.isAnnotationEditingEnabled
            annotationTransformPan.isEnabled = session.isAnnotationEditingEnabled
            let allowsDocumentGestures = !session.isDrawingEnabled && !session.isAnnotationEditingEnabled
            if let scrollView = findScrollView(in: pdfView) {
                scrollView.isScrollEnabled = allowsDocumentGestures
                scrollView.pinchGestureRecognizer?.isEnabled = allowsDocumentGestures
            }
            if !session.isDrawingEnabled { resetDrawingPreview() }
            updateAnnotationSelectionOverlay()
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            false
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard gestureRecognizer === annotationTransformPan else { return true }
            let location = gestureRecognizer.location(in: pdfView)
            if
                session.selectedAnnotationCanMove,
                let selected = session.selectedAnnotation,
                let page = pdfView.document?.page(at: selected.pageIndex)
            {
                let viewBounds = annotationViewBounds(selected.annotation, on: page)
                if viewBounds.insetBy(dx: -18, dy: -18).contains(location)
                    || resizeHandleHitArea().contains(location) {
                    return true
                }
            }

            guard
                let document = pdfView.document,
                let page = pdfView.page(for: location, nearest: false)
            else { return false }
            let pagePoint = pdfView.convert(location, to: page)
            guard let annotation = page.annotations.reversed().first(where: {
                session.canMoveAnnotation($0) && $0.bounds.insetBy(dx: -8, dy: -8).contains(pagePoint)
            }) else { return false }

            session.selectAnnotation(annotation, pageIndex: document.index(for: page), navigate: false)
            updateAnnotationSelectionOverlay()
            return true
        }

        @objc private func handleInkGesture(_ gesture: UIPanGestureRecognizer) {
            let viewPoint = gesture.location(in: pdfView)
            switch gesture.state {
            case .began:
                guard let page = pdfView.page(for: viewPoint, nearest: false) else { return }
                drawingPage = page
                drawingPoints = [pdfView.convert(viewPoint, to: page)]
                let path = UIBezierPath()
                path.move(to: viewPoint)
                previewPath = path
                previewLayer.strokeColor = session.inkColor.uiColor.cgColor
                previewLayer.lineWidth = session.inkLineWidth
                previewLayer.path = path.cgPath
            case .changed:
                guard let page = drawingPage, let previewPath else { return }
                drawingPoints.append(pdfView.convert(viewPoint, to: page))
                previewPath.addLine(to: viewPoint)
                previewLayer.path = previewPath.cgPath
            case .ended:
                guard let document = pdfView.document, let page = drawingPage else {
                    resetDrawingPreview()
                    return
                }
                drawingPoints.append(pdfView.convert(viewPoint, to: page))
                let pageIndex = document.index(for: page)
                let points = drawingPoints
                resetDrawingPreview()
                session.addInkAnnotation(pageIndex: pageIndex, points: points)
            case .cancelled, .failed:
                resetDrawingPreview()
            default:
                break
            }
        }

        @objc private func handlePlacementTap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended, let document = pdfView.document else { return }
            let viewPoint = gesture.location(in: pdfView)
            guard let page = pdfView.page(for: viewPoint, nearest: false) else { return }
            session.placeAnnotation(
                pageIndex: document.index(for: page),
                point: pdfView.convert(viewPoint, to: page)
            )
        }

        @objc private func handleAnnotationSelectionTap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended, let document = pdfView.document else { return }
            let viewPoint = gesture.location(in: pdfView)
            guard let page = pdfView.page(for: viewPoint, nearest: false) else {
                session.clearSelectedAnnotation()
                updateAnnotationSelectionOverlay()
                return
            }
            let pagePoint = pdfView.convert(viewPoint, to: page)
            let annotation = page.annotations.reversed().first { $0.bounds.insetBy(dx: -8, dy: -8).contains(pagePoint) }
            if let annotation {
                session.selectAnnotation(annotation, pageIndex: document.index(for: page))
            } else {
                session.clearSelectedAnnotation()
            }
            updateAnnotationSelectionOverlay()
        }

        @objc private func handleAnnotationTransformPan(_ gesture: UIPanGestureRecognizer) {
            guard
                let selected = session.selectedAnnotation,
                let page = pdfView.document?.page(at: selected.pageIndex)
            else { return }
            let viewPoint = gesture.location(in: pdfView)
            let pagePoint = pdfView.convert(viewPoint, to: page)

            switch gesture.state {
            case .began:
                transformStartPoint = pagePoint
                transformStartBounds = selected.annotation.bounds
                isResizingAnnotation = session.selectedAnnotationCanResize && resizeHandleHitArea().contains(viewPoint)
            case .changed:
                guard let startPoint = transformStartPoint, let startBounds = transformStartBounds else { return }
                let delta = CGPoint(x: pagePoint.x - startPoint.x, y: pagePoint.y - startPoint.y)
                let proposedBounds: CGRect
                if isResizingAnnotation {
                    let maximumY = startBounds.maxY
                    proposedBounds = CGRect(
                        x: startBounds.minX,
                        y: min(maximumY - 32, startBounds.minY + delta.y),
                        width: max(32, startBounds.width + delta.x),
                        height: max(32, startBounds.height - delta.y)
                    )
                } else {
                    proposedBounds = startBounds.offsetBy(dx: delta.x, dy: delta.y)
                }
                selected.annotation.bounds = session.clampedBounds(
                    proposedBounds,
                    on: page,
                    minimumSize: isResizingAnnotation
                        ? CGSize(width: 32, height: 32)
                        : CGSize(width: 1, height: 1)
                )
                updateAnnotationSelectionOverlay()
            case .ended:
                if let startBounds = transformStartBounds {
                    session.commitSelectedAnnotationTransform(from: startBounds)
                }
                resetAnnotationTransform()
                updateAnnotationSelectionOverlay()
            case .cancelled, .failed:
                if let startBounds = transformStartBounds {
                    selected.annotation.bounds = startBounds
                }
                resetAnnotationTransform()
                updateAnnotationSelectionOverlay()
            default:
                break
            }
        }

        private func updateAnnotationSelectionOverlay() {
            let overlayFrame = CGRect(origin: .zero, size: pdfView.bounds.size)
            annotationSelectionLayer.frame = overlayFrame
            resizeHandleLayer.frame = overlayFrame
            guard
                session.isAnnotationEditingEnabled,
                let selected = session.selectedAnnotation,
                let page = pdfView.document?.page(at: selected.pageIndex)
            else {
                annotationSelectionLayer.isHidden = true
                resizeHandleLayer.isHidden = true
                return
            }
            let viewBounds = annotationViewBounds(selected.annotation, on: page)
            annotationSelectionLayer.path = UIBezierPath(roundedRect: viewBounds.insetBy(dx: -3, dy: -3), cornerRadius: 5).cgPath
            annotationSelectionLayer.isHidden = false
            if session.selectedAnnotationCanResize {
                let handleBounds = CGRect(x: viewBounds.maxX - 8, y: viewBounds.maxY - 8, width: 16, height: 16)
                resizeHandleLayer.path = UIBezierPath(roundedRect: handleBounds, cornerRadius: 4).cgPath
                resizeHandleLayer.isHidden = false
            } else {
                resizeHandleLayer.isHidden = true
            }
        }

        private func resizeHandleHitArea() -> CGRect {
            guard let path = resizeHandleLayer.path else { return .null }
            return path.boundingBox.insetBy(dx: -14, dy: -14)
        }

        private func annotationViewBounds(_ annotation: PDFAnnotation, on page: PDFPage) -> CGRect {
            let convertedBounds = pdfView.convert(annotation.bounds, from: page)
            let canvasOriginInWindow = pdfView.convert(pdfView.bounds.origin, to: nil)
            return convertedBounds.offsetBy(
                dx: -canvasOriginInWindow.x - pdfView.safeAreaInsets.left,
                dy: -canvasOriginInWindow.y - pdfView.safeAreaInsets.top
            ).standardized
        }

        private func resetAnnotationTransform() {
            transformStartPoint = nil
            transformStartBounds = nil
            isResizingAnnotation = false
        }

        private func resetDrawingPreview() {
            drawingPage = nil
            drawingPoints = []
            previewPath = nil
            previewLayer.path = nil
        }

        private func findScrollView(in view: UIView) -> UIScrollView? {
            if let scrollView = view as? UIScrollView { return scrollView }
            for subview in view.subviews {
                if let scrollView = findScrollView(in: subview) { return scrollView }
            }
            return nil
        }

        @objc private func pageChanged() {
            guard pendingRestore == nil, !isPageReportScheduled else { return }
            isPageReportScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isPageReportScheduled = false
                guard self.pendingRestore == nil, self.isObserving else { return }
                self.session.reportPage(self.pdfView.currentPage)
            }
        }

        @objc private func selectionChanged() {
            guard !isSelectionReportScheduled else { return }
            isSelectionReportScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isSelectionReportScheduled = false
                self.session.reportSelection(self.pdfView.currentSelection)
            }
        }

        @objc private func formAnnotationHit() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                self?.session.noteFormEditing()
            }
        }

        @objc private func formTextChanged(_ notification: Notification) {
            guard let field = notification.object as? UIView, field.isDescendant(of: pdfView) else { return }
            session.noteFormEditing()
        }

        func perform(_ action: PDFReaderCommand.Action) {
            switch action {
            case .goToPage(let index):
                if let page = pdfView.document?.page(at: index) { pdfView.go(to: page) }
            case .goToSelection(let selection):
                pdfView.highlightedSelections = [selection]
                pdfView.setCurrentSelection(selection, animate: true)
                pdfView.go(to: selection)
            case .goToDestination(let destination):
                pdfView.go(to: destination)
            case .goToAnnotation(let annotation, let pageIndex):
                if let page = pdfView.document?.page(at: pageIndex) {
                    pdfView.go(to: annotation.bounds.insetBy(dx: -18, dy: -18), on: page)
                    updateAnnotationSelectionOverlay()
                }
            case .previousPage:
                pdfView.goToPreviousPage(nil)
            case .nextPage:
                pdfView.goToNextPage(nil)
            case .fitPage:
                pdfView.autoScales = true
            case .setLayout(let layout):
                setLayout(layout, returningTo: pdfView.currentPage)
            case .restore(let pageIndex, let layout):
                pendingRestore = (pageIndex, layout)
                restoreAfterLayout()
            case .save:
                pdfView.endEditing(true)
                DispatchQueue.main.async { [weak self] in
                    self?.session.noteFormEditing()
                    self?.session.persistChanges()
                }
            }
        }

        private func restoreAfterLayout() {
            guard pendingRestore != nil, !isRestoreScheduled,
                  pdfView.window != nil, pdfView.bounds.width > 0, pdfView.bounds.height > 0 else { return }
            isRestoreScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isRestoreScheduled = false
                guard self.isObserving, let restore = self.pendingRestore,
                      self.pdfView.window != nil else { return }
                self.pdfView.layoutIfNeeded()
                self.setLayout(restore.layout, returningTo: self.pdfView.document?.page(at: restore.pageIndex))
                self.pendingRestore = nil
                self.pageChanged()
            }
        }

        private func setLayout(_ layout: ReaderLayout, returningTo currentPage: PDFPage?) {
                switch layout {
                case .continuous:
                    pdfView.displayMode = .singlePageContinuous
                    pdfView.displayDirection = .vertical
                case .singlePage:
                    pdfView.displayMode = .singlePage
                    pdfView.displayDirection = .horizontal
                case .twoUp:
                    pdfView.displayMode = .twoUpContinuous
                    pdfView.displayDirection = .vertical
                }
                pdfView.autoScales = true
                pdfView.layoutDocumentView()
                if let currentPage { pdfView.go(to: currentPage) }
        }
    }
}

import Combine
import PDFKit
import SwiftUI

nonisolated enum ReaderLayout: String, CaseIterable, Identifiable, Sendable {
    case continuous
    case singlePage
    case twoUp

    var id: Self { self }
    var title: String {
        switch self {
        case .continuous: "Continuous"
        case .singlePage: "Single Page"
        case .twoUp: "Two Page"
        }
    }
    var icon: String {
        switch self {
        case .continuous: "rectangle.split.1x2"
        case .singlePage: "rectangle.portrait"
        case .twoUp: "rectangle.split.2x1"
        }
    }
}

enum MarkupKind: String, CaseIterable, Identifiable {
    case highlight
    case underline
    case strikeOut

    var id: Self { self }
    var title: String {
        switch self {
        case .highlight: "Highlight"
        case .underline: "Underline"
        case .strikeOut: "Strike Out"
        }
    }
    var icon: String {
        switch self {
        case .highlight: "highlighter"
        case .underline: "underline"
        case .strikeOut: "strikethrough"
        }
    }
    var subtype: PDFAnnotationSubtype {
        switch self {
        case .highlight: .highlight
        case .underline: .underline
        case .strikeOut: .strikeOut
        }
    }
    var color: UIColor {
        switch self {
        case .highlight: FolikTheme.annotationYellow
        case .underline: FolikTheme.annotationBlue
        case .strikeOut: FolikTheme.annotationRed
        }
    }
}

enum InkColor: String, CaseIterable, Identifiable {
    case blue
    case red
    case black
    case yellow

    var id: Self { self }
    var title: String { rawValue.capitalized }
    var uiColor: UIColor {
        switch self {
        case .blue: FolikTheme.annotationBlue
        case .red: FolikTheme.annotationRed
        case .black: UIColor.label.withAlphaComponent(0.9)
        case .yellow: UIColor(red: 0.95, green: 0.63, blue: 0.08, alpha: 0.92)
        }
    }
    var color: Color { Color(uiColor: uiColor) }
}

enum AnnotationStamp: String, CaseIterable, Identifiable {
    case approved = "Approved"
    case draft = "Draft"
    case confidential = "Confidential"
    case final = "Final"

    var id: Self { self }

    var title: String {
        switch self {
        case .approved: "Approved"
        case .draft: "Draft"
        case .confidential: "Confidential"
        case .final: "Final"
        }
    }

    var icon: String {
        switch self {
        case .approved: "checkmark.seal"
        case .draft: "doc.badge.clock"
        case .confidential: "lock.shield"
        case .final: "checkmark.circle"
        }
    }

    var color: UIColor {
        switch self {
        case .approved: FolikTheme.annotationBlue
        case .draft: UIColor.systemOrange
        case .confidential: FolikTheme.annotationRed
        case .final: UIColor.systemPurple
        }
    }
}

struct DocumentAnnotation: Identifiable {
    let id: String
    let annotation: PDFAnnotation
    let pageIndex: Int
    let title: String
    let excerpt: String
    let icon: String
    let color: UIColor
}

enum AnnotationPlacementKind: String, CaseIterable, Identifiable {
    case note
    case textBox
    case rectangle
    case circle
    case stamp
    case signature
    case initials

    var id: Self { self }
    var title: String {
        switch self {
        case .note: "Note"
        case .textBox: "Text box"
        case .rectangle: "Rectangle"
        case .circle: "Circle"
        case .stamp: "Stamp"
        case .signature: "Signature"
        case .initials: "Initials"
        }
    }
    var icon: String {
        switch self {
        case .note: "note.text"
        case .textBox: "text.bubble"
        case .rectangle: "rectangle"
        case .circle: "circle"
        case .stamp: "seal"
        case .signature: "signature"
        case .initials: "character.cursor.ibeam"
        }
    }
    var requiresText: Bool { self == .note || self == .textBox }
    var requiresStamp: Bool { self == .stamp }
    var requiresSignatureAsset: Bool { self == .signature || self == .initials }
    var signatureKind: SignatureKind? {
        switch self {
        case .signature: .signature
        case .initials: .initials
        default: nil
        }
    }
}

struct AnnotationPlacement: Equatable {
    let kind: AnnotationPlacementKind
    let text: String
    let signatureAsset: SignatureAsset?
    let stamp: AnnotationStamp?

    var title: String { stamp?.title ?? kind.title }
    var icon: String { stamp?.icon ?? kind.icon }
}

private struct AnnotationGeometry {
    let bounds: CGRect
    let paths: [UIBezierPath]
}

private struct AnnotationStyle {
    let color: UIColor
    let interiorColor: UIColor?
    let fontColor: UIColor?
    let lineWidth: CGFloat?
}

private enum AnnotationHistoryAction {
    case added(PDFAnnotation, pageIndex: Int)
    case removed(PDFAnnotation, pageIndex: Int)
    case transformed(PDFAnnotation, pageIndex: Int, from: AnnotationGeometry, to: AnnotationGeometry)
    case styled(PDFAnnotation, pageIndex: Int, from: AnnotationStyle, to: AnnotationStyle)
}

struct SearchMatch: Identifiable {
    let id = UUID()
    let selection: PDFSelection
    let pageIndex: Int
    let excerpt: String
}

enum FormFieldKind: Equatable {
    case text
    case multilineText
    case checkbox
    case radio
    case choice
    case signature
    case pushButton
    case unknown

    var title: String {
        switch self {
        case .text: "Text field"
        case .multilineText: "Multiline text"
        case .checkbox: "Checkbox"
        case .radio: "Radio option"
        case .choice: "Choice"
        case .signature: "Signature"
        case .pushButton: "Button"
        case .unknown: "Unsupported field"
        }
    }

    var supportsEditing: Bool {
        switch self {
        case .text, .multilineText, .checkbox, .radio, .choice: true
        case .signature, .pushButton, .unknown: false
        }
    }
}

struct FormField: Identifiable {
    let id: String
    let annotation: PDFAnnotation
    let pageIndex: Int
    let title: String
    let logicalID: String
    let kind: FormFieldKind
    let value: String
    let isReadOnly: Bool
    let isSelected: Bool
    let isRequired: Bool

    var isFilled: Bool {
        switch kind {
        case .checkbox, .radio: isSelected
        case .text, .multilineText, .choice:
            !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .signature, .pushButton, .unknown: false
        }
    }

    var isEditable: Bool { !isReadOnly && kind.supportsEditing }

    var limitation: String? {
        switch kind {
        case .signature: "Use Annotations > Add > Signature for a visual signature. Certificate signing isn't supported."
        case .pushButton, .unknown: "This field type is not supported"
        default: isReadOnly ? "Read only" : nil
        }
    }

    var statusText: String {
        if let limitation { return limitation }
        switch kind {
        case .checkbox: return isSelected ? "Checked" : "Not checked"
        case .radio:
            let option = annotation.buttonWidgetStateString.trimmingCharacters(in: .whitespacesAndNewlines)
            return option.isEmpty ? (isSelected ? "Selected" : "Not selected") : "\(option) · \(isSelected ? "Selected" : "Not selected")"
        case .text, .multilineText, .choice:
            let summary = value
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            guard !summary.isEmpty else { return "Empty" }
            return summary.count > 56 ? "\(summary.prefix(55))…" : summary
        case .signature, .pushButton, .unknown: return limitation ?? "Unsupported"
        }
    }
}

private struct FormFieldSnapshot: Equatable {
    let stringValue: String
    let buttonState: Int
}

struct OutlineEntry: Identifiable {
    let id = UUID()
    let title: String
    let level: Int
    let destination: PDFDestination
}

struct PDFReaderCommand {
    let id = UUID()
    let action: Action

    enum Action {
        case goToPage(Int)
        case goToSelection(PDFSelection)
        case goToDestination(PDFDestination)
        case goToAnnotation(PDFAnnotation, pageIndex: Int)
        case previousPage
        case nextPage
        case fitPage
        case setLayout(ReaderLayout)
        case restore(pageIndex: Int, layout: ReaderLayout)
        case save
    }
}

@MainActor
final class DocumentSession: NSObject, ObservableObject, PDFDocumentDelegate {
    let item: LibraryDocument
    @Published private(set) var document: PDFDocument?
    @Published private(set) var pageIndex = 0
    @Published private(set) var bookmarkedPageIndices: Set<Int> = []
    @Published private(set) var searchMatches: [SearchMatch] = []
    @Published private(set) var searchQuery = ""
    @Published private(set) var selectedSearchMatchIndex: Int?
    @Published private(set) var searchedPageCount = 0
    @Published private(set) var outlineEntries: [OutlineEntry] = []
    @Published private(set) var annotations: [DocumentAnnotation] = []
    @Published private(set) var formFields: [FormField] = []
    @Published private(set) var hasTextSelection = false
    @Published private(set) var isSearching = false
    @Published private(set) var isModified = false
    @Published private(set) var isLocked = false
    @Published private(set) var canFillForms = false
    @Published private(set) var formCompatibilityNotice: String?
    @Published private(set) var canUndoAnnotation = false
    @Published private(set) var canRedoAnnotation = false
    @Published var isDrawingEnabled = false
    @Published private(set) var annotationPlacement: AnnotationPlacement?
    @Published private(set) var isAnnotationEditingEnabled = false
    @Published private(set) var selectedAnnotation: DocumentAnnotation?
    @Published private(set) var savedSignature: SignatureAsset?
    @Published private(set) var savedInitials: SignatureAsset?
    @Published var inkColor: InkColor = .blue
    @Published var inkLineWidth: CGFloat = 3
    @Published var layout: ReaderLayout = .continuous
    @Published var command: PDFReaderCommand?
    @Published var errorMessage: String?

    private var currentSelection: PDFSelection?
    private var savedFormValues: [String: FormFieldSnapshot] = [:]
    private var lastVisitedFormFieldLogicalID: String?
    private var annotationUndoStack: [AnnotationHistoryAction] = []
    private var annotationRedoStack: [AnnotationHistoryAction] = []
    private let signatureStore: SignatureStore
    private let bookmarkStore: BookmarkStore
    private let readerStateStore: ReaderStateStore

    init(
        item: LibraryDocument,
        signatureStore: SignatureStore? = nil,
        bookmarkStore: BookmarkStore? = nil,
        readerStateStore: ReaderStateStore? = nil
    ) {
        self.item = item
        self.signatureStore = signatureStore ?? SignatureStore()
        self.bookmarkStore = bookmarkStore ?? BookmarkStore()
        self.readerStateStore = readerStateStore ?? ReaderStateStore()
        super.init()
        loadSavedSignatures()
        loadDocument()
        let readerState = self.readerStateStore.state(for: item.url, pageCount: pageCount)
        pageIndex = readerState.pageIndex
        layout = readerState.layout
        bookmarkedPageIndices = self.bookmarkStore.bookmarks(for: item.url, pageCount: pageCount)
        if !isLocked {
            command = PDFReaderCommand(action: .restore(pageIndex: pageIndex, layout: layout))
        }
    }

    var pageCount: Int { document?.pageCount ?? item.pageCount }
    var pageLabel: String { pageCount > 0 ? "\(pageIndex + 1) of \(pageCount)" : "No pages" }
    var isCurrentPageBookmarked: Bool { bookmarkedPageIndices.contains(pageIndex) }
    var searchProgress: Double {
        guard pageCount > 0 else { return 0 }
        return min(1, Double(searchedPageCount) / Double(pageCount))
    }
    var searchPositionLabel: String {
        guard let selectedSearchMatchIndex, !searchMatches.isEmpty else {
            return searchMatches.isEmpty ? "No results" : "\(searchMatches.count) results"
        }
        return "\(selectedSearchMatchIndex + 1) of \(searchMatches.count)"
    }
    var formFieldCount: Int { Set(formFields.map(\.logicalID)).count }
    var fillableFormFieldCount: Int {
        Set(formFields.filter(\.isEditable).map(\.logicalID)).count
    }
    var completedFormFieldCount: Int {
        Dictionary(grouping: formFields, by: \.logicalID).values.filter { group in
            group.contains(where: \.isEditable) && group.contains(where: \.isFilled)
        }.count
    }
    var requiredFormFieldCount: Int {
        Dictionary(grouping: formFields, by: \.logicalID).values.filter { group in
            group.contains { $0.isEditable && $0.isRequired }
        }.count
    }
    var remainingRequiredFormFieldCount: Int {
        Dictionary(grouping: formFields, by: \.logicalID).values.filter { group in
            group.contains { $0.isEditable && $0.isRequired } && !group.contains(where: \.isFilled)
        }.count
    }
    var incompleteFormFieldCount: Int { max(0, fillableFormFieldCount - completedFormFieldCount) }

    func unlock(with password: String) -> Bool {
        guard let document, document.unlock(withPassword: password) else { return false }
        isLocked = false
        outlineEntries = Self.flattenOutline(document.outlineRoot)
        configureForms(in: document)
        refreshAnnotations()
        command = PDFReaderCommand(action: .restore(pageIndex: pageIndex, layout: layout))
        return true
    }

    func goToPage(_ index: Int) {
        guard pageCount > 0 else { return }
        command = PDFReaderCommand(action: .goToPage(max(0, min(index, pageCount - 1))))
    }

    func toggleCurrentPageBookmark() {
        guard pageIndex >= 0, pageIndex < pageCount else { return }
        if isCurrentPageBookmarked {
            bookmarkedPageIndices.remove(pageIndex)
        } else {
            bookmarkedPageIndices.insert(pageIndex)
        }
        bookmarkStore.save(bookmarkedPageIndices, for: item.url)
    }

    func clearBookmarks() {
        bookmarkedPageIndices.removeAll()
        bookmarkStore.save([], for: item.url)
    }

    func goToMatch(_ match: SearchMatch) {
        selectedSearchMatchIndex = searchMatches.firstIndex { $0.id == match.id }
        command = PDFReaderCommand(action: .goToSelection(match.selection))
    }

    func moveToSearchMatch(offset: Int) {
        guard !searchMatches.isEmpty else { return }
        let current = selectedSearchMatchIndex ?? (offset > 0 ? -1 : 0)
        let index = (current + offset + searchMatches.count) % searchMatches.count
        selectedSearchMatchIndex = index
        command = PDFReaderCommand(action: .goToSelection(searchMatches[index].selection))
    }

    func goToFormField(_ field: FormField) {
        lastVisitedFormFieldLogicalID = field.logicalID
        command = PDFReaderCommand(action: .goToAnnotation(field.annotation, pageIndex: field.pageIndex))
    }

    func goToAnnotation(_ item: DocumentAnnotation) {
        command = PDFReaderCommand(action: .goToAnnotation(item.annotation, pageIndex: item.pageIndex))
    }

    func setDrawingEnabled(_ enabled: Bool) {
        isDrawingEnabled = enabled
        if enabled {
            annotationPlacement = nil
            finishAnnotationEditing()
            command = PDFReaderCommand(action: .fitPage)
        }
    }

    func beginAnnotationPlacement(_ kind: AnnotationPlacementKind, text: String = "") {
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            (!kind.requiresText || !normalizedText.isEmpty),
            !kind.requiresSignatureAsset,
            !kind.requiresStamp
        else { return }
        isDrawingEnabled = false
        finishAnnotationEditing()
        annotationPlacement = AnnotationPlacement(
            kind: kind,
            text: normalizedText,
            signatureAsset: nil,
            stamp: nil
        )
    }

    func beginStampPlacement(_ stamp: AnnotationStamp) {
        isDrawingEnabled = false
        finishAnnotationEditing()
        annotationPlacement = AnnotationPlacement(kind: .stamp, text: "", signatureAsset: nil, stamp: stamp)
    }

    func beginSignaturePlacement(_ asset: SignatureAsset) {
        guard asset.isValid else { return }
        isDrawingEnabled = false
        finishAnnotationEditing()
        annotationPlacement = AnnotationPlacement(
            kind: asset.kind == .signature ? .signature : .initials,
            text: asset.typedText ?? "",
            signatureAsset: asset,
            stamp: nil
        )
    }

    func savedSignatureAsset(for kind: SignatureKind) -> SignatureAsset? {
        kind == .signature ? savedSignature : savedInitials
    }

    func saveSignatureAsset(_ asset: SignatureAsset) {
        guard signatureStore.save(asset) else {
            errorMessage = "Folik couldn’t securely save this \(asset.kind.title.lowercased())."
            return
        }
        if asset.kind == .signature { savedSignature = asset } else { savedInitials = asset }
    }

    func deleteSavedSignature(for kind: SignatureKind) {
        guard signatureStore.delete(kind) else {
            errorMessage = "Folik couldn’t remove the saved \(kind.title.lowercased())."
            return
        }
        if kind == .signature { savedSignature = nil } else { savedInitials = nil }
    }

    func cancelAnnotationPlacement() {
        annotationPlacement = nil
    }

    func beginAnnotationEditing() {
        isDrawingEnabled = false
        annotationPlacement = nil
        selectedAnnotation = nil
        isAnnotationEditingEnabled = true
        command = PDFReaderCommand(action: .fitPage)
    }

    func finishAnnotationEditing() {
        selectedAnnotation = nil
        isAnnotationEditingEnabled = false
    }

    func selectAnnotation(_ annotation: PDFAnnotation, pageIndex: Int, navigate: Bool = true) {
        guard isAnnotationEditingEnabled else { return }
        selectedAnnotation = annotations.first {
            $0.pageIndex == pageIndex && $0.annotation === annotation
        }
        if selectedAnnotation != nil, navigate {
            command = PDFReaderCommand(action: .goToAnnotation(annotation, pageIndex: pageIndex))
        }
    }

    func clearSelectedAnnotation() {
        selectedAnnotation = nil
    }

    var selectedAnnotationCanResize: Bool {
        guard let type = selectedAnnotation?.annotation.type?.lowercased() else { return false }
        return ["freetext", "square", "circle", "stamp", "ink"].contains(type)
    }

    var selectedAnnotationCanMove: Bool {
        guard let annotation = selectedAnnotation?.annotation else { return false }
        return canMoveAnnotation(annotation)
    }

    var selectedAnnotationCanChangeColor: Bool {
        guard let type = selectedAnnotation?.annotation.type?.lowercased() else { return false }
        return ["highlight", "underline", "strikeout", "ink", "text", "freetext", "square", "circle", "line", "stamp"]
            .contains(type)
    }

    var selectedAnnotationCanChangeLineWidth: Bool {
        guard let type = selectedAnnotation?.annotation.type?.lowercased() else { return false }
        return ["ink", "square", "circle", "line"].contains(type)
    }

    var selectedAnnotationLineWidth: CGFloat? {
        guard selectedAnnotationCanChangeLineWidth else { return nil }
        return selectedAnnotation?.annotation.border?.lineWidth
    }

    func canMoveAnnotation(_ annotation: PDFAnnotation) -> Bool {
        guard let type = annotation.type?.lowercased() else { return false }
        return ["text", "freetext", "square", "circle", "line", "stamp", "ink"].contains(type)
    }

    func selectedAnnotationUsesColor(_ color: InkColor) -> Bool {
        guard let annotationColor = selectedAnnotation?.annotation.color else { return false }
        return Self.colorsMatch(annotationColor, color.uiColor)
    }

    func setSelectedAnnotationColor(_ color: InkColor) {
        guard
            selectedAnnotationCanChangeColor,
            !selectedAnnotationUsesColor(color),
            let selectedAnnotation
        else { return }
        let annotation = selectedAnnotation.annotation
        let originalStyle = annotationStyle(for: annotation)
        annotation.color = color.uiColor

        switch annotation.type?.lowercased() {
        case "square", "circle":
            annotation.interiorColor = nil
        case "freetext":
            annotation.fontColor = color.uiColor
        default:
            break
        }

        let updatedStyle = annotationStyle(for: annotation)
        recordAnnotationAction(.styled(
            annotation,
            pageIndex: selectedAnnotation.pageIndex,
            from: originalStyle,
            to: updatedStyle
        ))
        finishAnnotationStyleChange()
    }

    func setSelectedAnnotationLineWidth(_ lineWidth: CGFloat) {
        guard
            selectedAnnotationCanChangeLineWidth,
            let selectedAnnotation,
            lineWidth > 0,
            abs((selectedAnnotation.annotation.border?.lineWidth ?? 0) - lineWidth) > 0.01
        else { return }
        let annotation = selectedAnnotation.annotation
        let originalStyle = annotationStyle(for: annotation)
        let border = annotation.border ?? PDFBorder()
        border.lineWidth = lineWidth
        annotation.border = border
        let updatedStyle = annotationStyle(for: annotation)
        recordAnnotationAction(.styled(
            annotation,
            pageIndex: selectedAnnotation.pageIndex,
            from: originalStyle,
            to: updatedStyle
        ))
        finishAnnotationStyleChange()
    }

    func commitSelectedAnnotationTransform(from originalBounds: CGRect) {
        guard
            let selectedAnnotation,
            selectedAnnotation.annotation.bounds != originalBounds
        else { return }
        let originalGeometry = AnnotationGeometry(
            bounds: originalBounds,
            paths: copiedPaths(from: selectedAnnotation.annotation)
        )
        if selectedAnnotation.annotation.type?.lowercased() == "ink" {
            let transformedPaths = transformedPaths(
                originalGeometry.paths,
                from: originalBounds,
                to: selectedAnnotation.annotation.bounds
            )
            replacePaths(on: selectedAnnotation.annotation, with: transformedPaths)
        }
        let updatedGeometry = AnnotationGeometry(
            bounds: selectedAnnotation.annotation.bounds,
            paths: copiedPaths(from: selectedAnnotation.annotation)
        )
        recordAnnotationAction(.transformed(
            selectedAnnotation.annotation,
            pageIndex: selectedAnnotation.pageIndex,
            from: originalGeometry,
            to: updatedGeometry
        ))
        finishAnnotationGeometryChange()
    }

    func moveSelectedAnnotation(horizontal: CGFloat, vertical: CGFloat) {
        guard
            selectedAnnotationCanMove,
            let selectedAnnotation,
            let page = document?.page(at: selectedAnnotation.pageIndex)
        else { return }
        let originalBounds = selectedAnnotation.annotation.bounds
        var proposedBounds = originalBounds
        proposedBounds.origin.x += horizontal
        proposedBounds.origin.y += vertical
        selectedAnnotation.annotation.bounds = clampedBounds(proposedBounds, on: page)
        commitSelectedAnnotationTransform(from: originalBounds)
    }

    func resizeSelectedAnnotation(by amount: CGFloat) {
        guard
            selectedAnnotationCanResize,
            let selectedAnnotation,
            let page = document?.page(at: selectedAnnotation.pageIndex)
        else { return }
        let originalBounds = selectedAnnotation.annotation.bounds
        let proposedBounds = originalBounds.insetBy(dx: -amount, dy: -amount)
        selectedAnnotation.annotation.bounds = clampedBounds(
            proposedBounds,
            on: page,
            minimumSize: CGSize(width: 32, height: 32)
        )
        commitSelectedAnnotationTransform(from: originalBounds)
    }

    func deleteSelectedAnnotation() {
        guard let selectedAnnotation else { return }
        deleteAnnotation(selectedAnnotation)
        self.selectedAnnotation = nil
    }

    func placeAnnotationAtCurrentPageCenter() {
        guard let page = document?.page(at: pageIndex) else { return }
        let bounds = page.bounds(for: .cropBox)
        placeAnnotation(pageIndex: pageIndex, point: CGPoint(x: bounds.midX, y: bounds.midY))
    }

    func goToNextIncompleteFormField() {
        let groups = Dictionary(grouping: formFields, by: \.logicalID)
        var seenLogicalIDs = Set<String>()
        let representatives = formFields.filter { field in
            field.isEditable && seenLogicalIDs.insert(field.logicalID).inserted
        }
        let incomplete = representatives.filter { representative in
            guard let group = groups[representative.logicalID] else { return false }
            return !group.contains(where: \.isFilled)
        }
        let required = incomplete.filter { representative in
            groups[representative.logicalID]?.contains(where: \.isRequired) == true
        }
        let candidates = required.isEmpty ? incomplete : required
        guard !candidates.isEmpty else { return }

        let next: FormField
        if let lastVisitedFormFieldLogicalID,
           let index = candidates.firstIndex(where: { $0.logicalID == lastVisitedFormFieldLogicalID }) {
            next = candidates[(index + 1) % candidates.count]
        } else {
            next = candidates[0]
        }
        goToFormField(next)
    }

    func goToOutline(_ entry: OutlineEntry) {
        command = PDFReaderCommand(action: .goToDestination(entry.destination))
    }

    func previousPage() { command = PDFReaderCommand(action: .previousPage) }
    func nextPage() { command = PDFReaderCommand(action: .nextPage) }
    func fitPage() { command = PDFReaderCommand(action: .fitPage) }

    func setLayout(_ layout: ReaderLayout) {
        guard self.layout != layout else { return }
        self.layout = layout
        saveReaderState()
        command = PDFReaderCommand(action: .setLayout(layout))
    }

    func search(for query: String) {
        guard let document else { return }
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        searchQuery = normalized
        document.cancelFindString()
        searchMatches = []
        selectedSearchMatchIndex = nil
        searchedPageCount = 0
        guard !normalized.isEmpty else {
            isSearching = false
            return
        }
        isSearching = true
        document.beginFindString(normalized, withOptions: .caseInsensitive)
    }

    func didMatchString(_ instance: PDFSelection) {
        guard let document, let page = instance.pages.first else { return }
        let excerpt = instance.string?
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let matchBounds = instance.bounds(for: page)
        let lineText = page.selectionForLine(
            at: CGPoint(x: matchBounds.midX, y: matchBounds.midY)
        )?.string
        let contextualExcerpt = lineText?
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        searchMatches.append(SearchMatch(
            selection: instance,
            pageIndex: document.index(for: page),
            excerpt: contextualExcerpt?.nilIfEmpty ?? excerpt?.nilIfEmpty ?? "Match"
        ))
        if selectedSearchMatchIndex == nil { selectedSearchMatchIndex = 0 }
    }

    func documentDidEndPageFind(_ notification: Notification) {
        guard let pageIndex = notification.userInfo?[PDFDocumentPageIndexKey] as? NSNumber else { return }
        searchedPageCount = max(searchedPageCount, pageIndex.intValue + 1)
    }

    func documentDidEndDocumentFind(_ notification: Notification) {
        searchedPageCount = pageCount
        isSearching = false
    }

    func noteFormEditing() {
        guard !formFields.isEmpty else { return }
        isModified = true
        refreshFormState(markModified: true)
    }

    func requestSave() {
        command = PDFReaderCommand(action: .save)
    }

    func persistChanges() {
        guard let document, isModified else { return }
        refreshFormState(markModified: true)
        if document.write(to: item.url) {
            savedFormValues = currentFormValues()
            refreshFormState(markModified: false)
            refreshAnnotations()
            isModified = false
        } else {
            errorMessage = "Your changes are visible, but Folik couldn’t save them to this PDF."
        }
    }

    func revertFormChanges() {
        guard let document else { return }
        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            for (annotationIndex, annotation) in page.annotations.enumerated() where annotation.type == "Widget" {
                let key = Self.formFieldID(pageIndex: pageIndex, annotationIndex: annotationIndex, annotation: annotation)
                guard let snapshot = savedFormValues[key] else { continue }
                annotation.widgetStringValue = snapshot.stringValue
                Self.restoreButtonState(snapshot.buttonState, to: annotation)
            }
        }
        isModified = false
        refreshFormState(markModified: false)
    }

    func refreshFormState(markModified: Bool) {
        guard let document else { return }
        let previousValues = currentFormValues()
        formFields = Self.formFields(in: document)
        if markModified, previousValues != currentFormValues() { isModified = true }
    }

    func applyMarkup(_ kind: MarkupKind) {
        guard document != nil, let selection = currentSelection else { return }
        var addedAnnotation = false
        for line in selection.selectionsByLine() {
            for page in line.pages {
                let bounds = line.bounds(for: page)
                guard !bounds.isEmpty else { continue }
                let annotation = PDFAnnotation(bounds: bounds, forType: kind.subtype, withProperties: nil)
                annotation.color = kind.color
                page.addAnnotation(annotation)
                if let document {
                    recordAnnotationAction(.added(annotation, pageIndex: document.index(for: page)))
                }
                addedAnnotation = true
            }
        }

        guard addedAnnotation else { return }
        isModified = true
        refreshAnnotations()
        persistChanges()
    }

    func addInkAnnotation(pageIndex: Int, points: [CGPoint]) {
        guard
            points.count > 1,
            let document,
            let page = document.page(at: pageIndex)
        else { return }

        let padding = max(inkLineWidth * 2, 4)
        let minX = points.map(\.x).min() ?? 0
        let maxX = points.map(\.x).max() ?? 0
        let minY = points.map(\.y).min() ?? 0
        let maxY = points.map(\.y).max() ?? 0
        let bounds = CGRect(
            x: minX - padding,
            y: minY - padding,
            width: max(maxX - minX + padding * 2, padding * 2),
            height: max(maxY - minY + padding * 2, padding * 2)
        )
        let path = UIBezierPath()
        path.move(to: CGPoint(x: points[0].x - bounds.minX, y: points[0].y - bounds.minY))
        for point in points.dropFirst() {
            path.addLine(to: CGPoint(x: point.x - bounds.minX, y: point.y - bounds.minY))
        }

        let annotation = PDFAnnotation(bounds: bounds, forType: .ink, withProperties: nil)
        annotation.color = inkColor.uiColor
        let border = PDFBorder()
        border.lineWidth = inkLineWidth
        annotation.border = border
        annotation.add(path)
        annotation.contents = "Drawing"
        page.addAnnotation(annotation)
        recordAnnotationAction(.added(annotation, pageIndex: pageIndex))
        isModified = true
        refreshAnnotations()
        persistChanges()
    }

    func deleteAnnotation(_ item: DocumentAnnotation) {
        guard let page = document?.page(at: item.pageIndex) else { return }
        page.removeAnnotation(item.annotation)
        recordAnnotationAction(.removed(item.annotation, pageIndex: item.pageIndex))
        isModified = true
        refreshAnnotations()
        persistChanges()
    }

    func undoAnnotationAction() {
        guard let action = annotationUndoStack.popLast() else { return }
        applyInverse(of: action)
        annotationRedoStack.append(action)
        updateAnnotationHistoryState()
        isModified = true
        refreshAnnotations()
        persistChanges()
    }

    func redoAnnotationAction() {
        guard let action = annotationRedoStack.popLast() else { return }
        apply(action)
        annotationUndoStack.append(action)
        updateAnnotationHistoryState()
        isModified = true
        refreshAnnotations()
        persistChanges()
    }

    func placeAnnotation(pageIndex: Int, point: CGPoint) {
        guard
            let placement = annotationPlacement,
            let page = document?.page(at: pageIndex)
        else { return }

        let annotation: PDFAnnotation
        switch placement.kind {
        case .note:
            annotation = PDFAnnotation(
                bounds: clampedBounds(size: CGSize(width: 34, height: 34), centeredAt: point, on: page),
                forType: .text,
                withProperties: nil
            )
            annotation.iconType = .note
            annotation.color = inkColor.uiColor
            annotation.contents = placement.text
        case .textBox:
            annotation = PDFAnnotation(
                bounds: clampedBounds(size: CGSize(width: 230, height: 76), centeredAt: point, on: page),
                forType: .freeText,
                withProperties: nil
            )
            annotation.contents = placement.text
            annotation.font = UIFont.systemFont(ofSize: 16)
            annotation.fontColor = .black
            annotation.backgroundColor = UIColor.white.withAlphaComponent(0.94)
            annotation.color = inkColor.uiColor
            let border = PDFBorder()
            border.lineWidth = 1
            annotation.border = border
        case .rectangle, .circle:
            annotation = PDFAnnotation(
                bounds: clampedBounds(size: CGSize(width: 130, height: 84), centeredAt: point, on: page),
                forType: placement.kind == .rectangle ? .square : .circle,
                withProperties: nil
            )
            annotation.color = inkColor.uiColor
            let border = PDFBorder()
            border.lineWidth = inkLineWidth
            annotation.border = border
        case .stamp:
            guard let stamp = placement.stamp else { return }
            annotation = PDFAnnotation(
                bounds: clampedBounds(size: CGSize(width: 180, height: 58), centeredAt: point, on: page),
                forType: .stamp,
                withProperties: nil
            )
            annotation.stampName = stamp.rawValue
            annotation.contents = stamp.title
            annotation.color = stamp.color
        case .signature, .initials:
            guard let asset = placement.signatureAsset else { return }
            let bounds = clampedBounds(size: asset.kind.defaultSize, centeredAt: point, on: page)
            if let typedText = asset.typedText?.trimmingCharacters(in: .whitespacesAndNewlines),
               !typedText.isEmpty {
                annotation = PDFAnnotation(bounds: bounds, forType: .freeText, withProperties: nil)
                annotation.contents = typedText
                annotation.font = UIFont(name: "SnellRoundhand-Bold", size: asset.kind == .signature ? 32 : 28)
                    ?? UIFont.italicSystemFont(ofSize: asset.kind == .signature ? 30 : 26)
                annotation.fontColor = .black
                annotation.color = .clear
                annotation.backgroundColor = .clear
                let border = PDFBorder()
                border.lineWidth = 0
                annotation.border = border
            } else {
                annotation = PDFAnnotation(bounds: bounds, forType: .ink, withProperties: nil)
                annotation.color = .black
                let border = PDFBorder()
                border.lineWidth = 2.2
                annotation.border = border
                for stroke in asset.strokes where !stroke.points.isEmpty {
                    let path = UIBezierPath()
                    let first = signaturePoint(stroke.points[0], in: bounds)
                    path.move(to: first)
                    if stroke.points.count == 1 {
                        path.addLine(to: CGPoint(x: first.x + 0.5, y: first.y + 0.5))
                    } else {
                        for point in stroke.points.dropFirst() {
                            path.addLine(to: signaturePoint(point, in: bounds))
                        }
                    }
                    annotation.add(path)
                }
            }
            annotation.userName = "Folik \(asset.kind.title)"
        }

        page.addAnnotation(annotation)
        annotationPlacement = nil
        recordAnnotationAction(.added(annotation, pageIndex: pageIndex))
        isModified = true
        refreshAnnotations()
        persistChanges()
    }

    private func signaturePoint(_ point: SignaturePoint, in bounds: CGRect) -> CGPoint {
        CGPoint(
            x: bounds.minX + CGFloat(point.x) * bounds.width,
            y: bounds.maxY - CGFloat(point.y) * bounds.height
        )
    }

    private func recordAnnotationAction(_ action: AnnotationHistoryAction) {
        annotationUndoStack.append(action)
        annotationRedoStack.removeAll()
        updateAnnotationHistoryState()
    }

    private func updateAnnotationHistoryState() {
        canUndoAnnotation = !annotationUndoStack.isEmpty
        canRedoAnnotation = !annotationRedoStack.isEmpty
    }

    private func apply(_ action: AnnotationHistoryAction) {
        switch action {
        case .added(let annotation, let pageIndex):
            document?.page(at: pageIndex)?.addAnnotation(annotation)
        case .removed(let annotation, let pageIndex):
            document?.page(at: pageIndex)?.removeAnnotation(annotation)
        case .transformed(let annotation, _, _, let toGeometry):
            applyGeometry(toGeometry, to: annotation)
        case .styled(let annotation, _, _, let toStyle):
            applyStyle(toStyle, to: annotation)
        }
    }

    private func applyInverse(of action: AnnotationHistoryAction) {
        switch action {
        case .added(let annotation, let pageIndex):
            document?.page(at: pageIndex)?.removeAnnotation(annotation)
        case .removed(let annotation, let pageIndex):
            document?.page(at: pageIndex)?.addAnnotation(annotation)
        case .transformed(let annotation, _, let fromGeometry, _):
            applyGeometry(fromGeometry, to: annotation)
        case .styled(let annotation, _, let fromStyle, _):
            applyStyle(fromStyle, to: annotation)
        }
    }

    private func copiedPaths(from annotation: PDFAnnotation) -> [UIBezierPath] {
        (annotation.paths ?? []).compactMap { $0.copy() as? UIBezierPath }
    }

    private func transformedPaths(
        _ paths: [UIBezierPath],
        from originalBounds: CGRect,
        to updatedBounds: CGRect
    ) -> [UIBezierPath] {
        guard originalBounds.width > 0, originalBounds.height > 0 else { return paths }
        return paths.compactMap { source in
            guard let path = source.copy() as? UIBezierPath else { return nil }
            path.apply(CGAffineTransform(translationX: -originalBounds.minX, y: -originalBounds.minY))
            path.apply(CGAffineTransform(
                scaleX: updatedBounds.width / originalBounds.width,
                y: updatedBounds.height / originalBounds.height
            ))
            path.apply(CGAffineTransform(translationX: updatedBounds.minX, y: updatedBounds.minY))
            return path
        }
    }

    private func replacePaths(on annotation: PDFAnnotation, with paths: [UIBezierPath]) {
        for path in annotation.paths ?? [] { annotation.remove(path) }
        for path in paths { annotation.add(path) }
    }

    private func applyGeometry(_ geometry: AnnotationGeometry, to annotation: PDFAnnotation) {
        annotation.bounds = geometry.bounds
        if annotation.type?.lowercased() == "ink" {
            replacePaths(on: annotation, with: geometry.paths.compactMap { $0.copy() as? UIBezierPath })
        }
    }

    private func annotationStyle(for annotation: PDFAnnotation) -> AnnotationStyle {
        AnnotationStyle(
            color: annotation.color,
            interiorColor: annotation.interiorColor,
            fontColor: annotation.fontColor,
            lineWidth: annotation.border?.lineWidth
        )
    }

    private func applyStyle(_ style: AnnotationStyle, to annotation: PDFAnnotation) {
        annotation.color = style.color
        annotation.interiorColor = style.interiorColor
        annotation.fontColor = style.fontColor
        if let lineWidth = style.lineWidth {
            let border = annotation.border ?? PDFBorder()
            border.lineWidth = lineWidth
            annotation.border = border
        } else {
            annotation.border = nil
        }
    }

    private func finishAnnotationGeometryChange() {
        isModified = true
        refreshAnnotations()
        persistChanges()
    }

    private func finishAnnotationStyleChange() {
        isModified = true
        refreshAnnotations()
        persistChanges()
    }

    private static func colorsMatch(_ first: UIColor, _ second: UIColor) -> Bool {
        let traits = UITraitCollection.current
        var firstRed: CGFloat = 0
        var firstGreen: CGFloat = 0
        var firstBlue: CGFloat = 0
        var firstAlpha: CGFloat = 0
        var secondRed: CGFloat = 0
        var secondGreen: CGFloat = 0
        var secondBlue: CGFloat = 0
        var secondAlpha: CGFloat = 0
        guard
            first.resolvedColor(with: traits).getRed(
                &firstRed,
                green: &firstGreen,
                blue: &firstBlue,
                alpha: &firstAlpha
            ),
            second.resolvedColor(with: traits).getRed(
                &secondRed,
                green: &secondGreen,
                blue: &secondBlue,
                alpha: &secondAlpha
            )
        else { return first.isEqual(second) }
        return abs(firstRed - secondRed) < 0.03
            && abs(firstGreen - secondGreen) < 0.03
            && abs(firstBlue - secondBlue) < 0.03
    }

    private func clampedBounds(size: CGSize, centeredAt point: CGPoint, on page: PDFPage) -> CGRect {
        let pageBounds = page.bounds(for: .cropBox)
        let width = min(size.width, pageBounds.width)
        let height = min(size.height, pageBounds.height)
        let x = min(max(point.x - width / 2, pageBounds.minX), pageBounds.maxX - width)
        let y = min(max(point.y - height / 2, pageBounds.minY), pageBounds.maxY - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    func clampedBounds(
        _ bounds: CGRect,
        on page: PDFPage,
        minimumSize: CGSize = CGSize(width: 1, height: 1)
    ) -> CGRect {
        let pageBounds = page.bounds(for: .cropBox)
        let width = min(max(bounds.width, minimumSize.width), pageBounds.width)
        let height = min(max(bounds.height, minimumSize.height), pageBounds.height)
        let x = min(max(bounds.minX, pageBounds.minX), pageBounds.maxX - width)
        let y = min(max(bounds.minY, pageBounds.minY), pageBounds.maxY - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    func reportPage(_ page: PDFPage?) {
        guard let document, let page else { return }
        let reportedIndex = max(0, document.index(for: page))
        if pageIndex != reportedIndex {
            pageIndex = reportedIndex
            saveReaderState()
        }
        if let selectedAnnotation, selectedAnnotation.pageIndex != pageIndex {
            self.selectedAnnotation = nil
        }
    }

    private func saveReaderState() {
        readerStateStore.save(ReaderState(pageIndex: pageIndex, layout: layout), for: item.url)
    }

    func reportSelection(_ selection: PDFSelection?) {
        currentSelection = selection
        let selectionHasText = !(selection?.string?.isEmpty ?? true)
        if hasTextSelection != selectionHasText {
            hasTextSelection = selectionHasText
        }
    }

    private func loadDocument() {
        guard let document = PDFDocument(url: item.url) else {
            errorMessage = "Folik couldn’t read this PDF."
            return
        }
        self.document = document
        document.delegate = self
        isLocked = document.isLocked
        if !document.isLocked {
            outlineEntries = Self.flattenOutline(document.outlineRoot)
            configureForms(in: document)
            refreshAnnotations()
        }
    }

    private func loadSavedSignatures() {
        for kind in SignatureKind.allCases {
            guard let asset = signatureStore.load(kind) else { continue }
            if kind == .signature { savedSignature = asset } else { savedInitials = asset }
        }
    }

    private func refreshAnnotations() {
        guard let document else { return }
        annotations = Self.annotations(in: document)
        if let selected = selectedAnnotation {
            selectedAnnotation = annotations.first { $0.annotation === selected.annotation }
        }
    }

    private func configureForms(in document: PDFDocument) {
        canFillForms = document.allowsFormFieldEntry
        formFields = Self.formFields(in: document)
        if Self.containsXFA(in: document) {
            formCompatibilityNotice = formFields.isEmpty
                ? "This PDF uses an XFA form, which iOS cannot fill."
                : "This PDF also contains XFA content. Only its standard fields are editable."
        } else {
            formCompatibilityNotice = nil
        }
        savedFormValues = currentFormValues()
    }

    private func currentFormValues() -> [String: FormFieldSnapshot] {
        Dictionary(uniqueKeysWithValues: formFields.map {
            ($0.id, FormFieldSnapshot(
                stringValue: $0.annotation.widgetStringValue ?? "",
                buttonState: $0.annotation.buttonWidgetState.rawValue
            ))
        })
    }

    private static func formFields(in document: PDFDocument) -> [FormField] {
        var fields: [FormField] = []
        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            for (annotationIndex, annotation) in page.annotations.enumerated() where annotation.type == "Widget" {
                let rawKind = annotation.widgetFieldType.rawValue
                let normalizedKind = rawKind.replacingOccurrences(of: "/", with: "").lowercased()
                let kind: FormFieldKind
                if normalizedKind.contains("text") || normalizedKind == "tx" {
                    kind = annotation.isMultiline ? .multilineText : .text
                } else if normalizedKind.contains("choice") || normalizedKind == "ch" {
                    kind = .choice
                } else if normalizedKind.contains("signature") || normalizedKind == "sig" {
                    kind = .signature
                } else if normalizedKind.contains("button") || normalizedKind == "btn" {
                    switch annotation.widgetControlType {
                    case .checkBoxControl: kind = .checkbox
                    case .radioButtonControl: kind = .radio
                    case .pushButtonControl: kind = .pushButton
                    default: kind = .unknown
                    }
                } else {
                    kind = .unknown
                }
                let fallbackTitle = "\(kind.title) on page \(pageIndex + 1)"
                let fieldName = annotation.fieldName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                let accessibleLabel = (annotation.value(forAnnotationKey: .widgetTextLabelUI) as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .nilIfEmpty
                let nearbyLabel = fieldName.map(isTechnicalFieldName) == true
                    ? nearbyFormLabel(for: annotation, kind: kind, on: page)
                    : nil
                let id = formFieldID(pageIndex: pageIndex, annotationIndex: annotationIndex, annotation: annotation)
                fields.append(FormField(
                    id: id,
                    annotation: annotation,
                    pageIndex: pageIndex,
                    title: accessibleLabel ?? nearbyLabel ?? fieldName ?? fallbackTitle,
                    logicalID: fieldName ?? id,
                    kind: kind,
                    value: annotation.widgetStringValue ?? "",
                    isReadOnly: annotation.isReadOnly,
                    isSelected: annotation.buttonWidgetState == .onState,
                    isRequired: isRequired(annotation)
                ))
            }
        }
        return fields
    }

    private static func nearbyFormLabel(
        for annotation: PDFAnnotation,
        kind: FormFieldKind,
        on page: PDFPage
    ) -> String? {
        let pageBounds = page.bounds(for: .mediaBox)
        let fieldBounds = annotation.bounds
        let isButton = kind == .checkbox || kind == .radio
        let extraWidth: CGFloat = isButton ? 230 : 20
        let searchY = isButton ? fieldBounds.minY - 5 : fieldBounds.maxY - 4
        let requestedHeight = isButton ? fieldBounds.height + 10 : 34
        let searchBounds = CGRect(
            x: max(pageBounds.minX, fieldBounds.minX - 10),
            y: max(pageBounds.minY, searchY),
            width: min(pageBounds.maxX - max(pageBounds.minX, fieldBounds.minX - 10), fieldBounds.width + extraWidth),
            height: min(pageBounds.maxY - max(pageBounds.minY, searchY), requestedHeight)
        )
        guard let rawText = page.selection(for: searchBounds)?.string else { return nil }
        let lines = rawText
            .components(separatedBy: .newlines)
            .map {
                $0.components(separatedBy: .whitespaces)
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
            }
            .filter { !$0.isEmpty }
        guard let bestLine = lines.max(by: { $0.count < $1.count }), bestLine.count >= 2 else { return nil }
        return bestLine.count > 110 ? "\(bestLine.prefix(109))…" : bestLine
    }

    private static func isTechnicalFieldName(_ name: String) -> Bool {
        name.contains("[")
            || name.contains("]")
            || name.localizedCaseInsensitiveContains("subform")
            || name.range(of: #"^f\d+[_\d]*$"#, options: .regularExpression) != nil
    }

    private static func formFieldID(pageIndex: Int, annotationIndex: Int, annotation: PDFAnnotation) -> String {
        "\(pageIndex):\(annotationIndex):\(annotation.fieldName ?? "field")"
    }

    private static func restoreButtonState(_ rawValue: Int, to annotation: PDFAnnotation) {
        switch rawValue {
        case PDFWidgetCellState.mixedState.rawValue: annotation.buttonWidgetState = .mixedState
        case PDFWidgetCellState.onState.rawValue: annotation.buttonWidgetState = .onState
        default: annotation.buttonWidgetState = .offState
        }
    }

    private static func isRequired(_ annotation: PDFAnnotation) -> Bool {
        let flags = (annotation.value(forAnnotationKey: .widgetFieldFlags) as? NSNumber)?.intValue ?? 0
        return flags & (1 << 1) != 0
    }

    private static func containsXFA(in document: PDFDocument) -> Bool {
        guard
            let documentRef = document.documentRef,
            let catalog = documentRef.catalog
        else { return false }

        var acroForm: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(catalog, "AcroForm", &acroForm), let acroForm else {
            return false
        }
        var xfa: CGPDFObjectRef?
        return CGPDFDictionaryGetObject(acroForm, "XFA", &xfa)
    }

    private static func annotations(in document: PDFDocument) -> [DocumentAnnotation] {
        var items: [DocumentAnnotation] = []
        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            for (annotationIndex, annotation) in page.annotations.enumerated() {
                guard let metadata = annotationMetadata(for: annotation, on: page) else { continue }
                items.append(DocumentAnnotation(
                    id: "\(pageIndex):\(annotationIndex):\(annotation.type ?? "annotation")",
                    annotation: annotation,
                    pageIndex: pageIndex,
                    title: metadata.title,
                    excerpt: metadata.excerpt,
                    icon: metadata.icon,
                    color: annotation.color
                ))
            }
        }
        return items
    }

    private static func annotationMetadata(
        for annotation: PDFAnnotation,
        on page: PDFPage
    ) -> (title: String, excerpt: String, icon: String)? {
        let type = (annotation.type ?? "").lowercased()
        let title: String
        let icon: String
        if annotation.userName == "Folik Signature" {
            return ("Signature", annotation.contents?.nilIfEmpty ?? "Saved signature", "signature")
        }
        if annotation.userName == "Folik Initials" {
            return ("Initials", annotation.contents?.nilIfEmpty ?? "Saved initials", "character.cursor.ibeam")
        }
        switch type {
        case "highlight": title = "Highlight"; icon = "highlighter"
        case "underline": title = "Underline"; icon = "underline"
        case "strikeout": title = "Strike Out"; icon = "strikethrough"
        case "ink": title = "Drawing"; icon = "scribble"
        case "text": title = "Note"; icon = "note.text"
        case "freetext": title = "Text box"; icon = "text.bubble"
        case "square", "circle", "line": title = "Shape"; icon = "square.on.circle"
        case "stamp":
            title = annotation.contents?.nilIfEmpty
                ?? annotation.stampName?
                    .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                    .nilIfEmpty
                ?? "Stamp"
            icon = "seal"
        default: return nil
        }
        let content = annotation.contents?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
        let selectedText = page.selection(for: annotation.bounds)?.string?
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .nilIfEmpty
        return (title, content ?? selectedText ?? "Page annotation", icon)
    }

    private static func flattenOutline(_ root: PDFOutline?) -> [OutlineEntry] {
        guard let root else { return [] }
        var entries: [OutlineEntry] = []

        func visit(_ node: PDFOutline, level: Int) {
            if let destination = node.destination {
                entries.append(OutlineEntry(
                    title: node.label?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Untitled section",
                    level: level,
                    destination: destination
                ))
            }
            for index in 0..<node.numberOfChildren {
                if let child = node.child(at: index) { visit(child, level: level + 1) }
            }
        }

        for index in 0..<root.numberOfChildren {
            if let child = root.child(at: index) { visit(child, level: 0) }
        }
        return entries
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

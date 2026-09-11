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

nonisolated enum FormFieldPlacementKind: String, CaseIterable, Identifiable, Sendable {
    case text
    case multilineText
    case checkbox
    case date
    case signature

    var id: Self { self }

    var title: String {
        switch self {
        case .text: "Text field"
        case .multilineText: "Multiline field"
        case .checkbox: "Checkbox"
        case .date: "Date field"
        case .signature: "Signature field"
        }
    }

    var icon: String {
        switch self {
        case .text: "text.cursor"
        case .multilineText: "text.alignleft"
        case .checkbox: "checkmark.square"
        case .date: "calendar"
        case .signature: "signature"
        }
    }

    var defaultSize: CGSize {
        switch self {
        case .text: CGSize(width: 230, height: 38)
        case .multilineText: CGSize(width: 260, height: 92)
        case .checkbox: CGSize(width: 30, height: 30)
        case .date: CGSize(width: 170, height: 38)
        case .signature: CGSize(width: 250, height: 68)
        }
    }
}

struct FormFieldPlacement: Equatable {
    let kind: FormFieldPlacementKind
    let label: String
    let isRequired: Bool
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

private struct FormFieldProperties {
    let label: String
    let flags: Int
}

private indirect enum AnnotationHistoryAction {
    case batch([AnnotationHistoryAction])
    case fieldOrder(from: [(PDFAnnotation, Int?)], to: [(PDFAnnotation, Int?)])
    case formProperties(PDFAnnotation, from: FormFieldProperties, to: FormFieldProperties)
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
    var isAuthoredByFolik: Bool { annotation.contents == "Folik form field" }

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

enum FormWorkspaceMode: String, CaseIterable, Identifiable {
    case build, fill
    var id: Self { self }
    var title: String { self == .build ? "Build" : "Fill" }
}

@MainActor
final class DocumentSession: NSObject, ObservableObject, PDFDocumentDelegate {
    let item: LibraryDocument
    private var repeatsFormPlacement = false
    private var rememberedFieldSizes: [FormFieldPlacementKind: CGSize] = [:]
    private var lastPlacedFormAnnotation: PDFAnnotation?
    @Published private(set) var formMode: FormWorkspaceMode = .fill
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
    @Published private(set) var isSaving = false
    @Published private(set) var hasSavedChanges = false
    @Published private(set) var documentRevision = 0
    @Published private(set) var saveFailed = false
    var commitPendingEdits: (() -> Void)?
    private var pendingSave: Task<Bool, Never>?
    private var scheduledAnnotationSave: Task<Void, Never>?
    private let annotationSaveDelay: Duration
    private(set) var successfulSaveCount = 0
    private let saveDocument: @MainActor (PDFDocument, URL) throws -> Void

    var saveStatus: String {
        if isSaving { return "Saving…" }
        if saveFailed { return "Not saved · Tap to retry" }
        if isModified { return "Unsaved changes · Tap to save" }
        return hasSavedChanges ? "Saved on this device" : "On this device"
    }
    @Published private(set) var isPreparingDocument = false
    private let deferredPreparation: Bool
    private var preparationComplete = false
    private var preparationTask: Task<Void, Never>?
    private(set) var preparationBatchCount = 0
    private(set) var longestPreparationBatchMilliseconds = 0.0
    @Published private(set) var isLocked = false
    @Published private(set) var canFillForms = false
    @Published private(set) var formCompatibilityNotice: String?
    @Published private(set) var canUndoAnnotation = false
    @Published private(set) var canRedoAnnotation = false
    @Published var isDrawingEnabled = false
    @Published private(set) var annotationPlacement: AnnotationPlacement?
    @Published private(set) var formFieldPlacement: FormFieldPlacement?
    @Published private(set) var isAnnotationEditingEnabled = false
    @Published private(set) var isFormLayoutEditingEnabled = false
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
        readerStateStore: ReaderStateStore? = nil,
        annotationSaveDelay: Duration = .zero,
        deferredPreparation: Bool = false,
        saveDocument: @escaping @MainActor (PDFDocument, URL) throws -> Void = PDFDocumentPersistence.save
    ) {
        self.deferredPreparation = deferredPreparation
        self.saveDocument = saveDocument
        self.annotationSaveDelay = annotationSaveDelay
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
        if document != nil && !isLocked {
            self.readerStateStore.markOpened(item.url)
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
    var isPlacementActive: Bool { annotationPlacement != nil || formFieldPlacement != nil }
    var placementTitle: String { formFieldPlacement?.kind.title ?? annotationPlacement?.title ?? "Place" }
    var placementIcon: String { formFieldPlacement?.kind.icon ?? annotationPlacement?.icon ?? "plus" }

    func unlock(with password: String) -> Bool {
        guard let document, document.unlock(withPassword: password) else { return false }
        isLocked = false
        readerStateStore.markOpened(item.url)
        prepareSynchronously(document)
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
            formFieldPlacement = nil
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
        formFieldPlacement = nil
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
        formFieldPlacement = nil
        finishAnnotationEditing()
        annotationPlacement = AnnotationPlacement(kind: .stamp, text: "", signatureAsset: nil, stamp: stamp)
    }

    func beginSignaturePlacement(_ asset: SignatureAsset) {
        guard asset.isValid else { return }
        isDrawingEnabled = false
        formFieldPlacement = nil
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
        repeatsFormPlacement = false
        annotationPlacement = nil
        formFieldPlacement = nil
    }

    func setFormMode(_ mode: FormWorkspaceMode) {
        commitPendingEdits?()
        cancelAnnotationPlacement()
        setDrawingEnabled(false)
        finishAnnotationEditing()
        formMode = mode
    }

    func beginFormFieldPlacement(_ kind: FormFieldPlacementKind, label: String, isRequired: Bool) {
        repeatsFormPlacement = false
        let normalizedLabel = label
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(80)
        guard !normalizedLabel.isEmpty, document != nil, !isLocked, canFillForms else { return }
        isDrawingEnabled = false
        annotationPlacement = nil
        finishAnnotationEditing()
        formFieldPlacement = FormFieldPlacement(
            kind: kind,
            label: String(normalizedLabel),
            isRequired: isRequired
        )
    }

    func beginQuickFormFieldPlacement(_ kind: FormFieldPlacementKind) {
        beginFormFieldPlacement(kind, label: nextQuickFieldLabel(kind), isRequired: false)
        repeatsFormPlacement = formFieldPlacement != nil
    }

    private func nextQuickFieldLabel(_ kind: FormFieldPlacementKind) -> String {
        let used = Set(formFields.map { $0.title.localizedLowercase })
        var number = 1
        while used.contains("\(kind.title) \(number)".localizedLowercase) { number += 1 }
        return "\(kind.title) \(number)"
    }

    var selectedAuthoredFormField: FormField? {
        guard let selectedAnnotation else { return nil }
        return formFields.first { $0.annotation === selectedAnnotation.annotation && $0.isAuthoredByFolik }
    }

    func arrangeFormFields() {
        beginFormLayoutEditing()
        if let annotation = lastPlacedFormAnnotation,
           let field = formFields.first(where: { $0.annotation === annotation }) {
            selectAnnotation(annotation, pageIndex: field.pageIndex, navigate: false)
        }
    }

    private func placementKind(for field: FormField) -> FormFieldPlacementKind? {
        if let raw = field.annotation.value(forAnnotationKey: PDFAnnotationKey(rawValue: "FolikFieldKind")) as? String,
           let kind = FormFieldPlacementKind(rawValue: raw) { return kind }
        switch field.kind {
        case .text: return .text
        case .multilineText: return .multilineText
        case .checkbox: return .checkbox
        case .signature: return .signature
        default: return nil
        }
    }

    func duplicateSelectedFormField() {
        guard let field = selectedAuthoredFormField, let kind = placementKind(for: field),
              let page = document?.page(at: field.pageIndex) else { return }
        var reserved = Set(formFields.compactMap { $0.annotation.fieldName?.localizedLowercase })
        let annotation = formFieldAnnotation(
            placement: FormFieldPlacement(kind: kind, label: field.title, isRequired: field.isRequired),
            bounds: clampedBounds(field.annotation.bounds.offsetBy(dx: 0, dy: -field.annotation.bounds.height - 12), on: page),
            fieldName: uniqueFormFieldName(for: field.title, reservedNames: &reserved)
        )
        page.addAnnotation(annotation)
        recordAnnotationAction(.added(annotation, pageIndex: field.pageIndex))
        isModified = true
        refreshFormState(markModified: false)
        lastPlacedFormAnnotation = annotation
        selectAnnotation(annotation, pageIndex: field.pageIndex)
        scheduleAnnotationSave()
    }

    func updateSelectedFormField(label: String, isRequired: Bool) {
        guard let field = selectedAuthoredFormField else { return }
        let label = String(label.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        guard !label.isEmpty else { return }
        let oldFlags = (field.annotation.value(forAnnotationKey: .widgetFieldFlags) as? NSNumber)?.intValue ?? 0
        let newFlags = isRequired ? oldFlags | 2 : oldFlags & ~2
        guard label != field.title || newFlags != oldFlags else { return }
        let before = FormFieldProperties(label: field.title, flags: oldFlags)
        let after = FormFieldProperties(label: label, flags: newFlags)
        applyFormProperties(after, to: field.annotation)
        recordAnnotationAction(.formProperties(field.annotation, from: before, to: after))
        isModified = true
        refreshAnnotations()
        scheduleAnnotationSave()
    }

    private func applyFormProperties(_ properties: FormFieldProperties, to annotation: PDFAnnotation) {
        annotation.setValue(properties.label, forAnnotationKey: .widgetTextLabelUI)
        annotation.setValue(NSNumber(value: properties.flags), forAnnotationKey: .widgetFieldFlags)
        refreshFormState(markModified: false)
    }

    @discardableResult
    func arrangeFormFields(ids: Set<String>, action: FormLayoutAction) -> Bool {
        guard formMode == .build, !isLocked, canFillForms else { return false }
        let fields = formFields.filter { ids.contains($0.id) && !$0.isReadOnly }
        guard fields.count == ids.count, let first = fields.first,
              fields.allSatisfy({ $0.pageIndex == first.pageIndex }),
              let page = document?.page(at: first.pageIndex),
              let bounds = action.arrange(fields.map { $0.annotation.bounds }),
              bounds.allSatisfy({ page.bounds(for: .cropBox).contains($0) }) else { return false }
        var actions: [AnnotationHistoryAction] = []
        for (field, bounds) in zip(fields, bounds) where field.annotation.bounds != bounds {
            let before = AnnotationGeometry(bounds: field.annotation.bounds, paths: [])
            let after = AnnotationGeometry(bounds: bounds, paths: [])
            field.annotation.bounds = bounds
            actions.append(.transformed(field.annotation, pageIndex: field.pageIndex, from: before, to: after))
        }
        guard !actions.isEmpty else { return true }
        recordAnnotationAction(.batch(actions))
        finishAnnotationGeometryChange()
        return true
    }

    func setFormFillOrder(_ ids: [String]) {
        guard formMode == .build, !isLocked, canFillForms,
              ids.count == formFields.count, Set(ids).count == ids.count,
              Set(ids) == Set(formFields.map(\.id)), ids != formFields.map(\.id) else { return }
        let key = PDFAnnotationKey(rawValue: "/FolikFillOrder")
        let old = formFields.map { ($0.annotation, ($0.annotation.value(forAnnotationKey: key) as? NSNumber)?.intValue) }
        let byID = Dictionary(uniqueKeysWithValues: formFields.map { ($0.id, $0.annotation) })
        let new: [(PDFAnnotation, Int?)] = ids.enumerated().compactMap { index, id in
            byID[id].map { ($0, Optional(index)) }
        }
        applyFieldOrder(new)
        recordAnnotationAction(.fieldOrder(from: old, to: new))
        finishAnnotationGeometryChange()
    }

    private func applyFieldOrder(_ values: [(PDFAnnotation, Int?)]) {
        let key = PDFAnnotationKey(rawValue: "/FolikFillOrder")
        for (annotation, order) in values {
            if let order { annotation.setValue(NSNumber(value: order), forAnnotationKey: key) }
            else { annotation.removeValue(forAnnotationKey: key) }
        }
        refreshFormState(markModified: false)
    }

    private static func orderedFormFields(_ fields: [FormField]) -> [FormField] {
        let key = PDFAnnotationKey(rawValue: "/FolikFillOrder")
        return fields.enumerated().sorted { lhs, rhs in
            let left = (lhs.element.annotation.value(forAnnotationKey: key) as? NSNumber)?.intValue ?? Int.max
            let right = (rhs.element.annotation.value(forAnnotationKey: key) as? NSNumber)?.intValue ?? Int.max
            return left == right ? lhs.offset < rhs.offset : left < right
        }.map(\.element)
    }

    /// Snap matching edges within six PDF points. Used only for form dragging.
    func alignedFormBounds(_ proposed: CGRect, excluding annotation: PDFAnnotation, on page: PDFPage) -> CGRect {
        guard isFormLayoutEditingEnabled else { return proposed }
        let others = page.annotations.filter { $0 !== annotation && $0.type?.lowercased() == "widget" }
        var dx: CGFloat = 7
        var dy: CGFloat = 7
        for other in others {
            for delta in [other.bounds.minX - proposed.minX, other.bounds.maxX - proposed.maxX] where abs(delta) < abs(dx) { dx = delta }
            for delta in [other.bounds.minY - proposed.minY, other.bounds.maxY - proposed.maxY] where abs(delta) < abs(dy) { dy = delta }
        }
        return proposed.offsetBy(dx: abs(dx) <= 6 ? dx : 0, dy: abs(dy) <= 6 ? dy : 0)
    }

    func suggestFormFields() async throws -> [FormFieldSuggestion] {
        guard let data = document?.dataRepresentation(), !isLocked, canFillForms else {
            throw PDFProcessingError.protected
        }
        return try await FormFieldSuggestionEngine.suggestions(in: data)
    }

    func addFormFieldSuggestions(_ suggestions: [FormFieldSuggestion]) {
        guard let document, !suggestions.isEmpty, !isLocked, canFillForms else { return }
        var reservedNames = Set(formFields.compactMap { $0.annotation.fieldName?.localizedLowercase })
        var added = false

        for suggestion in suggestions.prefix(FormFieldSuggestionEngine.maximumSuggestions) {
            guard let page = document.page(at: suggestion.pageIndex) else { continue }
            let bounds = clampedBounds(suggestion.bounds, on: page, minimumSize: CGSize(width: 18, height: 18))
            let overlapsWidget = page.annotations.contains {
                guard $0.type?.lowercased() == "widget" else { return false }
                let intersection = $0.bounds.intersection(bounds)
                return !intersection.isNull && bounds.width * bounds.height > 0 &&
                    intersection.width * intersection.height / (bounds.width * bounds.height) > 0.45
            }
            guard !overlapsWidget else { continue }
            let fieldName = uniqueFormFieldName(for: suggestion.label, reservedNames: &reservedNames)
            let annotation = formFieldAnnotation(
                placement: FormFieldPlacement(kind: suggestion.kind, label: suggestion.label, isRequired: false),
                bounds: bounds,
                fieldName: fieldName
            )
            page.addAnnotation(annotation)
            recordAnnotationAction(.added(annotation, pageIndex: suggestion.pageIndex))
            added = true
        }

        guard added else { return }
        formFieldPlacement = nil
        isModified = true
        refreshFormState(markModified: false)
        scheduleAnnotationSave()
        beginFormLayoutEditing()
    }

    func beginAnnotationEditing() {
        isDrawingEnabled = false
        annotationPlacement = nil
        formFieldPlacement = nil
        selectedAnnotation = nil
        isFormLayoutEditingEnabled = false
        isAnnotationEditingEnabled = true
        command = PDFReaderCommand(action: .fitPage)
    }

    func beginFormLayoutEditing() {
        guard document != nil, !isLocked, canFillForms else { return }
        repeatsFormPlacement = false
        isDrawingEnabled = false
        annotationPlacement = nil
        formFieldPlacement = nil
        selectedAnnotation = nil
        isFormLayoutEditingEnabled = true
        isAnnotationEditingEnabled = true
        command = PDFReaderCommand(action: .fitPage)
    }

    func finishAnnotationEditing() {
        selectedAnnotation = nil
        isAnnotationEditingEnabled = false
        isFormLayoutEditingEnabled = false
    }

    func selectAnnotation(_ annotation: PDFAnnotation, pageIndex: Int, navigate: Bool = true) {
        guard isAnnotationEditingEnabled else { return }
        selectedAnnotation = annotations.first {
            $0.pageIndex == pageIndex && $0.annotation === annotation
        }
        if selectedAnnotation == nil,
           let field = formFields.first(where: {
               $0.pageIndex == pageIndex && $0.annotation === annotation
           }) {
            selectedAnnotation = DocumentAnnotation(
                id: field.id,
                annotation: annotation,
                pageIndex: pageIndex,
                title: field.title,
                excerpt: field.kind.title,
                icon: formFieldIcon(field.kind),
                color: annotation.color
            )
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
        return ["freetext", "square", "circle", "stamp", "ink", "widget"].contains(type)
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
        if isFormLayoutEditingEnabled { return type == "widget" }
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
        if let field = selectedAuthoredFormField, let kind = placementKind(for: field) {
            rememberedFieldSizes[kind] = field.annotation.bounds.size
        }
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

    func deleteAuthoredFormField(_ field: FormField) {
        guard
            field.isAuthoredByFolik,
            let currentField = formFields.first(where: { $0.annotation === field.annotation })
        else { return }
        if selectedAnnotation?.annotation === currentField.annotation {
            selectedAnnotation = nil
        }
        deleteAnnotation(DocumentAnnotation(
            id: currentField.id,
            annotation: currentField.annotation,
            pageIndex: currentField.pageIndex,
            title: currentField.title,
            excerpt: currentField.kind.title,
            icon: formFieldIcon(currentField.kind),
            color: currentField.annotation.color
        ))
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
        refreshFormValues()
        if currentFormValues() != savedFormValues { isModified = true }
    }

    func requestSave() {
        Task { await saveForSharing() }
    }

    /// Ends native field editing and confirms persistence before a caller reads the file.
    func saveForSharing() async -> Bool {
        if let pendingSave { return await pendingSave.value }
        isSaving = true
        let backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Save PDF")
        let task = Task { @MainActor in
            defer {
                self.pendingSave = nil
                self.isSaving = false
                if backgroundTask != .invalid { UIApplication.shared.endBackgroundTask(backgroundTask) }
            }
            self.commitPendingEdits?()
            // Allow PDFKit's end-editing notifications to commit the active field.
            await Task.yield()
            self.noteFormEditing()
            return self.persistChanges()
        }
        pendingSave = task
        return await task.value
    }

    func prepareShare(mode: DocumentExportMode) async throws -> URL {
        guard await saveForSharing() else { throw CocoaError(.fileWriteUnknown) }
        let sourceURL = item.url
        let worker = Task.detached(priority: .userInitiated) {
            try DocumentExporter.export(sourceURL: sourceURL, mode: mode)
        }
        let result = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
        if Task.isCancelled { DocumentExporter.removeExport(at: result); throw CancellationError() }
        return result
    }

    private func scheduleAnnotationSave() {
        guard annotationSaveDelay > .zero else { persistChanges(); return }
        scheduledAnnotationSave?.cancel()
        let delay = annotationSaveDelay
        scheduledAnnotationSave = Task { [weak self] in
            do {
                try await Task.sleep(for: delay)
                guard let self else { return }
                self.scheduledAnnotationSave = nil
                _ = await self.saveForSharing()
            } catch { }
        }
    }

    @discardableResult
    func persistChanges() -> Bool {
        scheduledAnnotationSave?.cancel()
        scheduledAnnotationSave = nil
        guard let document, !isLocked else {
            saveFailed = true
            errorMessage = "Open and unlock this PDF before saving or sharing."
            return false
        }
        guard isModified else { return !saveFailed }
        refreshFormValues()
        do {
            try saveDocument(document, item.url)
            savedFormValues = currentFormValues()
            refreshFormValues()
            isModified = false
            if saveFailed { errorMessage = nil }
            saveFailed = false
            hasSavedChanges = true
            documentRevision += 1
            successfulSaveCount += 1
            return true
        } catch {
            saveFailed = true
            errorMessage = "Your changes are still visible, but could not be saved. Free up device storage if needed, then tap the save status to retry."
            return false
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

    private func refreshFormValues() {
        formFields = formFields.map { field in
            FormField(id: field.id, annotation: field.annotation, pageIndex: field.pageIndex,
                      title: field.title, logicalID: field.logicalID, kind: field.kind,
                      value: field.annotation.widgetStringValue ?? "", isReadOnly: field.annotation.isReadOnly,
                      isSelected: field.annotation.buttonWidgetState == .onState, isRequired: field.isRequired)
        }
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
        scheduleAnnotationSave()
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
        scheduleAnnotationSave()
    }

    func deleteAnnotation(_ item: DocumentAnnotation) {
        guard let page = document?.page(at: item.pageIndex) else { return }
        page.removeAnnotation(item.annotation)
        if item.annotation.type == "Widget" { refreshFormState(markModified: false) }
        recordAnnotationAction(.removed(item.annotation, pageIndex: item.pageIndex))
        isModified = true
        refreshAnnotations()
        scheduleAnnotationSave()
    }

    func undoAnnotationAction() {
        guard let action = annotationUndoStack.popLast() else { return }
        applyInverse(of: action)
        annotationRedoStack.append(action)
        updateAnnotationHistoryState()
        isModified = true
        refreshAnnotations()
        scheduleAnnotationSave()
    }

    func redoAnnotationAction() {
        guard let action = annotationRedoStack.popLast() else { return }
        apply(action)
        annotationUndoStack.append(action)
        updateAnnotationHistoryState()
        isModified = true
        refreshAnnotations()
        scheduleAnnotationSave()
    }

    func placeAnnotation(pageIndex: Int, point: CGPoint) {
        if let placement = formFieldPlacement {
            placeFormField(placement, pageIndex: pageIndex, point: point)
            return
        }
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
        scheduleAnnotationSave()
    }

    private func placeFormField(_ placement: FormFieldPlacement, pageIndex: Int, point: CGPoint) {
        guard let page = document?.page(at: pageIndex) else { return }
        var reservedNames = Set(formFields.compactMap { $0.annotation.fieldName?.localizedLowercase })
        let fieldName = uniqueFormFieldName(for: placement.label, reservedNames: &reservedNames)
        let annotation = formFieldAnnotation(
            placement: placement,
            bounds: clampedBounds(size: rememberedFieldSizes[placement.kind] ?? placement.kind.defaultSize, centeredAt: point, on: page),
            fieldName: fieldName
        )
        page.addAnnotation(annotation)
        lastPlacedFormAnnotation = annotation
        formFieldPlacement = nil
        recordAnnotationAction(.added(annotation, pageIndex: pageIndex))
        isModified = true
        refreshFormState(markModified: false)
        if repeatsFormPlacement {
            formFieldPlacement = FormFieldPlacement(kind: placement.kind, label: nextQuickFieldLabel(placement.kind), isRequired: false)
        }
        scheduleAnnotationSave()
    }

    private func formFieldAnnotation(
        placement: FormFieldPlacement,
        bounds: CGRect,
        fieldName: String
    ) -> PDFAnnotation {
        let annotation: PDFAnnotation = placement.kind == .signature
            ? VisibleSignatureField(bounds: bounds, forType: .widget, withProperties: nil)
            : PDFAnnotation(bounds: bounds, forType: .widget, withProperties: nil)
        switch placement.kind {
        case .text, .multilineText, .date:
            annotation.widgetFieldType = .text
            annotation.widgetStringValue = ""
            annotation.font = UIFont.systemFont(ofSize: 16)
            if placement.kind == .multilineText { annotation.isMultiline = true }
        case .checkbox:
            annotation.widgetFieldType = .button
            annotation.widgetControlType = .checkBoxControl
            annotation.buttonWidgetStateString = "Yes"
            annotation.buttonWidgetState = .offState
        case .signature:
            annotation.widgetFieldType = .signature
        }

        annotation.fieldName = fieldName
        annotation.contents = "Folik form field"
        annotation.setValue(placement.kind.rawValue, forAnnotationKey: PDFAnnotationKey(rawValue: "FolikFieldKind"))
        annotation.setValue(placement.label, forAnnotationKey: .widgetTextLabelUI)
        if placement.isRequired {
            let flags = (annotation.value(forAnnotationKey: .widgetFieldFlags) as? NSNumber)?.intValue ?? 0
            annotation.setValue(NSNumber(value: flags | (1 << 1)), forAnnotationKey: .widgetFieldFlags)
        }
        annotation.backgroundColor = UIColor.white.withAlphaComponent(0.94)
        annotation.color = FolikTheme.annotationBlue
        // Widgets use /MK border colors; the general annotation color alone is not rendered.
        let appearance = PDFAppearanceCharacteristics()
        appearance.backgroundColor = .white
        appearance.borderColor = FolikTheme.annotationBlue
        if placement.kind == .checkbox { appearance.controlType = .checkBoxControl }
        annotation.setValue(appearance, forAnnotationKey: .widgetAppearanceDictionary)
        let border = PDFBorder()
        border.lineWidth = 1.5
        annotation.border = border
        return annotation
    }

    private func uniqueFormFieldName(
        for proposedName: String,
        reservedNames: inout Set<String>
    ) -> String {
        guard reservedNames.contains(proposedName.localizedLowercase) else {
            reservedNames.insert(proposedName.localizedLowercase)
            return proposedName
        }
        var suffix = 2
        while reservedNames.contains("\(proposedName) \(suffix)".localizedLowercase) { suffix += 1 }
        let name = "\(proposedName) \(suffix)"
        reservedNames.insert(name.localizedLowercase)
        return name
    }

    private func formFieldIcon(_ kind: FormFieldKind) -> String {
        switch kind {
        case .text: "text.cursor"
        case .multilineText: "text.alignleft"
        case .checkbox: "checkmark.square"
        case .radio: "circle.circle"
        case .choice: "list.bullet.rectangle"
        case .signature: "signature"
        case .pushButton: "button.programmable"
        case .unknown: "questionmark.square.dashed"
        }
    }

    private func signaturePoint(_ point: SignaturePoint, in bounds: CGRect) -> CGPoint {
        // PDFKit ink paths are local to the annotation; its bounds supply the page offset.
        CGPoint(
            x: CGFloat(point.x) * bounds.width,
            y: (1 - CGFloat(point.y)) * bounds.height
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
        case .batch(let actions): actions.forEach { apply($0) }
        case .fieldOrder(_, let to): applyFieldOrder(to)
        case .formProperties(let annotation, _, let to):
            applyFormProperties(to, to: annotation)
        case .added(let annotation, let pageIndex):
            document?.page(at: pageIndex)?.addAnnotation(annotation)
            if annotation.type == "Widget" { refreshFormState(markModified: false) }
        case .removed(let annotation, let pageIndex):
            document?.page(at: pageIndex)?.removeAnnotation(annotation)
            if annotation.type == "Widget" { refreshFormState(markModified: false) }
        case .transformed(let annotation, _, _, let toGeometry):
            applyGeometry(toGeometry, to: annotation)
        case .styled(let annotation, _, _, let toStyle):
            applyStyle(toStyle, to: annotation)
        }
    }

    private func applyInverse(of action: AnnotationHistoryAction) {
        switch action {
        case .batch(let actions): actions.reversed().forEach { applyInverse(of: $0) }
        case .fieldOrder(let from, _): applyFieldOrder(from)
        case .formProperties(let annotation, let from, _):
            applyFormProperties(from, to: annotation)
        case .added(let annotation, let pageIndex):
            document?.page(at: pageIndex)?.removeAnnotation(annotation)
            if annotation.type == "Widget" { refreshFormState(markModified: false) }
        case .removed(let annotation, let pageIndex):
            document?.page(at: pageIndex)?.addAnnotation(annotation)
            if annotation.type == "Widget" { refreshFormState(markModified: false) }
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
            // Moving changes only annotation.bounds; local ink points need only resizing.
            path.apply(CGAffineTransform(
                scaleX: updatedBounds.width / originalBounds.width,
                y: updatedBounds.height / originalBounds.height
            ))
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
        scheduleAnnotationSave()
    }

    private func finishAnnotationStyleChange() {
        isModified = true
        refreshAnnotations()
        scheduleAnnotationSave()
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
            if deferredPreparation { isPreparingDocument = true }
            else { prepareSynchronously(document) }
        }
    }

    private func prepareSynchronously(_ document: PDFDocument) {
        outlineEntries = Self.flattenOutline(document.outlineRoot)
        configureForms(in: document)
        refreshAnnotations()
        preparationComplete = true
    }

    /// Keeps live PDFKit objects on the main actor, yielding between small metadata batches.
    func prepareForReading() async {
        guard !preparationComplete, let document, !document.isLocked else { return }
        if let preparationTask { await preparationTask.value; return }
        isPreparingDocument = true
        let task = Task { @MainActor in
            defer { self.isPreparingDocument = false }
            var fields: [FormField] = []
            var annotations: [DocumentAnnotation] = []
            self.preparationBatchCount = 0
            self.longestPreparationBatchMilliseconds = 0
            for start in stride(from: 0, to: document.pageCount, by: 8) {
                await Task.yield()
                guard !Task.isCancelled else { return }
                let batchStart = CFAbsoluteTimeGetCurrent()
                let range = start..<min(start + 8, document.pageCount)
                autoreleasepool {
                    fields.append(contentsOf: Self.formFields(in: document, pages: range))
                    annotations.append(contentsOf: Self.annotations(in: document, pages: range))
                }
                self.longestPreparationBatchMilliseconds = max(self.longestPreparationBatchMilliseconds, (CFAbsoluteTimeGetCurrent() - batchStart) * 1000)
                self.preparationBatchCount += 1
            }
            guard !Task.isCancelled else { return }
            self.outlineEntries = Self.flattenOutline(document.outlineRoot)
            self.configureForms(in: document, preparedFields: fields)
            self.annotations = annotations
            self.preparationComplete = true
        }
        preparationTask = task
        await withTaskCancellationHandler(operation: { await task.value }, onCancel: { task.cancel() })
        preparationTask = nil
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
            if selected.annotation.type?.lowercased() == "widget",
               let field = formFields.first(where: { $0.annotation === selected.annotation }) {
                selectedAnnotation = DocumentAnnotation(
                    id: field.id,
                    annotation: field.annotation,
                    pageIndex: field.pageIndex,
                    title: field.title,
                    excerpt: field.kind.title,
                    icon: formFieldIcon(field.kind),
                    color: field.annotation.color
                )
            } else {
                selectedAnnotation = annotations.first { $0.annotation === selected.annotation }
            }
        }
    }

    private func configureForms(in document: PDFDocument, preparedFields: [FormField]? = nil) {
        canFillForms = document.allowsFormFieldEntry
        let loadedFields = preparedFields ?? Self.formFields(in: document)
        let repairedBorders = FormFieldBorderRepair.repair(in: document, fields: loadedFields.map(\.annotation), sourceURL: item.url)
        formFields = Self.orderedFormFields(repairedBorders ? Self.formFields(in: document) : loadedFields)
        if Self.containsXFA(in: document) {
            formCompatibilityNotice = formFields.isEmpty
                ? "This PDF uses an XFA form, which iOS cannot fill."
                : "This PDF also contains XFA content. Only its standard fields are editable."
        } else {
            formCompatibilityNotice = nil
        }
        savedFormValues = currentFormValues()
        if repairedBorders {
            isModified = true
            scheduleAnnotationSave()
        }
    }

    private func currentFormValues() -> [String: FormFieldSnapshot] {
        Dictionary(uniqueKeysWithValues: formFields.map {
            ($0.id, FormFieldSnapshot(
                stringValue: $0.annotation.widgetStringValue ?? "",
                buttonState: $0.annotation.buttonWidgetState.rawValue
            ))
        })
    }

    private static func formFields(in document: PDFDocument, pages: Range<Int>? = nil) -> [FormField] {
        var fields: [FormField] = []
        for pageIndex in pages ?? 0..<document.pageCount {
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
        return orderedFormFields(fields)
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

    private static func annotations(in document: PDFDocument, pages: Range<Int>? = nil) -> [DocumentAnnotation] {
        var items: [DocumentAnnotation] = []
        for pageIndex in pages ?? 0..<document.pageCount {
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

final class VisibleSignatureField: PDFAnnotation {
    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        super.draw(with: box, in: context)
        context.saveGState()
        context.setStrokeColor(FolikTheme.annotationBlue.cgColor)
        context.setLineWidth(1.5)
        context.stroke(bounds.insetBy(dx: 0.75, dy: 0.75))
        context.restoreGState()
    }
}

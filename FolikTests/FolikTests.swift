import Combine
import PDFKit
import UIKit
import XCTest
@testable import Folik

@MainActor
final class DocumentLibraryTests: XCTestCase {
    private var workspace: URL!
    private var libraryDirectory: URL!

    override func setUpWithError() throws {
        workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("FolikTests-\(UUID().uuidString)", isDirectory: true)
        libraryDirectory = workspace.appendingPathComponent("Library", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let workspace {
            try? FileManager.default.removeItem(at: workspace)
        }
        workspace = nil
        libraryDirectory = nil
    }

    func testImportReadsMetadataAndCopiesIntoLibrary() async throws {
        let source = workspace.appendingPathComponent("Field Notes.pdf")
        try PDFTestFixture.write(to: source, pages: ["First", "Second"])
        let library = DocumentLibrary(documentsDirectory: libraryDirectory)

        let imported = await library.importDocuments(at: [source])

        let document = try XCTUnwrap(imported.first)
        XCTAssertEqual(imported.count, 1)
        XCTAssertEqual(document.displayName, "Field Notes")
        XCTAssertEqual(document.pageCount, 2)
        XCTAssertGreaterThan(document.fileSize, 0)
        XCTAssertEqual(document.url.deletingLastPathComponent(), libraryDirectory)
        XCTAssertTrue(FileManager.default.fileExists(atPath: document.url.path))
    }

    func testDuplicateImportsReceiveStableCopyNames() async throws {
        let source = workspace.appendingPathComponent("Report.pdf")
        try PDFTestFixture.write(to: source, pages: ["Report"])
        let library = DocumentLibrary(documentsDirectory: libraryDirectory)

        _ = await library.importDocuments(at: [source])
        _ = await library.importDocuments(at: [source])

        XCTAssertEqual(Set(library.documents.map(\.url.lastPathComponent)), ["Report.pdf", "Report 2.pdf"])
    }

    func testDuplicatePreservesPDFAndOrganizationWithoutCopyingReadingProgress() throws {
        let source = libraryDirectory.appendingPathComponent("Report.pdf")
        try FileManager.default.createDirectory(at: libraryDirectory, withIntermediateDirectories: true)
        try PDFTestFixture.write(to: source, pages: ["Report"])
        let sourceBytes = try Data(contentsOf: source)
        let library = DocumentLibrary(documentsDirectory: libraryDirectory)
        let original = try XCTUnwrap(library.documents.first)
        try library.organize(original, folder: "Work", tags: ["review"])
        try library.setFavorite(true, for: [original])

        let copy = try library.duplicate(original)

        XCTAssertEqual(copy.url.lastPathComponent, "Report Copy.pdf")
        XCTAssertEqual(try Data(contentsOf: copy.url), sourceBytes)
        XCTAssertEqual(library.metadata(for: copy).folder, "Work")
        XCTAssertEqual(library.metadata(for: copy).tags, ["review"])
        XCTAssertTrue(library.metadata(for: copy).isFavorite)
    }

    func testNonPDFInputIsIgnored() async throws {
        let source = workspace.appendingPathComponent("notes.txt")
        try Data("Not a PDF".utf8).write(to: source)
        let library = DocumentLibrary(documentsDirectory: libraryDirectory)

        let imported = await library.importDocuments(at: [source])

        XCTAssertTrue(imported.isEmpty)
        XCTAssertTrue(library.documents.isEmpty)
        XCTAssertNil(library.errorMessage)
    }

    func testScannedImagesCreateAReadableLocalPDFWithPageOrientation() async throws {
        let library = DocumentLibrary(documentsDirectory: libraryDirectory)
        let portrait = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 900)).jpegData(
            withCompressionQuality: 0.9
        ) { context in
            UIColor.systemYellow.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 600, height: 900))
            NSString(string: "Folik portrait receipt").draw(
                at: CGPoint(x: 48, y: 72),
                withAttributes: [
                    .font: UIFont.systemFont(ofSize: 42, weight: .bold),
                    .foregroundColor: UIColor.black
                ]
            )
        }
        let landscape = UIGraphicsImageRenderer(size: CGSize(width: 900, height: 600)).jpegData(
            withCompressionQuality: 0.9
        ) { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 900, height: 600))
            NSString(string: "Folik landscape invoice").draw(
                at: CGPoint(x: 48, y: 72),
                withAttributes: [
                    .font: UIFont.systemFont(ofSize: 42, weight: .bold),
                    .foregroundColor: UIColor.white
                ]
            )
        }

        let imported = await library.importScannedPages(
            [portrait, landscape],
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let document = try XCTUnwrap(imported)
        XCTAssertTrue(document.displayName.hasPrefix("Scan "))
        XCTAssertEqual(document.pageCount, 2)
        XCTAssertEqual(document.url.deletingLastPathComponent(), libraryDirectory)
        let pdf = try XCTUnwrap(PDFDocument(url: document.url))
        XCTAssertEqual(pdf.pageCount, 2)
        XCTAssertEqual(pdf.page(at: 0)?.bounds(for: .mediaBox).size, CGSize(width: 612, height: 792))
        XCTAssertEqual(pdf.page(at: 1)?.bounds(for: .mediaBox).size, CGSize(width: 792, height: 612))
        let searchableText = pdf.string?.lowercased() ?? ""
        XCTAssertTrue(searchableText.contains("portrait receipt"), searchableText)
        XCTAssertTrue(searchableText.contains("landscape invoice"), searchableText)
    }

    func testEmptyScanShowsRecoverableErrorWithoutCreatingAFile() async {
        let library = DocumentLibrary(documentsDirectory: libraryDirectory)

        let imported = await library.importScannedPages([])

        XCTAssertNil(imported)
        XCTAssertEqual(
            library.errorMessage,
            "No scanned pages were available. Try scanning the document again."
        )
        XCTAssertTrue(library.documents.isEmpty)
    }

    func testDeleteRemovesTheLocalCopy() async throws {
        let source = workspace.appendingPathComponent("Disposable.pdf")
        try PDFTestFixture.write(to: source, pages: ["Disposable"])
        let suiteName = "FolikLibraryBookmarkTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let bookmarkStore = BookmarkStore(defaults: defaults)
        let readerStateStore = ReaderStateStore(defaults: defaults)
        let library = DocumentLibrary(
            documentsDirectory: libraryDirectory,
            bookmarkStore: bookmarkStore,
            readerStateStore: readerStateStore
        )
        let imported = await library.importDocuments(at: [source])
        let document = try XCTUnwrap(imported.first)
        bookmarkStore.save([0], for: document.url)
        readerStateStore.save(ReaderState(pageIndex: 0, layout: .singlePage), for: document.url)

        library.delete(document)

        XCTAssertTrue(library.documents.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: document.url.path))
        XCTAssertTrue(bookmarkStore.bookmarks(for: document.url, pageCount: 1).isEmpty)
        XCTAssertEqual(readerStateStore.state(for: document.url, pageCount: 1), ReaderState(pageIndex: 0, layout: .continuous))
    }

    func testRenamePreservesOrganizationBookmarksFavoriteAndReaderState() async throws {
        let source = workspace.appendingPathComponent("Original.pdf")
        try PDFTestFixture.write(to: source, pages: ["One", "Two"])
        let suiteName = "FolikRenameTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let bookmarkStore = BookmarkStore(defaults: defaults)
        let readerStateStore = ReaderStateStore(defaults: defaults)
        let library = DocumentLibrary(
            documentsDirectory: libraryDirectory,
            bookmarkStore: bookmarkStore,
            readerStateStore: readerStateStore
        )
        let imported = await library.importDocuments(at: [source])
        let original = try XCTUnwrap(imported.first)
        try library.organize(original, folder: "Work", tags: ["draft"])
        try library.setFavorite(true, for: [original])
        bookmarkStore.save([1], for: original.url)
        readerStateStore.save(ReaderState(pageIndex: 1, layout: .twoUp), for: original.url)

        let renamed = try library.rename(original, to: "Final Report")

        XCTAssertEqual(renamed.url.lastPathComponent, "Final Report.pdf")
        XCTAssertFalse(FileManager.default.fileExists(atPath: original.url.path))
        XCTAssertEqual(library.metadata(for: renamed).folder, "Work")
        XCTAssertEqual(library.metadata(for: renamed).tags, ["draft"])
        XCTAssertTrue(library.metadata(for: renamed).isFavorite)
        XCTAssertEqual(bookmarkStore.bookmarks(for: renamed.url, pageCount: 2), [1])
        XCTAssertEqual(readerStateStore.state(for: renamed.url, pageCount: 2), ReaderState(pageIndex: 1, layout: .twoUp))
    }

    func testRenameRejectsAnExistingNameWithoutChangingFiles() async throws {
        let first = workspace.appendingPathComponent("First.pdf")
        let second = workspace.appendingPathComponent("Second.pdf")
        try PDFTestFixture.write(to: first, pages: ["First"])
        try PDFTestFixture.write(to: second, pages: ["Second"])
        let library = DocumentLibrary(documentsDirectory: libraryDirectory)
        _ = await library.importDocuments(at: [first, second])
        let firstDocument = try XCTUnwrap(library.documents.first { $0.displayName == "First" })

        XCTAssertThrowsError(try library.rename(firstDocument, to: "Second"))
        XCTAssertEqual(Set(library.documents.map(\.url.lastPathComponent)), ["First.pdf", "Second.pdf"])
    }
}

@MainActor
final class DocumentSessionTests: XCTestCase {
    private var workspace: URL!

    override func setUpWithError() throws {
        workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("FolikSessionTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let workspace {
            try? FileManager.default.removeItem(at: workspace)
        }
        workspace = nil
    }

    func testSessionLoadsPagesAndBoundsNavigation() throws {
        let url = workspace.appendingPathComponent("Guide.pdf")
        try PDFTestFixture.write(to: url, pages: ["One", "Two"])
        let session = DocumentSession(item: PDFTestFixture.item(for: url))

        XCTAssertEqual(session.pageCount, 2)
        XCTAssertEqual(session.pageLabel, "1 of 2")

        session.goToPage(99)
        guard case .goToPage(let index) = session.command?.action else {
            return XCTFail("Expected a page-navigation command")
        }
        XCTAssertEqual(index, 1)
    }

    func testReaderPositionAndLayoutPersistPerDocument() throws {
        let suiteName = "FolikReaderStateTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = ReaderStateStore(defaults: defaults)
        let url = workspace.appendingPathComponent("Guide.pdf")
        try PDFTestFixture.write(to: url, pages: ["One", "Two", "Three"])
        store.save(ReaderState(pageIndex: 2, layout: .twoUp), for: url)

        let session = DocumentSession(item: PDFTestFixture.item(for: url), readerStateStore: store)

        XCTAssertEqual(session.pageIndex, 2)
        XCTAssertEqual(session.layout, .twoUp)
        guard case .restore(let pageIndex, let layout) = session.command?.action else {
            return XCTFail("Expected a reader-state restoration command")
        }
        XCTAssertEqual(pageIndex, 2)
        XCTAssertEqual(layout, .twoUp)
        session.reportPage(session.document?.page(at: 1))
        session.setLayout(.singlePage)
        XCTAssertEqual(store.state(for: url, pageCount: 3), ReaderState(pageIndex: 1, layout: .singlePage))
    }

    func testContinueReadingTracksOpensPreservesDismissalAndMigratesRename() throws {
        let suite = "FolikResume-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ReaderStateStore(defaults: defaults)
        let first = workspace.appendingPathComponent("First.pdf")
        let second = workspace.appendingPathComponent("Second.pdf")
        try PDFTestFixture.write(to: first, pages: ["1", "2"])
        try PDFTestFixture.write(to: second, pages: ["1"])
        let documents = [PDFTestFixture.item(for: first), PDFTestFixture.item(for: second)]
        store.save(ReaderState(pageIndex: 1, layout: .singlePage), for: first)
        XCTAssertNil(store.mostRecent(in: documents), "Old reading state must not invent an open date")
        store.markOpened(first, at: Date(timeIntervalSince1970: 100))
        store.markOpened(second, at: Date(timeIntervalSince1970: 200))
        store.save(ReaderState(pageIndex: 1, layout: .twoUp), for: first)
        XCTAssertEqual(store.mostRecent(in: documents)?.document.url, second)
        store.dismissResume(for: second)
        XCTAssertNil(ReaderStateStore(defaults: defaults).mostRecent(in: documents))
        store.markOpened(first, at: Date(timeIntervalSince1970: 300))
        XCTAssertEqual(store.mostRecent(in: documents)?.pageIndex, 1)
        let renamed = workspace.appendingPathComponent("Renamed.pdf")
        try FileManager.default.moveItem(at: first, to: renamed)
        store.moveState(from: first, to: renamed)
        XCTAssertEqual(store.mostRecent(in: [PDFTestFixture.item(for: renamed)])?.pageIndex, 1)
        store.removeState(for: renamed)
        XCTAssertNil(store.mostRecent(in: [PDFTestFixture.item(for: renamed)]))
    }

    func testReaderStateClampsStalePageIndexes() throws {
        let suiteName = "FolikReaderBoundsTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = ReaderStateStore(defaults: defaults)
        let url = workspace.appendingPathComponent("Short.pdf")
        try PDFTestFixture.write(to: url, pages: ["One", "Two"])
        store.save(ReaderState(pageIndex: 99, layout: .continuous), for: url)

        let session = DocumentSession(item: PDFTestFixture.item(for: url), readerStateStore: store)

        XCTAssertEqual(session.pageIndex, 1)
        XCTAssertEqual(store.state(for: url, pageCount: 2).pageIndex, 1)
    }

    func testBookmarksPersistPerDocumentWithoutModifyingPDF() throws {
        let suiteName = "FolikBookmarkTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = BookmarkStore(defaults: defaults)
        let firstURL = workspace.appendingPathComponent("Guide.pdf")
        let secondURL = workspace.appendingPathComponent("Notes.pdf")
        try PDFTestFixture.write(to: firstURL, pages: ["One", "Two"])
        try PDFTestFixture.write(to: secondURL, pages: ["Only"])
        let originalModificationDate = try firstURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate

        let session = DocumentSession(item: PDFTestFixture.item(for: firstURL), bookmarkStore: store)
        session.toggleCurrentPageBookmark()

        XCTAssertEqual(session.bookmarkedPageIndices, [0])
        XCTAssertFalse(session.isModified)
        XCTAssertEqual(
            try firstURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
            originalModificationDate
        )

        let reopened = DocumentSession(item: PDFTestFixture.item(for: firstURL), bookmarkStore: store)
        let otherDocument = DocumentSession(item: PDFTestFixture.item(for: secondURL), bookmarkStore: store)
        XCTAssertEqual(reopened.bookmarkedPageIndices, [0])
        XCTAssertTrue(otherDocument.bookmarkedPageIndices.isEmpty)
    }

    func testBookmarkStoreDropsPageIndexesOutsideDocumentBounds() throws {
        let suiteName = "FolikBookmarkBoundsTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = BookmarkStore(defaults: defaults)
        let url = workspace.appendingPathComponent("Short.pdf")
        try PDFTestFixture.write(to: url, pages: ["One", "Two"])
        store.save([-1, 0, 8], for: url)

        let session = DocumentSession(item: PDFTestFixture.item(for: url), bookmarkStore: store)

        XCTAssertEqual(session.bookmarkedPageIndices, [0])
        XCTAssertEqual(store.bookmarks(for: url, pageCount: 2), [0])
    }

    func testIncrementalSearchFindsTextWithoutBlockingTheCaller() async throws {
        let url = workspace.appendingPathComponent("Searchable.pdf")
        try PDFTestFixture.write(to: url, pages: ["A quiet haystack", "Folik needle appears in useful context", "Another needle result"])
        let session = DocumentSession(item: PDFTestFixture.item(for: url))

        session.search(for: "needle")
        XCTAssertTrue(session.isSearching)

        let deadline = ContinuousClock.now + .seconds(3)
        while session.isSearching && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }

        XCTAssertFalse(session.isSearching)
        XCTAssertEqual(session.searchMatches.count, 2)
        XCTAssertEqual(session.searchMatches.first?.pageIndex, 1)
        XCTAssertTrue(session.searchMatches.first?.excerpt.contains("useful context") == true)
        XCTAssertEqual(session.searchProgress, 1)
        XCTAssertEqual(session.selectedSearchMatchIndex, 0)

        session.moveToSearchMatch(offset: -1)
        XCTAssertEqual(session.selectedSearchMatchIndex, 1)
    }

    func testSelectionAvailabilityPublishesOnlyWhenItsValueChanges() throws {
        let url = workspace.appendingPathComponent("Selection.pdf")
        try PDFTestFixture.write(to: url, pages: ["Selectable text"])
        let session = DocumentSession(item: PDFTestFixture.item(for: url))
        let selection = try XCTUnwrap(
            session.document?.findString("Selectable", withOptions: .caseInsensitive).first
        )
        var reportedValues: [Bool] = []
        let observation = session.$hasTextSelection
            .dropFirst()
            .sink { reportedValues.append($0) }

        session.reportSelection(selection)
        session.reportSelection(selection)
        session.reportSelection(nil)
        session.reportSelection(nil)

        XCTAssertEqual(reportedValues, [true, false])
        withExtendedLifetime(observation) {}
    }

    func testFormFieldChangesPersistAfterReopeningDocument() throws {
        let url = workspace.appendingPathComponent("Application.pdf")
        try PDFTestFixture.writeForm(to: url)
        let session = DocumentSession(item: PDFTestFixture.item(for: url))

        let field = try XCTUnwrap(session.formFields.first)
        XCTAssertEqual(field.title, "Full name")
        XCTAssertEqual(field.kind, .text)
        XCTAssertTrue(session.canFillForms)
        XCTAssertFalse(field.isFilled)

        field.annotation.widgetStringValue = "Joseph Spears"
        session.noteFormEditing()

        XCTAssertTrue(session.isModified)
        XCTAssertEqual(session.completedFormFieldCount, 1)

        session.persistChanges()
        XCTAssertFalse(session.isModified)

        let reopened = try XCTUnwrap(PDFDocument(url: url))
        let savedField = try XCTUnwrap(reopened.page(at: 0)?.annotations.first(where: { $0.fieldName == "Full name" }))
        XCTAssertEqual(savedField.widgetStringValue, "Joseph Spears")
    }

    func testCompatibilityFormClassifiesStandardWidgetsAndGroupsRadioOptions() throws {
        let url = workspace.appendingPathComponent("Compatibility.pdf")
        try PDFTestFixture.writeCompatibilityForm(to: url)
        let session = DocumentSession(item: PDFTestFixture.item(for: url))

        XCTAssertEqual(session.formFields.count, 7)
        XCTAssertEqual(session.formFieldCount, 6)
        XCTAssertEqual(session.fillableFormFieldCount, 5)
        XCTAssertEqual(session.completedFormFieldCount, 1)
        XCTAssertEqual(session.requiredFormFieldCount, 2)
        XCTAssertEqual(session.remainingRequiredFormFieldCount, 2)
        XCTAssertEqual(session.formFields.first(where: { $0.title == "Full name" })?.kind, .text)
        XCTAssertEqual(session.formFields.first(where: { $0.title == "Comments" })?.kind, .multilineText)
        XCTAssertEqual(session.formFields.first(where: { $0.title == "Subscribe" })?.kind, .checkbox)
        XCTAssertEqual(session.formFields.filter { $0.title == "Contact preference" }.map(\.kind), [.radio, .radio])
        XCTAssertEqual(session.formFields.first(where: { $0.title == "Favorite color" })?.kind, .choice)

        let signature = try XCTUnwrap(session.formFields.first(where: { $0.title == "Approval" }))
        XCTAssertEqual(signature.kind, .signature)
        XCTAssertFalse(signature.isEditable)
        XCTAssertEqual(
            signature.limitation,
            "Use Annotations > Add > Signature for a visual signature. Certificate signing isn't supported."
        )
    }

    func testButtonChoiceAndMultilineValuesPersistAndReopen() throws {
        let url = workspace.appendingPathComponent("Compatibility.pdf")
        try PDFTestFixture.writeCompatibilityForm(to: url)
        let session = DocumentSession(item: PDFTestFixture.item(for: url))

        let comments = try XCTUnwrap(session.formFields.first(where: { $0.title == "Comments" }))
        let checkbox = try XCTUnwrap(session.formFields.first(where: { $0.title == "Subscribe" }))
        let email = try XCTUnwrap(session.formFields.first(where: {
            $0.title == "Contact preference" && $0.annotation.buttonWidgetStateString == "Email"
        }))
        let choice = try XCTUnwrap(session.formFields.first(where: { $0.title == "Favorite color" }))

        comments.annotation.widgetStringValue = "Line one\nLine two"
        checkbox.annotation.buttonWidgetState = .onState
        email.annotation.buttonWidgetState = .onState
        choice.annotation.widgetStringValue = "Blue"
        session.noteFormEditing()

        XCTAssertTrue(session.isModified)
        XCTAssertEqual(session.completedFormFieldCount, 4)
        session.persistChanges()

        let reopened = try XCTUnwrap(PDFDocument(url: url))
        let annotations = (0..<reopened.pageCount).flatMap { reopened.page(at: $0)?.annotations ?? [] }
        XCTAssertEqual(annotations.first(where: { $0.fieldName == "Comments" })?.widgetStringValue, "Line one\nLine two")
        XCTAssertEqual(annotations.first(where: { $0.fieldName == "Subscribe" })?.buttonWidgetState, .onState)
        XCTAssertEqual(annotations.first(where: { $0.buttonWidgetStateString == "Email" })?.buttonWidgetState, .onState)
        XCTAssertEqual(annotations.first(where: { $0.fieldName == "Favorite color" })?.widgetStringValue, "Blue")
        XCTAssertTrue(PDFTestFixture.hasCanonicalFormFieldTree(reopened))
    }

    func testRevertRestoresButtonStatesAndChoiceValues() throws {
        let url = workspace.appendingPathComponent("Compatibility.pdf")
        try PDFTestFixture.writeCompatibilityForm(to: url)
        let session = DocumentSession(item: PDFTestFixture.item(for: url))
        let checkbox = try XCTUnwrap(session.formFields.first(where: { $0.title == "Subscribe" }))
        let choice = try XCTUnwrap(session.formFields.first(where: { $0.title == "Favorite color" }))

        checkbox.annotation.buttonWidgetState = .onState
        choice.annotation.widgetStringValue = "Blue"
        session.noteFormEditing()
        session.revertFormChanges()

        XCTAssertFalse(session.isModified)
        XCTAssertEqual(checkbox.annotation.buttonWidgetState, .offState)
        XCTAssertEqual(choice.annotation.widgetStringValue, "Red")
        XCTAssertEqual(session.completedFormFieldCount, 1)
    }

    func testNextIncompleteFieldPrioritizesRequiredLogicalFields() throws {
        let url = workspace.appendingPathComponent("Compatibility.pdf")
        try PDFTestFixture.writeCompatibilityForm(to: url)
        let session = DocumentSession(item: PDFTestFixture.item(for: url))

        session.goToNextIncompleteFormField()
        guard case .goToAnnotation(let first, _) = session.command?.action else {
            return XCTFail("Expected navigation to the first required field")
        }
        XCTAssertEqual(first.fieldName, "Full name")

        first.widgetStringValue = "Joseph Spears"
        session.noteFormEditing()
        session.goToNextIncompleteFormField()
        guard case .goToAnnotation(let second, _) = session.command?.action else {
            return XCTFail("Expected navigation to the remaining required field")
        }
        XCTAssertEqual(second.fieldName, "Contact preference")
    }

    func testXFAOnlyFormReportsAnExplicitCompatibilityNotice() throws {
        let url = workspace.appendingPathComponent("XFA.pdf")
        try PDFTestFixture.writeXFAForm(to: url)
        let session = DocumentSession(item: PDFTestFixture.item(for: url))

        XCTAssertTrue(session.formFields.isEmpty)
        XCTAssertEqual(session.formFieldCount, 0)
        XCTAssertEqual(session.formCompatibilityNotice, "This PDF uses an XFA form, which iOS cannot fill.")
    }

    func testInkAnnotationPersistsAndDeletionCanBeUndone() throws {
        let url = workspace.appendingPathComponent("Annotated.pdf")
        try PDFTestFixture.write(to: url, pages: ["Draw here"])
        let session = DocumentSession(item: PDFTestFixture.item(for: url))
        session.inkColor = .red
        session.inkLineWidth = 5

        session.addInkAnnotation(
            pageIndex: 0,
            points: [CGPoint(x: 80, y: 500), CGPoint(x: 120, y: 530), CGPoint(x: 170, y: 510)]
        )

        XCTAssertEqual(session.annotations.count, 1)
        XCTAssertEqual(session.annotations.first?.title, "Drawing")
        XCTAssertFalse(session.isModified)
        var reopened = try XCTUnwrap(PDFDocument(url: url))
        XCTAssertEqual(reopened.page(at: 0)?.annotations.filter { $0.type == "Ink" }.count, 1)

        let item = try XCTUnwrap(session.annotations.first)
        session.deleteAnnotation(item)
        XCTAssertTrue(session.annotations.isEmpty)
        XCTAssertTrue(session.canUndoAnnotation)
        reopened = try XCTUnwrap(PDFDocument(url: url))
        XCTAssertEqual(reopened.page(at: 0)?.annotations.filter { $0.type == "Ink" }.count, 0)

        session.undoAnnotationAction()
        XCTAssertEqual(session.annotations.count, 1)
        XCTAssertTrue(session.canRedoAnnotation)
        reopened = try XCTUnwrap(PDFDocument(url: url))
        XCTAssertEqual(reopened.page(at: 0)?.annotations.filter { $0.type == "Ink" }.count, 1)

        session.redoAnnotationAction()
        XCTAssertTrue(session.annotations.isEmpty)
        session.undoAnnotationAction()
        XCTAssertEqual(session.annotations.count, 1)
    }

    func testNotesTextBoxesAndShapesPersistAfterPlacement() throws {
        let url = workspace.appendingPathComponent("Placed Annotations.pdf")
        try PDFTestFixture.write(to: url, pages: ["Place here"])
        let session = DocumentSession(item: PDFTestFixture.item(for: url))

        session.beginAnnotationPlacement(.note, text: "Review this paragraph")
        session.placeAnnotation(pageIndex: 0, point: CGPoint(x: 90, y: 650))
        session.beginAnnotationPlacement(.textBox, text: "Approved for release")
        session.placeAnnotation(pageIndex: 0, point: CGPoint(x: 300, y: 560))
        session.beginAnnotationPlacement(.rectangle)
        session.placeAnnotation(pageIndex: 0, point: CGPoint(x: 280, y: 430))
        session.beginAnnotationPlacement(.circle)
        session.placeAnnotationAtCurrentPageCenter()

        XCTAssertEqual(session.annotations.map(\.title), ["Note", "Text box", "Shape", "Shape"])
        XCTAssertEqual(session.annotations.first?.excerpt, "Review this paragraph")
        XCTAssertTrue(session.canUndoAnnotation)

        let reopened = try XCTUnwrap(PDFDocument(url: url))
        let types = reopened.page(at: 0)?.annotations.compactMap(\.type) ?? []
        XCTAssertEqual(types, ["Text", "Popup", "FreeText", "Square", "Circle"])
        XCTAssertEqual(reopened.page(at: 0)?.annotations.first?.contents, "Review this paragraph")

        let note = try XCTUnwrap(session.annotations.first(where: { $0.title == "Note" }))
        session.deleteAnnotation(note)
        let withoutNote = try XCTUnwrap(PDFDocument(url: url))
        XCTAssertFalse(withoutNote.page(at: 0)?.annotations.contains(where: { $0.type == "Text" }) == true)
        XCTAssertFalse(withoutNote.page(at: 0)?.annotations.contains(where: { $0.type == "Popup" }) == true)
        session.undoAnnotationAction()
        XCTAssertTrue(session.annotations.contains(where: { $0.title == "Note" }))
    }

    func testStandardStampPersistsAndCanBeMovedAndResized() throws {
        let url = workspace.appendingPathComponent("Stamped Review.pdf")
        try PDFTestFixture.write(to: url, pages: ["Review this document"])
        let session = DocumentSession(item: PDFTestFixture.item(for: url))

        session.beginStampPlacement(.approved)
        session.placeAnnotation(pageIndex: 0, point: CGPoint(x: 300, y: 430))

        let stamp = try XCTUnwrap(session.annotations.first)
        XCTAssertEqual(stamp.title, "Approved")
        XCTAssertEqual(stamp.annotation.type, "Stamp")
        XCTAssertEqual(stamp.annotation.stampName, "Approved")
        XCTAssertTrue(session.canMoveAnnotation(stamp.annotation))

        let originalBounds = stamp.annotation.bounds
        session.beginAnnotationEditing()
        session.selectAnnotation(stamp.annotation, pageIndex: 0)
        XCTAssertTrue(session.selectedAnnotationCanResize)
        session.moveSelectedAnnotation(horizontal: 12, vertical: -12)
        session.resizeSelectedAnnotation(by: 10)

        let reopened = try XCTUnwrap(PDFDocument(url: url))
        let persisted = try XCTUnwrap(reopened.page(at: 0)?.annotations.first { $0.type == "Stamp" })
        XCTAssertEqual(
            persisted.stampName?.trimmingCharacters(in: CharacterSet(charactersIn: "/")),
            "Approved"
        )
        XCTAssertEqual(persisted.contents, "Approved")
        XCTAssertEqual(persisted.bounds.origin.x, originalBounds.origin.x + 2, accuracy: 0.01)
        XCTAssertEqual(persisted.bounds.origin.y, originalBounds.origin.y - 22, accuracy: 0.01)
        XCTAssertEqual(persisted.bounds.width, originalBounds.width + 20, accuracy: 0.01)
        XCTAssertEqual(persisted.bounds.height, originalBounds.height + 20, accuracy: 0.01)
    }

    func testSelectedAnnotationMovesResizesAndParticipatesInHistory() throws {
        let url = workspace.appendingPathComponent("Transformed Annotation.pdf")
        try PDFTestFixture.write(to: url, pages: ["Transform here"])
        let session = DocumentSession(item: PDFTestFixture.item(for: url))
        session.beginAnnotationPlacement(.rectangle)
        session.placeAnnotation(pageIndex: 0, point: CGPoint(x: 250, y: 430))

        let shape = try XCTUnwrap(session.annotations.first)
        let originalBounds = shape.annotation.bounds
        session.beginAnnotationEditing()
        session.selectAnnotation(shape.annotation, pageIndex: 0)
        XCTAssertTrue(session.canMoveAnnotation(shape.annotation))
        XCTAssertTrue(session.selectedAnnotationCanResize)

        let circle = PDFAnnotation(bounds: .zero, forType: .circle, withProperties: nil)
        let markup = PDFAnnotation(bounds: .zero, forType: .highlight, withProperties: nil)
        XCTAssertTrue(session.canMoveAnnotation(circle))
        XCTAssertFalse(session.canMoveAnnotation(markup))

        session.moveSelectedAnnotation(horizontal: 12, vertical: -12)
        let movedBounds = shape.annotation.bounds
        XCTAssertEqual(movedBounds.origin.x, originalBounds.origin.x + 12, accuracy: 0.01)
        XCTAssertEqual(movedBounds.origin.y, originalBounds.origin.y - 12, accuracy: 0.01)

        session.undoAnnotationAction()
        XCTAssertEqual(shape.annotation.bounds, originalBounds)
        session.redoAnnotationAction()
        XCTAssertEqual(shape.annotation.bounds, movedBounds)

        session.resizeSelectedAnnotation(by: 10)
        let resizedBounds = shape.annotation.bounds
        XCTAssertEqual(resizedBounds.width, movedBounds.width + 20, accuracy: 0.01)
        XCTAssertEqual(resizedBounds.height, movedBounds.height + 20, accuracy: 0.01)

        let reopened = try XCTUnwrap(PDFDocument(url: url))
        let persistedShape = try XCTUnwrap(reopened.page(at: 0)?.annotations.first { $0.type == "Square" })
        XCTAssertEqual(persistedShape.bounds.width, resizedBounds.width, accuracy: 0.01)
        XCTAssertEqual(persistedShape.bounds.height, resizedBounds.height, accuracy: 0.01)
    }

    func testAnnotationAppearanceChangesPersistAndParticipateInHistory() throws {
        let url = workspace.appendingPathComponent("Styled Annotation.pdf")
        try PDFTestFixture.write(to: url, pages: ["Style this annotation"])
        let session = DocumentSession(item: PDFTestFixture.item(for: url))
        session.beginAnnotationPlacement(.rectangle)
        session.placeAnnotationAtCurrentPageCenter()

        let shape = try XCTUnwrap(session.annotations.first)
        session.beginAnnotationEditing()
        session.selectAnnotation(shape.annotation, pageIndex: 0)
        XCTAssertTrue(session.selectedAnnotationCanChangeColor)
        XCTAssertTrue(session.selectedAnnotationCanChangeLineWidth)
        XCTAssertTrue(session.selectedAnnotationUsesColor(.blue))
        XCTAssertEqual(try XCTUnwrap(session.selectedAnnotationLineWidth), 3, accuracy: 0.01)

        session.setSelectedAnnotationColor(.red)
        XCTAssertTrue(session.selectedAnnotationUsesColor(.red))
        session.setSelectedAnnotationLineWidth(6)
        XCTAssertEqual(try XCTUnwrap(shape.annotation.border?.lineWidth), 6, accuracy: 0.01)

        session.undoAnnotationAction()
        XCTAssertEqual(try XCTUnwrap(shape.annotation.border?.lineWidth), 3, accuracy: 0.01)
        XCTAssertTrue(session.selectedAnnotationUsesColor(.red))
        session.undoAnnotationAction()
        XCTAssertTrue(session.selectedAnnotationUsesColor(.blue))
        session.redoAnnotationAction()
        session.redoAnnotationAction()

        let reopened = try XCTUnwrap(PDFDocument(url: url))
        let persisted = try XCTUnwrap(reopened.page(at: 0)?.annotations.first { $0.type == "Square" })
        XCTAssertEqual(try XCTUnwrap(persisted.border?.lineWidth), 6, accuracy: 0.01)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        XCTAssertTrue(persisted.color.getRed(&red, green: &green, blue: &blue, alpha: &alpha))
        XCTAssertEqual(red, 0.86, accuracy: 0.02)
        XCTAssertEqual(green, 0.25, accuracy: 0.02)
        XCTAssertEqual(blue, 0.24, accuracy: 0.02)
        XCTAssertNil(persisted.interiorColor)
    }

    func testTextMarkupRemainsAnchoredToItsSourceText() throws {
        let url = workspace.appendingPathComponent("Anchored Markup.pdf")
        try PDFTestFixture.write(to: url, pages: ["Anchored highlight"])
        let document = try XCTUnwrap(PDFDocument(url: url))
        let page = try XCTUnwrap(document.page(at: 0))
        let highlight = PDFAnnotation(
            bounds: CGRect(x: 72, y: 650, width: 180, height: 28),
            forType: .highlight,
            withProperties: nil
        )
        page.addAnnotation(highlight)
        XCTAssertTrue(document.write(to: url))

        let session = DocumentSession(item: PDFTestFixture.item(for: url))
        let markup = try XCTUnwrap(session.annotations.first)
        let originalBounds = markup.annotation.bounds
        session.beginAnnotationEditing()
        session.selectAnnotation(markup.annotation, pageIndex: 0)

        XCTAssertFalse(session.selectedAnnotationCanMove)
        XCTAssertFalse(session.selectedAnnotationCanResize)
        session.moveSelectedAnnotation(horizontal: 12, vertical: 12)
        XCTAssertEqual(markup.annotation.bounds, originalBounds)
    }

    func testDrawnSignatureIsSavedPlacedResizedAndReopened() throws {
        let store = SignatureStore(directoryURL: workspace.appendingPathComponent("Signatures", isDirectory: true))
        let asset = SignatureAsset(
            kind: .signature,
            strokes: [SignatureStroke(points: [
                SignaturePoint(x: 0.05, y: 0.70),
                SignaturePoint(x: 0.35, y: 0.25),
                SignaturePoint(x: 0.62, y: 0.72),
                SignaturePoint(x: 0.95, y: 0.35)
            ])],
            typedText: nil
        )
        let url = workspace.appendingPathComponent("Signed Drawing.pdf")
        try PDFTestFixture.write(to: url, pages: ["Sign here"])
        let session = DocumentSession(item: PDFTestFixture.item(for: url), signatureStore: store)

        session.saveSignatureAsset(asset)
        XCTAssertEqual(session.savedSignature, asset)
        session.beginSignaturePlacement(asset)
        session.placeAnnotationAtCurrentPageCenter()

        let signature = try XCTUnwrap(session.annotations.first(where: { $0.title == "Signature" }))
        XCTAssertEqual(signature.annotation.type, "Ink")
        XCTAssertEqual(signature.annotation.paths?.count, 1)
        let originalPathBounds = try XCTUnwrap(signature.annotation.paths?.first?.bounds)

        session.beginAnnotationEditing()
        session.selectAnnotation(signature.annotation, pageIndex: 0)
        session.resizeSelectedAnnotation(by: 10)
        let resizedPathBounds = try XCTUnwrap(signature.annotation.paths?.first?.bounds)
        XCTAssertGreaterThan(resizedPathBounds.width, originalPathBounds.width)
        session.undoAnnotationAction()
        let undonePathBounds = try XCTUnwrap(signature.annotation.paths?.first?.bounds)
        XCTAssertEqual(undonePathBounds.width, originalPathBounds.width, accuracy: 0.01)

        let reopened = try XCTUnwrap(PDFDocument(url: url))
        let persisted = try XCTUnwrap(reopened.page(at: 0)?.annotations.first { $0.userName == "Folik Signature" })
        XCTAssertEqual(persisted.type, "Ink")
        XCTAssertEqual(persisted.paths?.count, 1)

        let restoredSession = DocumentSession(item: PDFTestFixture.item(for: url), signatureStore: store)
        XCTAssertEqual(restoredSession.savedSignature, asset)
#if !targetEnvironment(simulator)
        let attributes = try FileManager.default.attributesOfItem(atPath: store.fileURL(for: .signature).path)
        XCTAssertEqual(attributes[.protectionKey] as? FileProtectionType, .completeUnlessOpen)
#else
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.fileURL(for: .signature).path))
#endif
    }

    func testTypedInitialsAreSavedAsEditableFreeText() throws {
        let store = SignatureStore(directoryURL: workspace.appendingPathComponent("Initials", isDirectory: true))
        let asset = SignatureAsset(kind: .initials, strokes: [], typedText: "JS")
        let url = workspace.appendingPathComponent("Signed Initials.pdf")
        try PDFTestFixture.write(to: url, pages: ["Initial here"])
        let session = DocumentSession(item: PDFTestFixture.item(for: url), signatureStore: store)

        session.saveSignatureAsset(asset)
        session.beginSignaturePlacement(asset)
        session.placeAnnotation(pageIndex: 0, point: CGPoint(x: 420, y: 180))

        let initials = try XCTUnwrap(session.annotations.first(where: { $0.title == "Initials" }))
        XCTAssertEqual(initials.annotation.type, "FreeText")
        XCTAssertEqual(initials.annotation.contents, "JS")
        let reopened = try XCTUnwrap(PDFDocument(url: url))
        let persisted = try XCTUnwrap(reopened.page(at: 0)?.annotations.first { $0.userName == "Folik Initials" })
        XCTAssertEqual(persisted.contents, "JS")
    }

    func testLegacySignatureMigratesToProtectedFileStorage() throws {
        let defaultsName = "FolikTests.Migration.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        let asset = SignatureAsset(kind: .signature, strokes: [], typedText: "Joseph Spears")
        let legacyKey = "com.x3nllc.Folik.saved-signature-v1"
        defaults.set(try JSONEncoder().encode(asset), forKey: legacyKey)
        let store = SignatureStore(
            directoryURL: workspace.appendingPathComponent("Migrated Signatures", isDirectory: true),
            legacyDefaults: defaults
        )

        XCTAssertEqual(store.load(.signature), asset)
        XCTAssertNil(defaults.data(forKey: legacyKey))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.fileURL(for: .signature).path))
    }

    func testEditableAndFlattenedExportsPreserveOriginal() throws {
        let source = workspace.appendingPathComponent("Completed Application.pdf")
        try PDFTestFixture.writeCompatibilityForm(to: source)
        let sourceSession = DocumentSession(item: PDFTestFixture.item(for: source))
        let name = try XCTUnwrap(sourceSession.formFields.first(where: { $0.title == "Full name" }))
        name.annotation.widgetStringValue = "Joseph Spears"
        sourceSession.noteFormEditing()
        sourceSession.beginAnnotationPlacement(.rectangle)
        sourceSession.placeAnnotationAtCurrentPageCenter()
        sourceSession.persistChanges()

        let sourceBefore = try XCTUnwrap(PDFDocument(url: source))
        let sourceAnnotationCount = (0..<sourceBefore.pageCount).reduce(0) {
            $0 + (sourceBefore.page(at: $1)?.annotations.count ?? 0)
        }
        let editableURL = try DocumentExporter.export(sourceURL: source, mode: .editable)
        let flattenedURL = try DocumentExporter.export(sourceURL: source, mode: .flattened)

        XCTAssertNotEqual(editableURL, source)
        XCTAssertNotEqual(flattenedURL, source)
        let editable = try XCTUnwrap(PDFDocument(url: editableURL))
        XCTAssertEqual(editable.pageCount, sourceBefore.pageCount)
        XCTAssertGreaterThan(editable.page(at: 0)?.annotations.count ?? 0, 0)
        XCTAssertEqual(
            editable.page(at: 0)?.annotations.first(where: { $0.fieldName == "Full name" })?.widgetStringValue,
            "Joseph Spears"
        )

        let flattened = try XCTUnwrap(PDFDocument(url: flattenedURL))
        XCTAssertEqual(flattened.pageCount, sourceBefore.pageCount)
        XCTAssertEqual(
            (0..<flattened.pageCount).reduce(0) { $0 + (flattened.page(at: $1)?.annotations.count ?? 0) },
            0
        )
        let sourceAfter = try XCTUnwrap(PDFDocument(url: source))
        XCTAssertEqual(
            (0..<sourceAfter.pageCount).reduce(0) { $0 + (sourceAfter.page(at: $1)?.annotations.count ?? 0) },
            sourceAnnotationCount
        )
    }

    func testOfficialIRSW9TextCheckboxSaveReopenAndFlatten() throws {
        let fixtureURL = try XCTUnwrap(
            Bundle(for: Self.self).url(
                forResource: "IRS-Form-W-9-2024",
                withExtension: "pdf",
                subdirectory: "Fixtures"
            ) ?? Bundle(for: Self.self).url(forResource: "IRS-Form-W-9-2024", withExtension: "pdf")
        )
        let workingURL = workspace.appendingPathComponent("Real W-9.pdf")
        try FileManager.default.copyItem(at: fixtureURL, to: workingURL)
        let session = DocumentSession(item: PDFTestFixture.item(for: workingURL))

        XCTAssertEqual(session.pageCount, 6)
        XCTAssertEqual(session.fillableFormFieldCount, 23)
        XCTAssertTrue(session.canFillForms)
        XCTAssertEqual(
            session.formCompatibilityNotice,
            "This PDF also contains XFA content. Only its standard fields are editable."
        )
        let textField = try XCTUnwrap(session.formFields.first(where: { $0.kind == .text }))
        XCTAssertFalse(textField.title.hasPrefix("topmostSubform"))
        let textFieldName = try XCTUnwrap(textField.annotation.fieldName)
        textField.annotation.widgetStringValue = "Folik Real PDF Test"
        let checkbox = try XCTUnwrap(session.formFields.first(where: { $0.kind == .checkbox }))
        let checkboxName = try XCTUnwrap(checkbox.annotation.fieldName)
        checkbox.annotation.buttonWidgetState = .onState
        session.noteFormEditing()
        session.persistChanges()

        let reopened = try XCTUnwrap(PDFDocument(url: workingURL))
        let widgets = (0..<reopened.pageCount).flatMap { reopened.page(at: $0)?.annotations ?? [] }
        XCTAssertEqual(widgets.first(where: { $0.fieldName == textFieldName })?.widgetStringValue, "Folik Real PDF Test")
        XCTAssertEqual(widgets.first(where: { $0.fieldName == checkboxName })?.buttonWidgetState, .onState)

        let flattenedURL = try DocumentExporter.export(sourceURL: workingURL, mode: .flattened)
        let flattened = try XCTUnwrap(PDFDocument(url: flattenedURL))
        XCTAssertEqual(
            (0..<flattened.pageCount).reduce(0) { $0 + (flattened.page(at: $1)?.annotations.count ?? 0) },
            0
        )
    }

    func testPageOrganizerCreatesReorderedRotatedDuplicateCopyWithoutChangingOriginal() throws {
        let source = workspace.appendingPathComponent("Source Pages.pdf")
        try PDFTestFixture.write(to: source, pages: ["One", "Two", "Three"])
        let draft = PageOrganizerDraft(sourceURL: source)

        draft.rotate(indices: [0], by: 90)
        draft.duplicate(indices: [1])
        draft.move(from: IndexSet(integer: 3), to: 1)
        draft.delete(indices: [2])
        XCTAssertEqual(draft.pageCount, 3)
        draft.undo()
        XCTAssertEqual(draft.pageCount, 4)

        let organizedURL = try draft.saveOrganizedCopy()
        XCTAssertNotEqual(organizedURL, source)
        let original = try XCTUnwrap(PDFDocument(url: source))
        XCTAssertEqual(original.pageCount, 3)
        XCTAssertEqual((0..<3).compactMap { original.page(at: $0)?.string?.trimmingCharacters(in: .whitespacesAndNewlines) }, ["One", "Two", "Three"])
        XCTAssertEqual(original.page(at: 0)?.rotation, 0)

        let organized = try XCTUnwrap(PDFDocument(url: organizedURL))
        XCTAssertEqual(organized.pageCount, 4)
        XCTAssertEqual(
            (0..<4).compactMap { organized.page(at: $0)?.string?.trimmingCharacters(in: .whitespacesAndNewlines) },
            ["One", "Three", "Two", "Two"]
        )
        XCTAssertEqual(organized.page(at: 0)?.rotation, 90)
    }

    func testPageOrganizerExtractsSelectionAndNeverDeletesEveryPage() throws {
        let source = workspace.appendingPathComponent("Extract Source.pdf")
        try PDFTestFixture.write(to: source, pages: ["Alpha", "Beta", "Gamma"])
        let draft = PageOrganizerDraft(sourceURL: source)

        draft.delete(indices: [0, 1, 2])
        XCTAssertEqual(draft.pageCount, 3)
        let extractedURL = try draft.extract(indices: [0, 2])
        let extracted = try XCTUnwrap(PDFDocument(url: extractedURL))
        XCTAssertEqual(extracted.pageCount, 2)
        XCTAssertEqual(
            (0..<2).compactMap { extracted.page(at: $0)?.string?.trimmingCharacters(in: .whitespacesAndNewlines) },
            ["Alpha", "Gamma"]
        )
    }

    func testPageOrganizerPreservesFormWidgetsInSavedCopy() throws {
        let source = workspace.appendingPathComponent("Organized Form.pdf")
        try PDFTestFixture.writeCompatibilityForm(to: source)
        let draft = PageOrganizerDraft(sourceURL: source)
        draft.move(from: IndexSet(integer: 1), to: 0)
        let organizedURL = try draft.saveOrganizedCopy()

        let organized = try XCTUnwrap(PDFDocument(url: organizedURL))
        let widgets = (0..<organized.pageCount).flatMap { organized.page(at: $0)?.annotations.filter { $0.type == "Widget" } ?? [] }
        XCTAssertEqual(widgets.count, 7)
        XCTAssertTrue(PDFTestFixture.hasCanonicalFormFieldTree(organized))
    }

    func testPageOrganizerInsertsBlankPageAndUndoes() throws {
        let source = workspace.appendingPathComponent("Blank Source.pdf")
        try PDFTestFixture.write(to: source, pages: ["First", "Second"])
        let draft = PageOrganizerDraft(sourceURL: source)

        draft.insertBlankPage(after: 0)
        XCTAssertEqual(draft.pageCount, 3)
        XCTAssertTrue(draft.page(at: 1)?.string?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        XCTAssertTrue(draft.canUndo)

        draft.undo()
        XCTAssertEqual(draft.pageCount, 2)
        XCTAssertEqual(draft.page(at: 1)?.string?.trimmingCharacters(in: .whitespacesAndNewlines), "Second")
    }

    func testPageOrganizerAppendsPagesFromAnotherPDF() throws {
        let source = workspace.appendingPathComponent("Merge Source.pdf")
        let imported = workspace.appendingPathComponent("Imported Pages.pdf")
        try PDFTestFixture.write(to: source, pages: ["Source"])
        try PDFTestFixture.write(to: imported, pages: ["Imported One", "Imported Two"])
        let draft = PageOrganizerDraft(sourceURL: source)

        draft.appendPages(from: imported)

        XCTAssertEqual(draft.pageCount, 3)
        XCTAssertEqual(
            (0..<3).compactMap { draft.page(at: $0)?.string?.trimmingCharacters(in: .whitespacesAndNewlines) },
            ["Source", "Imported One", "Imported Two"]
        )
        XCTAssertEqual(PDFDocument(url: imported)?.pageCount, 2)
    }
}

private enum PDFTestFixture {
    static func write(to url: URL, pages: [String]) throws {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))
        try renderer.writePDF(to: url) { context in
            for text in pages {
                context.beginPage()
                text.draw(
                    at: CGPoint(x: 72, y: 96),
                    withAttributes: [.font: UIFont.systemFont(ofSize: 24)]
                )
            }
        }
    }

    static func writeForm(to url: URL) throws {
        try write(to: url, pages: ["Folik Form Fixture"])
        let document = try XCTUnwrap(PDFDocument(url: url))
        let page = try XCTUnwrap(document.page(at: 0))
        let field = PDFAnnotation(
            bounds: CGRect(x: 72, y: 590, width: 320, height: 40),
            forType: .widget,
            withProperties: nil
        )
        field.widgetFieldType = .text
        field.fieldName = "Full name"
        field.widgetStringValue = ""
        field.font = UIFont.systemFont(ofSize: 16)
        field.backgroundColor = .white
        field.color = .systemBlue
        let border = PDFBorder()
        border.lineWidth = 1.5
        field.border = border
        page.addAnnotation(field)
        guard document.write(to: url) else {
            throw CocoaError(.fileWriteUnknown)
        }
    }

    static func writeCompatibilityForm(to url: URL) throws {
        try write(to: url, pages: ["Folik AcroForm Compatibility", "Signature and choice fields"])
        let document = try XCTUnwrap(PDFDocument(url: url))
        let firstPage = try XCTUnwrap(document.page(at: 0))
        let secondPage = try XCTUnwrap(document.page(at: 1))

        let fullName = textField(name: "Full name", bounds: CGRect(x: 72, y: 620, width: 300, height: 36))
        fullName.setValue(NSNumber(value: 1 << 1), forAnnotationKey: .widgetFieldFlags)
        firstPage.addAnnotation(fullName)
        let comments = textField(name: "Comments", bounds: CGRect(x: 72, y: 500, width: 360, height: 92))
        comments.isMultiline = true
        firstPage.addAnnotation(comments)

        let checkbox = widget(name: "Subscribe", type: .button, bounds: CGRect(x: 72, y: 450, width: 28, height: 28))
        checkbox.widgetControlType = .checkBoxControl
        checkbox.buttonWidgetStateString = "Yes"
        checkbox.buttonWidgetState = .offState
        firstPage.addAnnotation(checkbox)

        let email = widget(name: "Contact preference", type: .button, bounds: CGRect(x: 72, y: 400, width: 28, height: 28))
        email.widgetControlType = .radioButtonControl
        email.setValue(NSNumber(value: (1 << 15) | (1 << 1)), forAnnotationKey: .widgetFieldFlags)
        email.buttonWidgetStateString = "Email"
        email.buttonWidgetState = .offState
        firstPage.addAnnotation(email)
        let phone = widget(name: "Contact preference", type: .button, bounds: CGRect(x: 160, y: 400, width: 28, height: 28))
        phone.widgetControlType = .radioButtonControl
        phone.setValue(NSNumber(value: (1 << 15) | (1 << 1)), forAnnotationKey: .widgetFieldFlags)
        phone.buttonWidgetStateString = "Phone"
        phone.buttonWidgetState = .offState
        firstPage.addAnnotation(phone)

        let choice = widget(name: "Favorite color", type: .choice, bounds: CGRect(x: 72, y: 620, width: 240, height: 36))
        choice.choices = ["Red", "Blue", "Green"]
        choice.values = ["red", "blue", "green"]
        choice.widgetStringValue = "Red"
        secondPage.addAnnotation(choice)

        let signature = widget(name: "Approval", type: .signature, bounds: CGRect(x: 72, y: 520, width: 300, height: 70))
        secondPage.addAnnotation(signature)

        guard document.write(to: url) else { throw CocoaError(.fileWriteUnknown) }
    }

    static func hasCanonicalFormFieldTree(_ document: PDFDocument) -> Bool {
        guard let documentRef = document.documentRef, let catalog = documentRef.catalog else {
            return false
        }
        var acroForm: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(catalog, "AcroForm", &acroForm), let acroForm else {
            return false
        }
        var fields: CGPDFArrayRef?
        return CGPDFDictionaryGetArray(acroForm, "Fields", &fields) && fields.map(CGPDFArrayGetCount) ?? 0 > 0
    }

    static func writeXFAForm(to url: URL) throws {
        let xfa = "<xdp:xdp xmlns:xdp=\"http://ns.adobe.com/xdp/\"><template/></xdp:xdp>"
        let objects = [
            "<< /Type /Catalog /Pages 2 0 R /AcroForm 4 0 R >>",
            "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] >>",
            "<< /Fields [] /XFA 5 0 R >>",
            "<< /Length \(xfa.utf8.count) >>\nstream\n\(xfa)\nendstream"
        ]
        var pdf = "%PDF-1.7\n"
        var offsets = [0]
        for (index, object) in objects.enumerated() {
            offsets.append(pdf.utf8.count)
            pdf += "\(index + 1) 0 obj\n\(object)\nendobj\n"
        }
        let xrefOffset = pdf.utf8.count
        pdf += "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n"
        for offset in offsets.dropFirst() {
            pdf += String(format: "%010d 00000 n \n", offset)
        }
        pdf += "trailer\n<< /Size \(objects.count + 1) /Root 1 0 R >>\nstartxref\n\(xrefOffset)\n%%EOF\n"
        try Data(pdf.utf8).write(to: url)
    }

    private static func textField(name: String, bounds: CGRect) -> PDFAnnotation {
        let field = widget(name: name, type: .text, bounds: bounds)
        field.widgetStringValue = ""
        field.font = UIFont.systemFont(ofSize: 16)
        return field
    }

    private static func widget(
        name: String,
        type: PDFAnnotationWidgetSubtype,
        bounds: CGRect
    ) -> PDFAnnotation {
        let field = PDFAnnotation(bounds: bounds, forType: .widget, withProperties: nil)
        field.widgetFieldType = type
        field.fieldName = name
        field.backgroundColor = .white
        field.color = .systemBlue
        let border = PDFBorder()
        border.lineWidth = 1.5
        field.border = border
        return field
    }

    static func item(for url: URL) -> LibraryDocument {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        return LibraryDocument(
            url: url,
            pageCount: PDFDocument(url: url)?.pageCount ?? 0,
            fileSize: Int64(values?.fileSize ?? 0),
            modifiedAt: values?.contentModificationDate ?? .distantPast
        )
    }
}

import UIKit
import XCTest

final class FolikUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLibraryOpensDocumentAndAdvancesPage() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixture"]
        app.launch()

        XCTAssertTrue(app.navigationBars["Library"].waitForExistence(timeout: 5))

        let document = app.buttons["library.document.Folik UI Test.pdf"]
        XCTAssertTrue(document.waitForExistence(timeout: 3))
        document.tap()

        XCTAssertTrue(app.navigationBars["Folik UI Test"].waitForExistence(timeout: 3))
        let pageStatus = app.staticTexts["reader.pageStatus"]
        XCTAssertTrue(pageStatus.waitForExistence(timeout: 3))
        XCTAssertEqual(pageStatus.label, "Page 1 of 2")

        let nextPage = app.buttons["reader.nextPage"]
        XCTAssertTrue(nextPage.isEnabled)
        nextPage.tap()

        let secondPage = NSPredicate(format: "label == 'Page 2 of 2'")
        expectation(for: secondPage, evaluatedWith: pageStatus)
        waitForExpectations(timeout: 3)

        let annotations = app.buttons["reader.panel.annotations"]
        XCTAssertTrue(annotations.waitForExistence(timeout: 3))
        annotations.tap()
        XCTAssertTrue(app.navigationBars["Annotations"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["reader.annotation.draw"].waitForExistence(timeout: 3))
        XCTAssertEqual(
            app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'reader.annotation.'")).count,
            4
        )
        app.buttons["reader.annotation.add"].tap()
        XCTAssertTrue(app.buttons["Stamp"].exists)
        app.buttons["Rectangle"].tap()
        let placeCenter = app.buttons["reader.annotation.placeCenter"]
        XCTAssertTrue(placeCenter.waitForExistence(timeout: 3))
        placeCenter.tap()
        annotations.tap()
        XCTAssertTrue(app.staticTexts["2 annotations"].waitForExistence(timeout: 3))
        app.buttons["reader.annotation.edit"].tap()
        let doneEditing = app.buttons["reader.annotation.doneEditing"]
        XCTAssertTrue(doneEditing.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Tap or drag an annotation"].exists)
        doneEditing.tap()
        annotations.tap()
        app.buttons["reader.annotation.draw"].tap()
        let finishDrawing = app.buttons["reader.drawing.done"]
        XCTAssertTrue(finishDrawing.waitForExistence(timeout: 3))
        finishDrawing.tap()

        let forms = app.buttons["reader.panel.forms"]
        XCTAssertTrue(forms.waitForExistence(timeout: 3))
        forms.tap()
        XCTAssertTrue(app.navigationBars["Forms"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["reader.form.field.0:0:Full name"].waitForExistence(timeout: 3))
        let nextIncomplete = app.buttons["reader.form.nextIncomplete"]
        XCTAssertTrue(nextIncomplete.waitForExistence(timeout: 3))
        XCTAssertEqual(nextIncomplete.label, "Next required field")
        nextIncomplete.tap()

        let firstPage = NSPredicate(format: "label == 'Page 1 of 2'")
        expectation(for: firstPage, evaluatedWith: pageStatus)
        waitForExpectations(timeout: 3)

        let find = app.buttons["reader.panel.find"]
        XCTAssertTrue(find.waitForExistence(timeout: 3))
        find.tap()
        let query = app.textFields["reader.find.query"]
        XCTAssertTrue(query.waitForExistence(timeout: 3))
        query.tap()
        query.typeText("searchable")

        XCTAssertTrue(app.staticTexts["1 of 2"].waitForExistence(timeout: 5))
        let nextResult = app.buttons["reader.find.next"]
        XCTAssertTrue(nextResult.isEnabled)
        nextResult.tap()
        XCTAssertTrue(app.staticTexts["2 of 2"].waitForExistence(timeout: 3))
    }

    func testLibraryAddMenuOffersScanningAndFileImport() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixture"]
        app.launch()

        XCTAssertTrue(app.navigationBars["Library"].waitForExistence(timeout: 5))
        let addDocument = app.buttons["library.addDocument"]
        XCTAssertTrue(addDocument.waitForExistence(timeout: 3))
        XCTAssertEqual(addDocument.label, "Add Document")
        addDocument.tap()

        XCTAssertTrue(app.buttons["Scan Document"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Choose PDFs"].exists)
        XCTAssertTrue(app.buttons["Images to PDF"].exists)
        XCTAssertTrue(app.buttons["Text/RTF to PDF"].exists)
    }

    func testConversionScreensCanBeCancelledWithoutCreatingDocuments() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixture"]
        app.launch()
        for title in ["Images to PDF", "Text/RTF to PDF"] {
            app.buttons["library.addDocument"].tap()
            app.buttons[title].tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 3))
            XCTAssertFalse(app.buttons["converter.create"].isEnabled)
            XCTAssertTrue(app.buttons["converter.chooseFiles"].exists)
            app.buttons["Cancel"].tap()
            XCTAssertTrue(app.navigationBars["Library"].waitForExistence(timeout: 3))
        }
    }

    func testImageConversionReviewReordersAndCreatesReadablePDF() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixture", "--ui-test-conversion-selection"]
        app.launch()
        app.buttons["library.addDocument"].tap()
        app.buttons["Images to PDF"].tap()
        XCTAssertTrue(app.buttons["converter.create"].waitForExistence(timeout: 3))
        app.buttons["Actions for page 2"].tap()
        app.buttons["Move Up"].tap()
        app.buttons["converter.create"].tap()
        XCTAssertTrue(app.navigationBars["Converted Images"].waitForExistence(timeout: 20))
        XCTAssertEqual(app.staticTexts["reader.pageStatus"].label, "Page 1 of 2")
        app.buttons["reader.panel.find"].tap()
        let query = app.textFields["reader.find.query"]
        XCTAssertTrue(query.waitForExistence(timeout: 3))
        query.tap()
        query.typeText("Second conversion page")
        XCTAssertTrue(app.staticTexts["1 of 1"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["reader.pageStatus"].label, "Page 1 of 2")
    }

    func testTextConversionCreatesMultipageReadablePDF() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixture", "--ui-test-conversion-selection"]
        app.launch()
        app.buttons["library.addDocument"].tap()
        app.buttons["Text/RTF to PDF"].tap()
        XCTAssertTrue(app.buttons["converter.create"].waitForExistence(timeout: 3))
        app.buttons["converter.create"].tap()
        XCTAssertTrue(app.navigationBars["Converted Text"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["reader.nextPage"].isEnabled)
        app.buttons["reader.panel.find"].tap()
        let query = app.textFields["reader.find.query"]
        XCTAssertTrue(query.waitForExistence(timeout: 3))
        query.tap()
        query.typeText("Conversion line 119")
        XCTAssertTrue(app.staticTexts["1 of 1"].waitForExistence(timeout: 5))
    }

    func testRedactionAreaPreviewAndSave() {
        let data = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792)).pdfData { c in
            c.beginPage(); ("PRIVATE ACCOUNT 4827" as NSString).draw(at: CGPoint(x: 72, y: 72), withAttributes: [.font: UIFont.systemFont(ofSize: 20)])
        }
        let app = XCUIApplication(); app.launchArguments = ["--ui-test-fixture", "--ui-test-pdf-source", data.base64EncodedString()]; app.launch()
        app.buttons["library.addDocument"].tap(); app.buttons["Redact PDF"].tap()
        let addArea = app.buttons["redaction.addArea"]
        XCTAssertTrue(addArea.waitForExistence(timeout: 10)); if !addArea.isHittable { app.swipeUp() }; addArea.tap()
        let create = app.buttons["redaction.preview"]; XCTAssertTrue(create.isEnabled); create.tap()
        XCTAssertTrue(app.navigationBars["Conversion Preview"].waitForExistence(timeout: 30))
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.lifetime = .keepAlways; add(attachment)
        app.buttons["office.save"].tap()
        XCTAssertTrue(app.navigationBars["Redacted Test"].waitForExistence(timeout: 10))
    }

    func testBatchSeparateAndCombinedSave() {
        for combined in [false, true] {
            let app = XCUIApplication(); app.launchArguments = ["--ui-test-fixture", "--ui-test-batch"]; app.launch()
            app.buttons["library.addDocument"].tap(); app.buttons["Batch to PDF"].tap()
            XCTAssertTrue(app.buttons["batch.action"].waitForExistence(timeout: 5))
            if combined {
                let toggle = app.switches["batch.combine"]
                toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
                XCTAssertTrue(app.textFields["Combined filename"].waitForExistence(timeout: 5))
            }
            app.buttons["batch.action"].tap()
            let save = app.buttons["batch.action"]
            expectation(for: NSPredicate(format: "label == 'Save All to Library'"), evaluatedWith: save)
            waitForExpectations(timeout: 20)
            save.tap()
            XCTAssertTrue(app.navigationBars["Library"].waitForExistence(timeout: 10))
            XCTAssertTrue(app.buttons[combined ? "library.document.Combined Documents.pdf" : "library.document.First.pdf"].waitForExistence(timeout: 10))
            if !combined { XCTAssertTrue(app.buttons["library.document.Second.pdf"].exists) }
            app.terminate()
        }
    }

    func testLibraryOrganizationAndContentSearch() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-test-fixture"]; app.launch()
        app.buttons["Document actions"].firstMatch.tap(); app.buttons["Organize"].tap()
        let folder = app.textFields["organization.folder"]
        XCTAssertTrue(folder.waitForExistence(timeout: 5)); folder.tap(); folder.typeText("Work")
        let tags = app.textFields["organization.tags"]; tags.tap(); tags.typeText("invoice, 2026")
        app.buttons["organization.save"].tap()
        XCTAssertTrue(app.navigationBars["Library"].waitForExistence(timeout: 5))
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap(); search.typeText("searchable")
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'Page 1:'")).firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["library.document.Folik UI Test.pdf"].exists)
    }

    func testExistingPDFOCRPreviewAndSave() throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 700, height: 900)).image { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 700, height: 900))
            ("Invoice number 4827" as NSString).draw(at: CGPoint(x: 60, y: 100), withAttributes: [.font: UIFont.systemFont(ofSize: 36), .foregroundColor: UIColor.black])
        }
        let data = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 700, height: 900)).pdfData { context in
            context.beginPage(); image.draw(in: CGRect(x: 0, y: 0, width: 700, height: 900))
        }
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixture", "--ui-test-pdf-source", data.base64EncodedString()]
        app.launch()
        app.buttons["library.addDocument"].tap(); app.buttons["Make PDF Searchable"].tap()
        XCTAssertTrue(app.buttons["pdfTool.preview"].waitForExistence(timeout: 5))
        app.buttons["pdfTool.preview"].tap()
        XCTAssertTrue(app.navigationBars["Conversion Preview"].waitForExistence(timeout: 30))
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.lifetime = .keepAlways; add(attachment)
        app.buttons["office.save"].tap()
        XCTAssertTrue(app.navigationBars["Searchable Test"].waitForExistence(timeout: 10))
    }

    func testPDFCompressionPreviewAndSave() throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 700, height: 900)).image { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 700, height: 900))
            ("Invoice number 4827" as NSString).draw(at: CGPoint(x: 60, y: 100), withAttributes: [.font: UIFont.systemFont(ofSize: 36), .foregroundColor: UIColor.black])
        }
        let data = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 700, height: 900)).pdfData { context in
            context.beginPage(); image.draw(in: CGRect(x: 0, y: 0, width: 700, height: 900))
        }
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixture", "--ui-test-pdf-source", data.base64EncodedString()]
        app.launch()
        app.buttons["library.addDocument"].tap(); app.buttons["Compress PDF"].tap()
        XCTAssertTrue(app.navigationBars["Compress PDF"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["pdfTool.preview"].waitForExistence(timeout: 5))
        app.buttons["pdfTool.preview"].tap()
        XCTAssertTrue(app.navigationBars["Conversion Preview"].waitForExistence(timeout: 30))
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.lifetime = .keepAlways; add(attachment)
        app.buttons["office.save"].tap()
        XCTAssertTrue(app.navigationBars["Compressed Test"].waitForExistence(timeout: 10))
    }

    func testOfficeDocumentsPreviewBeforeSaving() throws {
        for (name, ext) in [("OfficePreview", "docx"), ("OfficePreview", "odt"), ("LegacyUnicode", "doc"), ("PagesSavedPreview", "pages")] {
            let bundle = Bundle(for: Self.self)
            let url = try XCTUnwrap(bundle.url(forResource: name, withExtension: ext, subdirectory: "Fixtures") ?? bundle.url(forResource: name, withExtension: ext))
            let data = try Data(contentsOf: url)
            let app = XCUIApplication()
            app.launchArguments = ["--ui-test-fixture", "--ui-test-office-data", data.base64EncodedString(), ext]
            app.launch()
            app.buttons["library.addDocument"].tap()
            app.buttons["Documents to PDF"].tap()
            XCTAssertTrue(app.buttons["office.preview"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["office.save"].exists)
            app.buttons["office.preview"].tap()
            XCTAssertTrue(app.navigationBars["Conversion Preview"].waitForExistence(timeout: 15))
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "Office \(ext) preview"
            attachment.lifetime = .keepAlways
            add(attachment)
            XCTAssertTrue(app.buttons["office.save"].exists)
            if ext == "doc" { XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'Text recovery only.'")).firstMatch.exists) }
            if ext == "pages" { XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'Saved Pages preview.'")).firstMatch.exists) }
            app.buttons["office.save"].tap()
            XCTAssertTrue(app.navigationBars["Office Example"].waitForExistence(timeout: 10))
            app.terminate()
        }
    }

    func testOfficePreviewCanBeCancelledWithoutSaving() throws {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(bundle.url(forResource: "OfficePreview", withExtension: "docx", subdirectory: "Fixtures") ?? bundle.url(forResource: "OfficePreview", withExtension: "docx"))
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixture", "--ui-test-office-data", try Data(contentsOf: url).base64EncodedString(), "docx"]
        app.launch()
        app.buttons["library.addDocument"].tap()
        app.buttons["Documents to PDF"].tap()
        app.buttons["office.preview"].tap()
        XCTAssertTrue(app.navigationBars["Conversion Preview"].waitForExistence(timeout: 15))
        app.buttons["Back"].tap()
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Library"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["library.document.Office Example.pdf"].exists)
    }

    func testScannedPDFTextCanBeFound() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-scan-fixture"]
        app.launch()

        let scannedReader = app.navigationBars.matching(
            NSPredicate(format: "identifier BEGINSWITH 'Scan 2023-11-14'")
        ).firstMatch
        XCTAssertTrue(scannedReader.waitForExistence(timeout: 12))
        let find = app.buttons["reader.panel.find"]
        XCTAssertTrue(find.waitForExistence(timeout: 3))
        find.tap()

        let query = app.textFields["reader.find.query"]
        XCTAssertTrue(query.waitForExistence(timeout: 3))
        query.tap()
        query.typeText("landscape")

        XCTAssertTrue(app.staticTexts["1 of 1"].waitForExistence(timeout: 8))
    }

    func testSettingsOffersCompanyFeedbackLegalPrivacyAndVersion() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixture"]
        app.launch()

        let settings = app.buttons["library.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()

        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
        let settingsElements = app.descendants(matching: .any)
        XCTAssertTrue(settingsElements["settings.website"].exists)
        XCTAssertTrue(settingsElements["settings.openSource"].exists)
        XCTAssertTrue(settingsElements["settings.feedback"].exists)
        XCTAssertTrue(app.staticTexts["Documents stay on this device"].exists)
        XCTAssertTrue(app.staticTexts["Scans and text recognition run locally"].exists)
        XCTAssertTrue(app.staticTexts["Version 1.0 (1)"].exists)
        app.swipeUp()
        XCTAssertTrue(settingsElements["settings.eula"].waitForExistence(timeout: 3))
    }

    func testAnnotationEditingOffersAccessibleMovementControls() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-test-fixture",
            "--open-first-document",
            "--start-annotation-editing",
            "--add-editable-test-annotation",
            "--select-first-annotation"
        ]
        app.launch()

        XCTAssertTrue(app.navigationBars["Folik UI Test"].waitForExistence(timeout: 5))
        let move = app.buttons["reader.annotation.move"]
        XCTAssertTrue(move.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["reader.annotation.deleteSelected"].exists)
        XCTAssertTrue(app.buttons["reader.annotation.size"].exists)
        let appearance = app.buttons["reader.annotation.appearance"]
        XCTAssertTrue(appearance.exists)
        appearance.tap()
        XCTAssertTrue(app.buttons["Red"].exists)
        app.buttons["Red"].tap()
        appearance.tap()
        XCTAssertTrue(app.buttons["Bold, 6 point line"].exists)
        app.buttons["Bold, 6 point line"].tap()
        move.tap()
        app.buttons["Move right"].tap()
        app.buttons["reader.annotation.doneEditing"].tap()
        XCTAssertTrue(app.buttons["reader.panel.annotations"].waitForExistence(timeout: 3))
    }

    func testCurrentPageCanBeBookmarkedAndFilteredInPages() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixture", "--open-first-document", "--clear-bookmarks"]
        app.launch()

        XCTAssertTrue(app.navigationBars["Folik UI Test"].waitForExistence(timeout: 5))
        let bookmark = app.buttons["reader.bookmarkCurrentPage"]
        XCTAssertTrue(bookmark.waitForExistence(timeout: 3))
        XCTAssertEqual(bookmark.label, "Bookmark page 1")
        bookmark.tap()
        XCTAssertEqual(bookmark.label, "Remove bookmark from page 1")
        XCTAssertEqual(bookmark.value as? String, "Bookmarked")

        XCUIDevice.shared.orientation = .landscapeLeft
        addTeardownBlock { XCUIDevice.shared.orientation = .portrait }
        XCTAssertTrue(bookmark.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["reader.panel.pages"].isHittable)
        XCUIDevice.shared.orientation = .portrait

        app.buttons["reader.panel.pages"].tap()
        XCTAssertTrue(app.navigationBars["Pages"].waitForExistence(timeout: 3))
        let filter = app.segmentedControls["reader.pages.filter"]
        XCTAssertTrue(filter.waitForExistence(timeout: 3))
        filter.buttons["Bookmarks"].tap()

        XCTAssertTrue(app.buttons["reader.pages.page.0"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["reader.pages.page.1"].exists)
        XCTAssertTrue(app.buttons["reader.pages.page.0"].value as? String == "Current page, Bookmarked")
    }

    func testTypedSignatureCanBeCreatedAndPlaced() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-test-fixture",
            "--open-first-document",
            "--open-annotations-panel",
            "--clear-saved-signatures"
        ]
        app.launch()

        XCTAssertTrue(app.navigationBars["Annotations"].waitForExistence(timeout: 5))
        app.buttons["reader.annotation.add"].tap()
        app.buttons["Signature"].tap()
        app.buttons["Create signature"].tap()
        XCTAssertTrue(app.navigationBars["Signature"].waitForExistence(timeout: 3))
        app.buttons["Type"].tap()
        let typedText = app.textFields["signature.typedText"]
        XCTAssertTrue(typedText.waitForExistence(timeout: 3))
        typedText.tap()
        typedText.typeText("Joseph Spears")
        app.buttons["signature.save"].tap()

        let placeCenter = app.buttons["reader.annotation.placeCenter"]
        XCTAssertTrue(placeCenter.waitForExistence(timeout: 4))
        placeCenter.tap()
        app.buttons["reader.panel.annotations"].tap()
        XCTAssertTrue(app.staticTexts["2 annotations"].waitForExistence(timeout: 3))
    }

    func testApprovedStampCanBePlacedFromAnnotationMenu() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-test-fixture",
            "--open-first-document",
            "--open-annotations-panel"
        ]
        app.launch()

        XCTAssertTrue(app.navigationBars["Annotations"].waitForExistence(timeout: 5))
        app.buttons["reader.annotation.add"].tap()
        let stampMenu = app.buttons["Stamp"]
        XCTAssertTrue(stampMenu.waitForExistence(timeout: 3))
        stampMenu.tap()
        let approved = app.buttons["Approved"]
        XCTAssertTrue(approved.waitForExistence(timeout: 3))
        approved.tap()

        let placeCenter = app.buttons["reader.annotation.placeCenter"]
        XCTAssertTrue(placeCenter.waitForExistence(timeout: 3))
        placeCenter.tap()
        app.buttons["reader.panel.annotations"].tap()

        XCTAssertTrue(app.staticTexts["2 annotations"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Approved"].exists)
    }

    func testExportMenuExplainsEditableAndFlattenedCopies() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixture", "--open-first-document"]
        app.launch()

        XCTAssertTrue(app.navigationBars["Folik UI Test"].waitForExistence(timeout: 5))
        let export = app.buttons["reader.export"]
        XCTAssertTrue(export.waitForExistence(timeout: 3))
        XCTAssertEqual(export.label, "Export and share")
        export.tap()
        XCTAssertTrue(app.buttons["Share Original"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Editable Copy"].exists)
        XCTAssertTrue(app.buttons["Flattened Copy"].exists)
    }

    func testPageOrganizerRotatesDuplicatesDeletesAndUndoesDraftChanges() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixture", "--open-first-document"]
        app.launch()

        XCTAssertTrue(app.navigationBars["Folik UI Test"].waitForExistence(timeout: 5))
        app.buttons["reader.panel.pages"].tap()
        let organize = app.buttons["reader.pages.organize"]
        XCTAssertTrue(organize.waitForExistence(timeout: 3))
        organize.tap()

        XCTAssertTrue(app.navigationBars["Organize"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["organizer.saveCopy"].exists)
        let firstPage = app.buttons["organizer.page.0"]
        XCTAssertTrue(firstPage.waitForExistence(timeout: 3))
        firstPage.tap()
        app.buttons["organizer.right"].tap()
        app.buttons["organizer.duplicate"].tap()
        XCTAssertTrue(app.buttons["organizer.page.2"].waitForExistence(timeout: 3))

        app.buttons["organizer.undo"].tap()
        XCTAssertFalse(app.buttons["organizer.page.2"].exists)
        app.buttons["organizer.page.1"].tap()
        app.buttons["organizer.delete"].tap()
        XCTAssertTrue(app.alerts["Delete selected pages?"].waitForExistence(timeout: 2))
        app.alerts.buttons["Delete Pages"].tap()
        XCTAssertFalse(app.buttons["organizer.page.1"].exists)
        app.buttons["organizer.undo"].tap()
        XCTAssertTrue(app.buttons["organizer.page.1"].waitForExistence(timeout: 3))
    }

    func testCaptureOCRStoreScreenshot() throws {
        // Raster-only input exercises real OCR, using fictional meeting notes.
        let image = UIGraphicsImageRenderer(size: CGSize(width: 700, height: 900)).image { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 700, height: 900))
            func line(_ text: String, _ y: CGFloat, _ size: CGFloat, bold: Bool = false) {
                (text as NSString).draw(at: CGPoint(x: 50, y: y), withAttributes: [.font: bold ? UIFont.boldSystemFont(ofSize: size) : UIFont.systemFont(ofSize: size), .foregroundColor: UIColor.black])
            }
            line("MEETING NOTES", 65, 42, bold: true)
            line("Harbor Studio / Project review", 130, 24)
            line("September 6, 2026", 170, 22)
            line("Key decisions", 260, 30, bold: true)
            line("Approve the updated project brief.", 315, 24)
            line("Keep the launch checklist in one place.", 365, 24)
            line("Next steps", 465, 30, bold: true)
            line("Share the draft with the team.", 520, 24)
            line("Schedule a follow-up review.", 570, 24)
            line("Sample scanned document", 790, 18)
        }
        let data = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 700, height: 900)).pdfData { context in
            context.beginPage(); image.draw(in: CGRect(x: 0, y: 0, width: 700, height: 900))
        }
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixture", "--ui-test-pdf-source", data.base64EncodedString()]
        app.launch(); app.buttons["library.addDocument"].tap(); app.buttons["Make PDF Searchable"].tap()
        XCTAssertTrue(app.buttons["pdfTool.preview"].waitForExistence(timeout: 8))
        app.buttons["pdfTool.preview"].tap()
        XCTAssertTrue(app.navigationBars["Conversion Preview"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts["Searchable copy. Your source PDF is unchanged."].exists)
        capture("08-ocr", in: app)
        app.buttons["office.save"].tap()
        XCTAssertTrue(app.navigationBars["Searchable Test"].waitForExistence(timeout: 10))
    }

    func testCaptureVersion101Screenshots() throws {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(bundle.url(forResource: "OfficePreview", withExtension: "docx", subdirectory: "Fixtures") ?? bundle.url(forResource: "OfficePreview", withExtension: "docx"))
        let office = XCUIApplication()
        office.launchArguments = ["--ui-test-fixture", "--ui-test-office-data", try Data(contentsOf: url).base64EncodedString(), "docx"]
        office.launch()
        office.buttons["library.addDocument"].tap(); office.buttons["Documents to PDF"].tap()
        XCTAssertTrue(office.buttons["office.preview"].waitForExistence(timeout: 8))
        capture("06-document-conversion", in: office)
        office.terminate()

        // Entirely fictional sample; no user documents or personal details.
        let data = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792)).pdfData { context in
            context.beginPage()
            func line(_ text: String, _ y: CGFloat, _ size: CGFloat, bold: Bool = false) {
                (text as NSString).draw(at: CGPoint(x: 48, y: y), withAttributes: [.font: bold ? UIFont.boldSystemFont(ofSize: size) : UIFont.systemFont(ofSize: size), .foregroundColor: UIColor.black])
            }
            line("Account: 1234 5678 9012", 72, 22)
            line("PROJECT SUMMARY", 220, 32, bold: true)
            line("Harbor Studio / September 2026", 270, 18)
            line("Prepared for sharing", 350, 24, bold: true)
            line("Design review and project planning", 395, 18)
            line("Milestone 1     Discovery complete", 455, 18)
            line("Milestone 2     Draft approved", 495, 18)
            line("Milestone 3     Final review scheduled", 535, 18)
            line("Sample document — fictional information", 710, 14)
        }
        let redaction = XCUIApplication()
        redaction.launchArguments = ["--ui-test-fixture", "--ui-test-pdf-source", data.base64EncodedString()]
        redaction.launch()
        redaction.buttons["library.addDocument"].tap(); redaction.buttons["Redact PDF"].tap()
        let area = redaction.buttons["redaction.addArea"]
        XCTAssertTrue(area.waitForExistence(timeout: 10))
        if !area.isHittable { redaction.swipeUp() }; area.tap()
        redaction.buttons["redaction.preview"].tap()
        XCTAssertTrue(redaction.navigationBars["Conversion Preview"].waitForExistence(timeout: 30))
        capture("07-redaction", in: redaction)
    }

    func testCaptureAppStoreScreenshots() throws {
        let library = launchApp()
        XCTAssertTrue(library.navigationBars["Library"].waitForExistence(timeout: 8))
        guard library.buttons["library.document.IRS Form W-9.pdf"].waitForExistence(timeout: 3),
              library.buttons["library.document.IRS Publication 1.pdf"].exists,
              library.buttons["library.document.IRS Form 1040.pdf"].exists else {
            throw XCTSkip("Run Scripts/capture_app_store_screenshots.sh to seed the real PDF fixtures.")
        }
        capture("01-library", in: library)

        let reader = launchApp(opening: "IRS Publication 1.pdf")
        XCTAssertTrue(reader.navigationBars["IRS Publication 1"].waitForExistence(timeout: 8))
        XCTAssertTrue(reader.staticTexts["reader.pageStatus"].waitForExistence(timeout: 8))
        capture("02-reader", in: reader)

        let search = launchApp(
            opening: "IRS Publication 1.pdf",
            additionalArguments: ["--find-query", "taxpayer"]
        )
        XCTAssertTrue(search.navigationBars["Find"].waitForExistence(timeout: 8))
        XCTAssertTrue(search.textFields["reader.find.query"].waitForExistence(timeout: 8))
        XCTAssertTrue(
            search.staticTexts.matching(
                NSPredicate(format: "label MATCHES '[0-9]+ of [0-9]+'")
            ).firstMatch.waitForExistence(timeout: 12)
        )
        capture("03-find", in: search)

        let forms = launchApp(
            opening: "IRS Form W-9.pdf",
            additionalArguments: ["--open-forms-panel", "--fill-form-for-export-qa"]
        )
        XCTAssertTrue(forms.navigationBars["Forms"].waitForExistence(timeout: 8))
        XCTAssertTrue(
            forms.buttons.matching(
                NSPredicate(format: "identifier BEGINSWITH 'reader.form.field.'")
            ).firstMatch.waitForExistence(timeout: 8)
        )
        capture("04-forms", in: forms)

        let annotations = launchApp(
            opening: "IRS Form 1040.pdf",
            additionalArguments: [
                "--start-annotation-editing",
                "--add-editable-test-annotation",
                "--select-first-annotation"
            ]
        )
        XCTAssertTrue(annotations.navigationBars["IRS Form 1040"].waitForExistence(timeout: 8))
        XCTAssertTrue(annotations.buttons["reader.annotation.doneEditing"].waitForExistence(timeout: 8))
        XCTAssertTrue(annotations.buttons["reader.annotation.move"].exists)
        capture("05-annotations", in: annotations)
    }

    private func launchApp(
        opening filename: String? = nil,
        additionalArguments: [String] = []
    ) -> XCUIApplication {
        let app = XCUIApplication()
        if let filename {
            app.launchArguments = ["--open-document-named", filename] + additionalArguments
        } else {
            app.launchArguments = additionalArguments
        }
        app.launch()
        return app
    }

    private func capture(_ name: String, in app: XCUIApplication) {
        XCTAssertEqual(app.state, .runningForeground)
        Thread.sleep(forTimeInterval: 1.5)
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

}

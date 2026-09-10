import UIKit
import XCTest

final class FolikUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testRecentlyDeletedRestoresLastPDFAndConfirmsPermanentDeletion() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixture"]
        app.launch()
        XCTAssertTrue(app.buttons["Document actions"].waitForExistence(timeout: 5))
        app.buttons["Document actions"].tap()
        app.buttons["Move to Recently Deleted"].tap()
        app.buttons["library.recentlyDeleted"].tap()
        let restore = app.buttons["trash.restore.Folik UI Test.pdf"]
        XCTAssertTrue(restore.waitForExistence(timeout: 3))
        capture("Recently Deleted", in: app)
        restore.tap()
        XCTAssertTrue(app.staticTexts["No Deleted Documents"].waitForExistence(timeout: 3))
        app.navigationBars["Recently Deleted"].buttons["Done"].tap()
        XCTAssertTrue(app.buttons["library.document.Folik UI Test.pdf"].waitForExistence(timeout: 3))
        app.buttons["Document actions"].tap()
        app.buttons["Move to Recently Deleted"].tap()
        app.buttons["library.recentlyDeleted"].tap()
        let delete = app.buttons["trash.delete.Folik UI Test.pdf"]
        XCTAssertTrue(delete.waitForExistence(timeout: 3))
        delete.tap()
        app.buttons["Cancel"].tap()
        XCTAssertTrue(restore.exists)
        delete.tap()
        app.alerts.buttons["Delete Permanently"].tap()
        XCTAssertTrue(app.staticTexts["No Deleted Documents"].waitForExistence(timeout: 3))
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

    func testContinueReadingResumesAndDismissalPersists() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixture"]
        app.launch()
        let document = app.buttons["library.document.Folik UI Test.pdf"]
        XCTAssertTrue(document.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["library.resume"].exists)
        document.tap()
        app.buttons["reader.nextPage"].tap()
        XCTAssertTrue(app.staticTexts["Page 2 of 2"].waitForExistence(timeout: 5))
        app.navigationBars.buttons["Library"].tap()
        let resume = app.buttons["library.resume"]
        XCTAssertTrue(resume.waitForExistence(timeout: 5))
        XCTAssertTrue(resume.label.contains("page 2 of 2"))
        capture("library-continue-reading", in: app)
        resume.tap()
        XCTAssertTrue(app.staticTexts["Page 2 of 2"].waitForExistence(timeout: 5))
        app.navigationBars.buttons["Library"].tap()
        app.buttons["library.dismissResume"].tap()
        XCTAssertFalse(resume.exists)
        app.terminate()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(document.waitForExistence(timeout: 5))
        XCTAssertFalse(resume.exists)
        document.tap()
        app.navigationBars.buttons["Library"].tap()
        XCTAssertTrue(resume.waitForExistence(timeout: 5))
    }

    func testMergeSelectedLibraryPDFsCanReorderPreviewAndSave() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixture", "--ui-test-library-pair"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Library"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["library.document.Second.pdf"].waitForExistence(timeout: 5))
        app.buttons["library.sort"].tap()
        app.buttons["Name"].tap()
        app.buttons["library.select"].tap()
        app.buttons["library.document.Folik UI Test.pdf"].tap()
        app.buttons["More"].tap()
        XCTAssertFalse(app.buttons["Merge PDFs"].isEnabled)
        app.navigationBars["1 Selected"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        app.buttons["library.document.Second.pdf"].tap()
        app.buttons["More"].tap()
        app.buttons["Merge PDFs"].tap()
        XCTAssertTrue(app.navigationBars["Merge PDFs"].waitForExistence(timeout: 5))
        let secondActions = app.buttons["Actions for Second"]
        XCTAssertTrue(secondActions.waitForExistence(timeout: 10))
        secondActions.tap()
        app.buttons["Move Up"].tap()
        XCTAssertTrue(app.staticTexts["1. Second.pdf"].exists)
        app.buttons["batch.action"].tap()
        XCTAssertTrue(app.navigationBars["Batch Preview"].waitForExistence(timeout: 15))
        capture("library-merge-preview", in: app)
        app.navigationBars["Batch Preview"].buttons["Done"].tap()
        app.buttons["batch.action"].tap()
        XCTAssertTrue(app.navigationBars["Library"].waitForExistence(timeout: 10))
        let merged = app.buttons["library.document.Combined Documents.pdf"]
        XCTAssertTrue(merged.waitForExistence(timeout: 5))
        XCTAssertTrue(merged.label.contains("3 pages"))
        XCTAssertTrue(app.buttons["library.document.Folik UI Test.pdf"].exists)
        XCTAssertTrue(app.buttons["library.document.Second.pdf"].exists)
    }

    func testSearchOffersOCRForImageOnlyPDFAndClearSearch() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixture", "--ui-test-image-only"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Library"].waitForExistence(timeout: 5))
        let search = app.searchFields.firstMatch
        search.tap(); search.typeText("notpresent")
        let ocr = app.buttons["library.searchOCR"]
        for _ in 0..<3 where !ocr.exists || !ocr.isHittable { app.swipeUp() }
        XCTAssertTrue(ocr.waitForExistence(timeout: 10))
        capture("library-search-ocr-guidance", in: app)
        ocr.tap()
        XCTAssertTrue(app.navigationBars["Make PDF Searchable"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["pdfTool.source"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["pdfTool.source"].label, "Scan.pdf")
        app.navigationBars["Make PDF Searchable"].buttons["Cancel"].tap()
        let clear = app.buttons["library.clearSearch"]
        for _ in 0..<3 where !clear.isHittable { app.swipeDown() }
        XCTAssertTrue(clear.waitForExistence(timeout: 5))
        clear.tap()
        XCTAssertTrue(app.buttons["library.document.Scan.pdf"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["library.searchOCR"].exists)
    }

    func testLibrarySearchShowsSeveralMatchingPages() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixture"]
        app.launch()

        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("Folik searchable")

        XCTAssertTrue(app.staticTexts["2 matching pages"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Page 1:'")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Page 2:'")).firstMatch.exists)
    }

    func testLibraryDocumentCanBeDuplicated() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixture"]
        app.launch()

        XCTAssertTrue(app.buttons["Document actions"].waitForExistence(timeout: 5))
        app.buttons["Document actions"].tap()
        app.buttons["Duplicate"].tap()

        XCTAssertTrue(app.buttons["library.document.Folik UI Test Copy.pdf"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["library.document.Folik UI Test.pdf"].exists)
    }

    func testRecentlyDeletedCanRestoreSeveralSelectedDocuments() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixture", "--ui-test-library-pair"]
        app.launch()

        app.buttons["library.select"].tap()
        app.buttons["library.document.Folik UI Test.pdf"].tap()
        app.buttons["library.document.Second.pdf"].tap()
        XCTAssertTrue(app.navigationBars["2 Selected"].exists)
        app.buttons["Remove selected documents"].tap()
        app.buttons["Move to Recently Deleted"].tap()

        XCTAssertTrue(app.buttons["library.recentlyDeleted"].waitForExistence(timeout: 5))
        app.buttons["library.recentlyDeleted"].tap()
        app.buttons["trash.select"].tap()
        app.buttons["Folik UI Test"].tap()
        app.buttons["Second"].tap()
        XCTAssertEqual(app.staticTexts["trash.selectionCount"].label, "2 selected")
        app.buttons["Restore"].tap()

        XCTAssertTrue(app.staticTexts["No Deleted Documents"].waitForExistence(timeout: 5))
    }

    func testGridLayoutPersistsAndSupportsSelectionAndDocumentTools() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixture", "--ui-test-library-pair"]
        app.launch()
        XCTAssertTrue(app.buttons["library.layout"].waitForExistence(timeout: 5))
        app.buttons["library.layout"].tap()
        app.buttons["Grid"].tap()
        XCTAssertEqual(app.buttons["library.layout"].value as? String, "Grid")
        XCTAssertTrue(app.buttons["library.document.Second.pdf"].isHittable)
        capture("library-grid", in: app)
        app.buttons["library.select"].tap()
        app.buttons["library.document.Second.pdf"].tap()
        XCTAssertEqual(app.buttons["library.document.Second.pdf"].value as? String, "Selected")
        app.buttons["library.select"].tap()
        app.terminate()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.buttons["library.layout"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["library.layout"].value as? String, "Grid")
        app.buttons["Document actions"].firstMatch.tap()
        app.buttons["Tools"].tap()
        XCTAssertTrue(app.buttons["Compress PDF"].exists)
        app.navigationBars["Library"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        app.buttons["library.layout"].tap()
        app.buttons["List"].tap()
        XCTAssertEqual(app.buttons["library.layout"].value as? String, "List")
    }

    func testGridAtAccessibilityTextSizeKeepsDocumentsReachable() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixture", "--ui-test-library-pair", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.buttons["library.layout"].waitForExistence(timeout: 5))
        app.buttons["library.layout"].tap()
        app.buttons["Grid"].tap()
        let document = app.buttons["library.document.Folik UI Test.pdf"]
        for _ in 0..<5 where !document.exists || !document.isHittable { app.swipeUp() }
        XCTAssertTrue(document.isHittable)
        capture("library-grid-largest-text", in: app)
        document.tap()
        XCTAssertTrue(app.navigationBars["Folik UI Test"].waitForExistence(timeout: 5))
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

        XCTAssertTrue(app.navigationBars["Add & Tools"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Capture and import"].exists)
        XCTAssertTrue(app.staticTexts["Convert to PDF"].exists)
        XCTAssertTrue(app.staticTexts["Improve and protect"].exists)
        XCTAssertTrue(app.buttons["Scan Document"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Choose PDFs"].exists)
        XCTAssertTrue(app.buttons["Images to PDF"].exists)
        XCTAssertTrue(app.buttons["Text/RTF to PDF"].exists)
    }

    func testLibrarySelectionCanFavoriteDocuments() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixture"]
        app.launch()

        XCTAssertTrue(app.navigationBars["Library"].waitForExistence(timeout: 5))
        app.buttons["library.select"].tap()
        let document = app.descendants(matching: .any)["library.document.Folik UI Test.pdf"]
        XCTAssertTrue(document.waitForExistence(timeout: 3))
        document.tap()
        app.buttons["More"].tap()
        app.buttons["Favorite"].tap()
        app.buttons["Done"].tap()

        app.buttons["Document actions"].tap()
        XCTAssertTrue(app.buttons["Remove Favorite"].waitForExistence(timeout: 3))
    }

    func testLibraryLargeTextLayoutKeepsDocumentsAndControlsAccessible() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixture"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Library"].waitForExistence(timeout: 5))
        app.buttons["Document actions"].tap()
        app.buttons["Rename"].tap()
        let name = app.textFields["rename.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "Folik UI Test".count))
        let longName = "Home renovation contract and supporting documents for September 2026"
        name.typeText(longName)
        app.buttons["rename.save"].tap()
        XCTAssertTrue(app.buttons["library.document." + longName + ".pdf"].waitForExistence(timeout: 5))
        app.terminate()
        app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.buttons["library.filter"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["library.filter"].isHittable)
        XCTAssertTrue(app.buttons["library.sort"].isHittable)
        capture("library-largest-text-portrait", in: app)
        XCUIDevice.shared.orientation = .landscapeLeft
        capture("library-largest-text-landscape", in: app)
        XCUIDevice.shared.orientation = .portrait
        let document = app.buttons["library.document." + longName + ".pdf"]
        if !document.isHittable { app.swipeUp() }
        XCTAssertTrue(document.isHittable)
        document.tap()
        XCTAssertTrue(app.navigationBars[longName].waitForExistence(timeout: 5))
    }

    func testLibraryFavoritesFilterCanBeCleared() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixture"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Library"].waitForExistence(timeout: 5))
        app.buttons["library.filter"].tap()
        app.buttons["Favorites only"].tap()
        XCTAssertTrue(app.staticTexts["No matching documents"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["library.document.Folik UI Test.pdf"].exists)
        app.buttons["library.clearFilters"].tap()
        XCTAssertTrue(app.buttons["library.document.Folik UI Test.pdf"].waitForExistence(timeout: 3))

        app.buttons["Document actions"].tap()
        app.buttons["Favorite"].tap()
        XCTAssertTrue(app.staticTexts["Favorites (1)"].waitForExistence(timeout: 3))
        app.buttons["library.filter"].tap()
        app.buttons["Favorites only"].tap()
        XCTAssertTrue(app.buttons["library.document.Folik UI Test.pdf"].exists)
        capture("library-favorites-filter", in: app)
        app.buttons["Document actions"].tap()
        app.buttons["Remove Favorite"].tap()
        XCTAssertTrue(app.staticTexts["No matching documents"].waitForExistence(timeout: 3))
        app.buttons["library.clearFilters"].tap()
        XCTAssertTrue(app.buttons["library.document.Folik UI Test.pdf"].exists)
    }

    func testLibraryDocumentToolsLoadSelectedPDFAndResetForGlobalTools() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixture"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Library"].waitForExistence(timeout: 5))
        for title in ["Make PDF Searchable", "Compress PDF", "Redact PDF", "Inspect & Sanitize", "Protect PDF", "Compare PDFs"] {
            app.buttons["Document actions"].tap()
            app.buttons["Tools"].tap()
            app.buttons[title].tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5))
            if title == "Inspect & Sanitize" {
                XCTAssertTrue(app.staticTexts["privacy.source"].waitForExistence(timeout: 10))
                XCTAssertEqual(app.staticTexts["privacy.source"].label, "Folik UI Test.pdf")
                XCTAssertTrue(app.buttons["privacy.preview"].waitForExistence(timeout: 10))
                XCTAssertTrue(app.buttons["privacy.preview"].isEnabled)
            } else if title == "Protect PDF" {
                XCTAssertTrue(app.staticTexts["protect.source"].waitForExistence(timeout: 10))
                XCTAssertEqual(app.staticTexts["protect.source"].label, "Folik UI Test.pdf")
                XCTAssertFalse(app.buttons["protect.review"].isEnabled)
            } else if title == "Compare PDFs" {
                XCTAssertTrue(app.staticTexts["compare.original"].waitForExistence(timeout: 10))
                XCTAssertEqual(app.staticTexts["compare.original"].label, "Folik UI Test.pdf")
                XCTAssertFalse(app.buttons["compare.run"].isEnabled)
            } else {
                XCTAssertTrue(app.staticTexts["pdfTool.source"].waitForExistence(timeout: 10))
                XCTAssertEqual(app.staticTexts["pdfTool.source"].label, "Folik UI Test.pdf")
            }
            if title == "Redact PDF" {
                XCTAssertTrue(app.staticTexts["Page 1 of 2"].waitForExistence(timeout: 10))
                XCTAssertFalse(app.buttons["redaction.preview"].isEnabled)
            } else if title != "Inspect & Sanitize" && title != "Protect PDF" && title != "Compare PDFs" {
                XCTAssertTrue(app.buttons["pdfTool.preview"].isEnabled)
                XCTAssertEqual(app.textFields["Filename"].value as? String,
                               title == "Compress PDF" ? "Folik UI Test Compressed" : "Folik UI Test Searchable")
            }
            capture("library-tool-" + title, in: app)
            app.navigationBars[title].buttons["Cancel"].tap()
            XCTAssertTrue(app.navigationBars["Library"].waitForExistence(timeout: 5))
        }
        app.buttons["library.addDocument"].tap()
        XCTAssertTrue(app.navigationBars["Add & Tools"].waitForExistence(timeout: 5))
        let compress = app.buttons["Compress PDF"]
        for _ in 0..<3 where !compress.exists || !compress.isHittable { app.swipeUp() }
        XCTAssertTrue(compress.waitForExistence(timeout: 3))
        compress.tap()
        XCTAssertTrue(app.navigationBars["Compress PDF"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["pdfTool.preview"].isEnabled)
        XCTAssertFalse(app.staticTexts["pdfTool.source"].exists)
    }

    func testLibraryCompressionSavesCopyAndKeepsOriginal() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixture"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Library"].waitForExistence(timeout: 5))
        app.buttons["Document actions"].tap()
        app.buttons["Tools"].tap()
        app.buttons["Compress PDF"].tap()
        XCTAssertTrue(app.staticTexts["pdfTool.source"].waitForExistence(timeout: 10))
        app.buttons["pdfTool.preview"].tap()
        XCTAssertTrue(app.navigationBars["Conversion Preview"].waitForExistence(timeout: 30))
        app.buttons["office.save"].tap()
        XCTAssertTrue(app.navigationBars["Folik UI Test Compressed"].waitForExistence(timeout: 10))
        app.navigationBars.buttons["Library"].tap()
        XCTAssertTrue(app.buttons["library.document.Folik UI Test.pdf"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["library.document.Folik UI Test Compressed.pdf"].exists)
        capture("library-two-documents", in: app)
    }

    func testPrivacyReportSanitizesCopyAndKeepsOriginal() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixture"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Library"].waitForExistence(timeout: 5))
        app.buttons["Document actions"].tap()
        app.buttons["Tools"].tap()
        app.buttons["Inspect & Sanitize"].tap()
        XCTAssertTrue(app.navigationBars["Inspect & Sanitize"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Form fields"].waitForExistence(timeout: 10))
        app.buttons["privacy.preview"].tap()
        XCTAssertTrue(app.navigationBars["Conversion Preview"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts["Sanitized image-only copy. Your original is unchanged and still contains its original information."].exists)
        app.buttons["office.save"].tap()
        XCTAssertTrue(app.navigationBars["Folik UI Test Sanitized"].waitForExistence(timeout: 10))
        app.navigationBars.buttons["Library"].tap()
        XCTAssertTrue(app.buttons["library.document.Folik UI Test.pdf"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["library.document.Folik UI Test Sanitized.pdf"].exists)
    }

    func testPasswordProtectedCopyRequiresPasswordAndKeepsOriginal() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixture"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Library"].waitForExistence(timeout: 5))
        app.buttons["Document actions"].tap()
        app.buttons["Tools"].tap()
        app.buttons["Protect PDF"].tap()
        XCTAssertTrue(app.navigationBars["Protect PDF"].waitForExistence(timeout: 5))

        let password = app.secureTextFields["protect.password"]
        let confirmation = app.secureTextFields["protect.confirmation"]
        XCTAssertTrue(password.waitForExistence(timeout: 10))
        password.tap()
        password.typeText("secret12")
        confirmation.tap()
        confirmation.typeText("secret12")
        XCTAssertTrue(app.buttons["protect.review"].isEnabled)
        app.buttons["protect.review"].tap()

        XCTAssertTrue(app.navigationBars["Protection Preview"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Password protection verified"].exists)
        app.buttons["protect.save"].tap()
        XCTAssertTrue(app.staticTexts["This PDF is locked"].waitForExistence(timeout: 10))
        let unlockPassword = app.secureTextFields["PDF password"]
        unlockPassword.tap()
        unlockPassword.typeText("secret12")
        app.buttons["Unlock"].tap()
        XCTAssertTrue(app.staticTexts["reader.pageStatus"].waitForExistence(timeout: 10))
        app.navigationBars.buttons["Library"].tap()
        XCTAssertTrue(app.buttons["library.document.Folik UI Test.pdf"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["library.document.Folik UI Test Protected.pdf"].exists)
    }

    func testPDFComparisonAlignsAnInsertedPage() {
        func pdf(_ pages: [String]) -> Data {
            UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792)).pdfData { context in
                for text in pages {
                    context.beginPage()
                    (text as NSString).draw(at: CGPoint(x: 72, y: 96), withAttributes: [.font: UIFont.systemFont(ofSize: 22)])
                }
            }
        }
        let original = pdf(["Cover", "Terms", "Signature page"])
        let revised = pdf(["Cover", "New disclosure", "Terms", "Signature page"])
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-test-fixture",
            "--ui-test-compare-original", original.base64EncodedString(),
            "--ui-test-compare-revised", revised.base64EncodedString()
        ]
        app.launch()
        app.buttons["library.addDocument"].tap()
        let compare = app.buttons["Compare PDFs"]
        for _ in 0..<4 where !compare.exists || !compare.isHittable { app.swipeUp() }
        XCTAssertTrue(compare.waitForExistence(timeout: 5))
        compare.tap()
        XCTAssertTrue(app.navigationBars["Compare PDFs"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["compare.run"].isEnabled)
        app.buttons["compare.run"].tap()
        XCTAssertTrue(app.navigationBars["Comparison Report"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["Page 2 added"].exists)
        XCTAssertTrue(app.staticTexts["Text-based result only. Review both PDFs for image, layout, color, annotation, and other visual changes."].exists)
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
        app.buttons["library.addDocument"].tap()
        let redact = app.buttons["Redact PDF"]
        if !redact.exists { app.swipeUp() }
        XCTAssertTrue(redact.waitForExistence(timeout: 3)); redact.tap()
        let addArea = app.buttons["redaction.addArea"]
        XCTAssertTrue(addArea.waitForExistence(timeout: 10)); if !addArea.isHittable { app.swipeUp() }; addArea.tap()
        let create = app.buttons["redaction.preview"]; XCTAssertTrue(create.isEnabled); create.tap()
        XCTAssertTrue(app.navigationBars["Conversion Preview"].waitForExistence(timeout: 30))
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.lifetime = .keepAlways; add(attachment)
        app.buttons["office.save"].tap()
        XCTAssertTrue(app.navigationBars["Redacted Test"].waitForExistence(timeout: 10))
    }

    func testSmartRedactionFindsAndAddsReviewedText() {
        let data = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792)).pdfData { context in
            context.beginPage()
            ("PRIVATE ACCOUNT 4827" as NSString).draw(at: CGPoint(x: 72, y: 72), withAttributes: [.font: UIFont.systemFont(ofSize: 20)])
            ("Public project summary" as NSString).draw(at: CGPoint(x: 72, y: 500), withAttributes: [.font: UIFont.systemFont(ofSize: 20)])
        }
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixture", "--ui-test-pdf-source", data.base64EncodedString()]
        app.launch()
        app.buttons["library.addDocument"].tap()
        let redact = app.buttons["Redact PDF"]
        if !redact.exists { app.swipeUp() }
        XCTAssertTrue(redact.waitForExistence(timeout: 3))
        redact.tap()

        let query = app.textFields["redaction.searchText"]
        XCTAssertTrue(query.waitForExistence(timeout: 10))
        if !query.isHittable { app.swipeUp() }
        query.tap()
        query.typeText("PRIVATE ACCOUNT")
        app.buttons["redaction.findText"].tap()

        XCTAssertTrue(app.navigationBars["Review Suggestions"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["PRIVATE ACCOUNT"].exists)
        let addSuggestions = app.buttons["redaction.addSuggestions"]
        XCTAssertTrue(addSuggestions.isEnabled)
        addSuggestions.tap()
        XCTAssertTrue(app.staticTexts["Area 1 · Page 1"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["redaction.preview"].isEnabled)
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
        app.buttons["library.addDocument"].tap()
        let compress = app.buttons["Compress PDF"]
        for _ in 0..<3 where !compress.exists || !compress.isHittable { app.swipeUp() }
        XCTAssertTrue(compress.waitForExistence(timeout: 5))
        compress.tap()
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
        let preview = app.buttons["office.preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: preview)
        waitForExpectations(timeout: 5)
        preview.tap()
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
        XCTAssertTrue(app.staticTexts["Version 1.0.3 (1)"].exists)
        XCTAssertTrue(settingsElements["settings.shortcuts"].waitForExistence(timeout: 3))
        app.swipeUp()
        XCTAssertTrue(settingsElements["settings.website"].exists)
        XCTAssertTrue(settingsElements["settings.openSource"].exists)
        XCTAssertTrue(settingsElements["settings.feedback"].exists)
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["Documents stay on this device"].exists)
        XCTAssertTrue(app.staticTexts["Scans and text recognition run locally"].exists)
        app.swipeUp()
        XCTAssertTrue(settingsElements["settings.eula"].waitForExistence(timeout: 3))
    }

    func testAppLockCoversTheLibraryUntilAuthentication() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixture", "--ui-test-app-lock"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Folik is locked"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["appLock.unlock"].exists)
        XCTAssertFalse(app.buttons["library.settings"].isHittable)
        XCTAssertFalse(app.buttons["library.document.Folik UI Test.pdf"].isHittable)
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

    func testCaptureVersion102Screenshots() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixture", "--store-screenshots-102"]
        app.launch()
        XCTAssertTrue(app.buttons["library.document.Project Brief.pdf"].waitForExistence(timeout: 8))
        capture("01-library", in: app)
        app.buttons["library.dismissResume"].tap()
        app.buttons["Document actions"].firstMatch.tap()
        app.buttons["Remove Favorite"].tap()
        app.buttons["library.layout"].tap()
        app.buttons["Grid"].tap()
        capture("09-grid", in: app)
        app.buttons["library.layout"].tap()
        app.buttons["List"].tap()
        app.buttons["library.select"].tap()
        app.buttons["library.document.Project Brief.pdf"].tap()
        app.buttons["library.document.Meeting Notes.pdf"].tap()
        app.buttons["More"].tap()
        app.buttons["Merge PDFs"].tap()
        XCTAssertTrue(app.buttons["batch.action"].waitForExistence(timeout: 15))
        app.buttons["batch.action"].tap()
        XCTAssertTrue(app.navigationBars["Batch Preview"].waitForExistence(timeout: 15))
        app.navigationBars["Batch Preview"].buttons["Done"].tap()
        capture("10-merge", in: app)
        app.terminate()

        let data = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792)).pdfData { c in
            c.beginPage()
            func line(_ text: String, _ y: CGFloat, _ size: CGFloat) {
                (text as NSString).draw(at: CGPoint(x: 48, y: y), withAttributes: [.font: UIFont.systemFont(ofSize: size), .foregroundColor: UIColor.black])
            }
            line("HARBOR STUDIO / PROJECT BRIEF", 60, 24)
            line("Prepared for review", 110, 18)
            line("Contact: alex@example.com", 220, 20)
            line("Reply to alex@example.com with feedback.", 280, 20)
            line("Share the approved project brief with the team.", 440, 18)
            line("Fictional sample document", 710, 14)
        }
        app.launchArguments = ["--ui-test-fixture", "--store-screenshots-102", "--ui-test-pdf-source", data.base64EncodedString()]
        app.launch()
        app.buttons["library.addDocument"].tap()
        let redact = app.buttons["Redact PDF"]
        if !redact.exists { app.swipeUp() }
        redact.tap()
        let query = app.textFields["redaction.searchText"]
        XCTAssertTrue(query.waitForExistence(timeout: 10))
        if !query.isHittable { app.swipeUp() }
        query.tap(); query.typeText("alex@example.com")
        app.buttons["redaction.findText"].tap()
        XCTAssertTrue(app.navigationBars["Review Suggestions"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["redaction.addSuggestions"].isEnabled)
        capture("07-redaction", in: app)
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
        redaction.buttons["library.addDocument"].tap()
        let redactTool = redaction.buttons["Redact PDF"]
        if !redactTool.exists { redaction.swipeUp() }
        XCTAssertTrue(redactTool.waitForExistence(timeout: 3)); redactTool.tap()
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

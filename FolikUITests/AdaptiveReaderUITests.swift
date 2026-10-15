import XCTest

@MainActor
final class AdaptiveReaderUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testAccessibilitySizeKeepsToolsInReachableSheet() {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixture", "--ui-test-reader-resize", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let document = app.buttons["library.document.Folik UI Test.pdf"]
        XCTAssertTrue(document.waitForExistence(timeout: 8)); document.tap()
        XCTAssertTrue(app.buttons["reader.fill"].waitForExistence(timeout: 8))
        app.buttons["reader.fill"].tap()
        let done = app.buttons["reader.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5)); XCTAssertTrue(done.isHittable)
        XCTAssertFalse(app.descendants(matching: .any)["reader.companion"].exists)
        let capture = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        capture.name = "Production-Accessibility-Sheet"; capture.lifetime = .keepAlways; add(capture)
        done.tap()
        XCTAssertTrue(app.buttons["reader.read"].isHittable)
    }

    func testExpandedFillKeepsPDFContextAndDraftAcrossWidthChanges() {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixture", "--ui-test-reader-continuity", "--ui-test-reader-resize"]
        app.launch()
        let document = app.buttons["library.document.Folik UI Test.pdf"]
        XCTAssertTrue(document.waitForExistence(timeout: 8)); document.tap()
        XCTAssertTrue(app.buttons["reader.probe.seed"].waitForExistence(timeout: 8))
        app.buttons["reader.probe.seed"].tap()
        let snapshot = app.staticTexts["reader.probe.snapshot"]
        let original = snapshot.label
        app.buttons["reader.fill"].tap()
        let editor = app.textFields["reader.fill.value"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields.matching(identifier: "reader.fill.value").count, 1)
        let companion = app.descendants(matching: .any)["reader.companion"]
        XCTAssertTrue(companion.exists)
        let pdf = app.descendants(matching: .any)["reader.pdf"]
        XCTAssertLessThanOrEqual(pdf.frame.maxX, companion.frame.minX + 1)
        let next = app.buttons["reader.fill.nextUnfinished"]
        let bounds = XCTAttachment(string: "companion=\(companion.frame) nextExists=\(next.exists) next=\(next.exists ? next.frame.debugDescription : "missing")\n\(app.debugDescription)")
        bounds.name = "Expanded-pane-bounds"; bounds.lifetime = .keepAlways; add(bounds)
        let fillCapture = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        fillCapture.name = "Production-Controlled-Expanded-Fill"; fillCapture.lifetime = .keepAlways; add(fillCapture)
        XCTAssertTrue(next.isHittable)
        XCTAssertTrue(companion.frame.contains(next.frame))
        editor.tap(); editor.typeText("Ada")
        XCTAssertEqual(editor.value as? String, "Ada")
        app.buttons["reader.fill.close"].tap()
        let afterClose = XCTAttachment(string: app.debugDescription)
        afterClose.name = "After-Fill-Close"; afterClose.lifetime = .keepAlways; add(afterClose)
        app.buttons["reader.build"].tap()
        let afterBuild = XCTAttachment(string: app.debugDescription)
        afterBuild.name = "After-Build"; afterBuild.lifetime = .keepAlways; add(afterBuild)
        XCTAssertTrue(app.buttons["reader.form.add"].waitForExistence(timeout: 5))
        let buildCapture = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        buildCapture.name = "Production-Controlled-Expanded-Build"; buildCapture.lifetime = .keepAlways; add(buildCapture)
        app.buttons["reader.done"].tap()
        app.buttons["reader.read"].tap()
        app.buttons["reader.probe.inspect"].tap()
        XCTAssertEqual(snapshot.label, original)
        app.buttons["reader.fill"].tap()
        XCTAssertEqual(editor.value as? String, "Ada")
        app.buttons["reader.probe.compact"].tap()
        XCTAssertTrue(app.buttons["reader.done"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["reader.form.field.0:0:Full name"].exists)
        app.buttons["reader.done"].tap()
        app.buttons["reader.probe.expanded"].tap()
        app.buttons["reader.fill"].tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertEqual(editor.value as? String, "Ada")
        editor.tap(); editor.typeText(" Lovelace")
        XCTAssertEqual(editor.value as? String, "Ada Lovelace")
        app.buttons["reader.fill.close"].tap()
        app.buttons["reader.probe.inspect"].tap()
        XCTAssertEqual(snapshot.label, original)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "Production-Controlled-Expanded-Read"; attachment.lifetime = .keepAlways; add(attachment)
    }

    func testTaskChangesPreserveNativePDFContext() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixture", "--ui-test-reader-continuity"]
        app.launch()
        app.buttons["library.document.Folik UI Test.pdf"].tap()
        let seed = app.buttons["reader.probe.seed"]
        XCTAssertTrue(seed.waitForExistence(timeout: 8))
        seed.tap()
        let snapshot = app.staticTexts["reader.probe.snapshot"]
        XCTAssertTrue(snapshot.waitForExistence(timeout: 3))
        let original = snapshot.label
        XCTAssertTrue(original.contains("scale=1.250"))
        XCTAssertTrue(original.contains("selection=Folik"))
        for task in ["reader.fill", "reader.build"] {
            app.buttons[task].tap()
            let done = app.buttons["reader.done"]
            XCTAssertTrue(done.waitForExistence(timeout: 3))
            done.tap()
            app.buttons["reader.read"].tap()
            app.buttons["reader.probe.inspect"].tap()
            XCTAssertEqual(snapshot.label, original)
        }
    }

    func testReaderStartsDocumentFirstWithNativeTaskActions() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-fixture"]
        app.launch()
        let document = app.buttons["library.document.Folik UI Test.pdf"]
        XCTAssertTrue(document.waitForExistence(timeout: 8))
        document.tap()
        XCTAssertTrue(app.descendants(matching: .any)["reader.pdf"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["reader.read"].exists)
        XCTAssertTrue(app.buttons["reader.fill"].exists)
        XCTAssertTrue(app.buttons["reader.build"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["reader.companion"].exists)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "Production-Reader-Read"; attachment.lifetime = .keepAlways; add(attachment)
    }
}

import XCTest
import XCUIAutomation

@MainActor
final class EditorInteractionTests: MokoUITestCase {
    func testTemporalEditorsAcceptTypedValuesAndKeepNativePickers() throws {
        for (kind, value) in [("date", "2026-11-20"), ("time", "09:45:00"), ("datetime", "2026-11-20 09:45:00")] {
            choose("temporal." + kind)
            XCTAssertTrue(application.datePickers.firstMatch.exists, kind)
            let field = application.textFields.firstMatch
            replace(field, with: value)
            XCTAssertEqual(field.value as? String, value)
            replace(field, with: "invalid")
            XCTAssertTrue(application.staticTexts["edit this value in the text field"].exists)
            replace(field, with: value)
            application.buttons["save"].click()
            XCTAssertEqual(displayedResult, value)
        }
    }

    func testObjectParametersPaginationAndTypeSelection() throws {
        choose("object.procedure")
        XCTAssertFalse(application.buttons["create"].isEnabled)
        for _ in 0..<4 { application.buttons["add parameter"].click() }
        XCTAssertTrue(application.staticTexts["parameters (4)"].exists)
        XCTAssertEqual(application.textFields.matching(identifier: "parameter name").count, 1)
        XCTAssertFalse(application.buttons["next parameters"].isEnabled)
        application.buttons["previous parameters"].click()
        XCTAssertEqual(application.textFields.matching(identifier: "parameter name").count, 3)
        selectMenu("parameter type", item: "varchar")
        let size = application.textFields["parameter type size or precision"].firstMatch
        replace(size, with: "80")
        XCTAssertEqual(size.value as? String, "80")
        application.buttons["remove parameter"].firstMatch.click()
        XCTAssertTrue(application.staticTexts["parameters (3)"].exists)
        XCTAssertFalse(application.buttons["next parameters"].exists)
        let body = application.textViews["sql body"]
        replace(body, with: "BEGIN SELECT 1; END")
        replace(application.textFields["object name"], with: "fixture_procedure")
        XCTAssertTrue(application.buttons["create"].isEnabled)
        try application.performAccessibilityAudit(for: .contrast)
    }

    func testNotificationsDismissAndExpire() throws {
        choose("notice")
        let message = application.staticTexts["changes applied"]
        XCTAssertTrue(message.waitForExistence(timeout: 3))
        application.buttons["dismiss"].click()
        XCTAssertTrue(message.waitForNonExistence(timeout: 3))
        application.buttons["show message"].click()
        XCTAssertTrue(message.waitForExistence(timeout: 3))
        application.buttons["fixture-light"].hover()
        XCTAssertTrue(message.waitForNonExistence(timeout: 8))
    }

    func testOnboardingResizesAndRespectsReducedMotion() throws {
        application.checkBoxes["fixture-reduce-motion"].click()
        choose("onboarding.2")
        for theme in ["light", "dark"] {
            application.buttons["fixture-" + theme].click()
            for _ in 0..<2 {
                application.buttons["fixture-size"].click()
                for choice in ["postgresql", "bundled", "external", "later"] {
                    XCTAssertTrue(application.buttons["sql-option." + choice].isHittable)
                }
                let image = XCTAttachment(screenshot: application.screenshot())
                image.name = "onboarding sql · " + theme
                image.lifetime = .keepAlways
                add(image)
                try application.performAccessibilityAudit(for: .contrast)
            }
        }
        application.buttons["sql-option.later"].click()
        application.buttons["continue"].click()
        XCTAssertTrue(application.buttons["set up php"].waitForExistence(timeout: 3))
        application.buttons["back"].click()
        XCTAssertTrue(application.buttons["sql-option.later"].waitForExistence(timeout: 3))
    }
}

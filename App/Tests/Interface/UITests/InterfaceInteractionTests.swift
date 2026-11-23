import XCTest
import XCUIAutomation

@MainActor
final class InterfaceInteractionTests: MokoUITestCase {
    func testSidebarNavigationAndGhostMariaDB() throws {
        for page in ["connections", "web server", "databases", "activity", "settings", "support", "overview"] {
            application.buttons[page].firstMatch.click()
            XCTAssertTrue(application.windows.firstMatch.exists, "navigation closed the window")
        }
        XCTAssertTrue(application.staticTexts["not installed"].exists)
        let install = application.buttons["install mariadb"]
        let content = application.scrollViews["workspace-scroll"]
        for _ in 0..<5 where !install.isHittable {
            content.scroll(byDeltaX: 0, deltaY: -280)
        }
        XCTAssertTrue(install.isHittable)
        install.click()
        XCTAssertTrue(application.staticTexts["mariadb-unavailable"].waitForExistence(timeout: 5))
        XCTAssertFalse(application.staticTexts["mariadb downloads have not been published yet"].exists)
    }

    func testOnboardingChoicesAndUnavailableDownload() throws {
        choose("onboarding.2")
        for option in ["external", "later", "bundled", "postgresql"] {
            let choice = application.buttons["sql-option." + option]
            XCTAssertTrue(choice.waitForExistence(timeout: 5))
            choice.click()
            XCTAssertEqual(choice.value as? String, "selected")
            if option == "bundled" {
                XCTAssertTrue(application.staticTexts["mariadb-unavailable"].exists)
                XCTAssertFalse(application.buttons["continue"].isEnabled)
            } else {
                XCTAssertTrue(application.buttons["continue"].isEnabled)
            }
        }
        application.buttons["fixture-dark"].click()
        application.buttons["sql-option.later"].click()
        application.buttons["continue"].click()
        XCTAssertTrue(application.buttons["set up php"].waitForExistence(timeout: 5))
        application.buttons["later"].click()
        XCTAssertTrue(application.buttons["open panel"].waitForExistence(timeout: 5))
    }

    func testTableFormsAndEngineSpecificModifiers() throws {
        for engine in ["postgresql", "mariadb"] {
            choose("table." + engine)
            let create = application.buttons["create table"]
            XCTAssertFalse(create.isEnabled)
            let name = application.textFields["table name"]
            XCTAssertTrue(name.isHittable)
            name.click()
            name.typeText("fixture_items")
            XCTAssertTrue(create.isEnabled)
            let primary = application.checkBoxes["primary key"].firstMatch
            XCTAssertTrue(primary.exists)
            XCTAssertFalse(application.checkBoxes["nullable"].firstMatch.isEnabled)
            XCTAssertEqual(application.checkBoxes["unsigned"].exists, engine == "mariadb")
            XCTAssertEqual(application.checkBoxes["identity"].exists, engine == "postgresql")
            application.buttons["add column"].click()
            XCTAssertEqual(application.textFields.matching(identifier: "column name").count, 2)
            let cancel = application.buttons["cancel"]
            XCTAssertEqual(cancel.frame.height, create.frame.height, accuracy: 1)
            try application.performAccessibilityAudit(for: .contrast)
        }
    }

    func testDestructiveDialogDefaultsToCancel() throws {
        choose("delete.sheet")
        application.buttons["review deletion"].click()
        let cancel = application.buttons["cancel"], delete = application.buttons["delete"]
        XCTAssertTrue(cancel.isHittable && delete.isHittable)
        XCTAssertEqual(cancel.frame.height, delete.frame.height, accuracy: 1)
        cancel.typeKey(.return, modifierFlags: [])
        XCTAssertEqual(displayedResult, "cancelled")
        application.buttons["review deletion"].click()
        application.buttons["delete"].click()
        XCTAssertEqual(displayedResult, "deleted")
    }

    func testConnectionPopupStates() throws {
        for state in ["testing", "starting", "stopped", "success", "failure"] {
            choose("connection." + state)
            XCTAssertTrue(application.staticTexts["connection test"].exists)
            XCTAssertEqual(application.buttons["close"].isEnabled, !["testing", "starting"].contains(state))
            if state == "failure" { XCTAssertTrue(application.staticTexts["error 1045"].exists) }
            if state == "success" { XCTAssertTrue(application.staticTexts["connection successful!"].exists) }
        }
    }

    func testRuntimeInstallationStates() throws {
        for state in ["unavailable", "ready", "download", "verifying", "cancelled", "error", "installed"] {
            choose("runtime." + state)
            if ["download", "verifying"].contains(state) {
                XCTAssertTrue(application.buttons["cancel"].exists)
                XCTAssertFalse(application.buttons["install mariadb"].exists)
            } else if state == "unavailable" {
                XCTAssertTrue(application.staticTexts["mariadb-unavailable"].exists)
            } else if state == "installed" {
                XCTAssertTrue(application.buttons["remove mariadb component"].exists)
            }
            let image = XCTAttachment(screenshot: application.screenshot())
            image.name = "runtime · " + state
            image.lifetime = .keepAlways
            add(image)
        }
    }

    func testNativeControlsHaveReadableContrastInBothThemes() throws {
        for theme in ["light", "dark"] {
            application.buttons["fixture-" + theme].click()
            for scene in ["profile", "column.postgresql", "table.postgresql", "delete", "constraint.index", "legal"] {
                choose(scene)
                try application.performAccessibilityAudit(for: .contrast)
            }
        }
    }

}

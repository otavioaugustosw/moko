import XCTest
import XCUIAutomation

@MainActor
final class OnboardingLayoutTests: MokoUITestCase {
    override var initialWindowSize: String? { "900x640" }

    func testExistingServerFieldsStayFullyVisibleAtMinimumSize() throws {
        choose("onboarding.2")
        application.buttons["sql-option.external"].click()
        let window = application.windows.firstMatch
        for theme in ["light", "dark"] {
            application.buttons["fixture-" + theme].click()
            for _ in 0..<2 {
                for name in ["engine", "host", "port", "user", "password", "save-password"] {
                    let field = application.descendants(matching: .any)["onboarding-" + name]
                    XCTAssertTrue(field.isHittable, name + " is not fully accessible")
                    XCTAssertTrue(window.frame.contains(field.frame), name + " extends outside the window")
                    XCTAssertLessThanOrEqual(field.frame.maxY, application.buttons["continue"].frame.minY, name)
                }
                XCTAssertTrue(application.buttons["back"].isHittable)
                XCTAssertTrue(application.buttons["continue"].isHittable)
                let image = XCTAttachment(screenshot: window.screenshot())
                image.name = "existing server · " + theme
                image.lifetime = .keepAlways
                add(image)
                try application.performAccessibilityAudit(for: .contrast)
                application.buttons["fixture-size"].click()
            }
        }
    }

    func testSQLChoicesDoNotMoveOrGrowOnHover() throws {
        choose("onboarding.2")
        for option in ["postgresql", "bundled", "external", "later"] {
            let button = application.buttons["sql-option." + option]
            let original = button.frame
            button.hover()
            XCTAssertEqual(button.frame, original, "hover changed the choice geometry")
        }
    }
}

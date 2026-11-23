import XCTest
import XCUIAutomation

@MainActor
class MokoUITestCase: XCTestCase {
    var application: XCUIApplication!
    var initialWindowSize: String? { nil }
    var displayedResult: String {
        let text = application.staticTexts["fixture-result"]
        return text.value as? String ?? text.label
    }
    override func setUpWithError() throws {
        continueAfterFailure = false
        application = XCUIApplication()
        application.launchEnvironment["MOKO_UI_TESTING"] = "1"
        if let initialWindowSize { application.launchEnvironment["MOKO_TEST_WINDOW_SIZE"] = initialWindowSize }
        application.launch()
        XCTAssertTrue(application.windows.firstMatch.waitForExistence(timeout: 15))
    }
    override func tearDownWithError() throws { application.terminate() }

    func choose(_ scenario: String) {
        selectMenu("fixture-selector", item: scenario)
    }
    func selectMenu(_ identifier: String, item title: String) {
        let picker = application.descendants(matching: .any).matching(identifier: identifier).firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 5), identifier)
        picker.click()
        let item = application.menuItems[title].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5), title)
        item.click()
    }
    func replace(_ field: XCUIElement, with text: String) {
        XCTAssertTrue(field.isHittable)
        field.click()
        field.typeKey("a", modifierFlags: .command)
        field.typeText(text)
    }
}

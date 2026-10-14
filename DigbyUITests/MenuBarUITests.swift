import XCTest

/// The menu bar extra: free space and "Quick clean (dry run)" against `fake-mo.sh`.
@MainActor
final class MenuBarUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        let fake = try XCTUnwrap(Bundle(for: Self.self).path(forResource: "fake-mo", ofType: "sh"))
        let configDir = "/tmp/digby-ui-\(UUID().uuidString)"
        app = XCUIApplication()
        app.launchArguments = [
            "-startView", "status",
            "-moBinaryPath", fake,
            "-moleConfigDir", configDir,
            "-showMenuBarExtra", "YES",
            "-menuBarShowsFree", "YES",
        ]
        app.launchEnvironment["FAKE_MO_DIR"] = configDir
        app.launch()
    }

    override func tearDown() async throws {
        app?.terminate()
    }

    func testQuickCleanPreviewsAndOpensReview() throws {
        let item = app.statusItems.firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 10), "menu bar extra is missing")
        item.click()

        let free = app.staticTexts["menubar.free"]
        XCTAssertTrue(free.waitForExistence(timeout: 5))
        XCTAssertTrue(text(free).hasSuffix("GB") || text(free).hasSuffix("TB"), "free space: \(text(free))")
        attachScreenshot("Menu bar · idle")

        app.buttons["menubar.quickClean"].click()
        let found = app.staticTexts["menubar.found"]
        XCTAssertTrue(found.waitForExistence(timeout: 20), "quick clean did not finish")
        XCTAssertEqual(text(found), "2.3 GB")
        attachScreenshot("Menu bar · results")

        // Review opens the main window on the Clean results.
        app.buttons["menubar.review"].click()
        XCTAssertTrue(app.buttons["clean.run"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["clean.run"].label, "Clean 2.3 GB")
    }

    private func text(_ element: XCUIElement) -> String {
        element.label.isEmpty ? (element.value as? String ?? "") : element.label
    }

    private func attachScreenshot(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}

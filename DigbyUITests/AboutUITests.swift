import XCTest

/// The About window opens from the app menu and shows the author's links.
@MainActor
final class AboutUITests: XCTestCase {
    func testAboutWindowShowsAuthorLinks() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-startView", "status", "-moBinaryPath", "/usr/bin/true", "-showMenuBarExtra", "NO"]
        app.launch()
        defer { app.terminate() }

        app.menuBars.menuBarItems["Digby"].click()
        app.menuBars.menuBarItems["Digby"].menuItems["About Digby"].firstMatch.click()

        let version = app.staticTexts["about.version"]
        XCTAssertTrue(version.waitForExistence(timeout: 5), "About window did not open")
        let versionText = version.label.isEmpty ? (version.value as? String ?? "") : version.label
        XCTAssertTrue(versionText.hasPrefix("Version "), versionText)
        for id in ["about.portfolio", "about.github", "about.coffee"] {
            XCTAssertTrue(app.descendants(matching: .any)[id].exists, "\(id) missing")
        }

        let shot = XCTAttachment(screenshot: app.windows["About Digby"].firstMatch.screenshot())
        shot.name = "About window"
        shot.lifetime = .keepAlways
        add(shot)
    }
}

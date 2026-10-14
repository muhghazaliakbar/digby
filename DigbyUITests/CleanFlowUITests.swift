import XCTest

/// Drives the Clean flow against `fake-mo.sh`, which replays real Mole output.
/// Nothing on the Mac is scanned or removed: the fake prints made-up paths, and Digby's
/// Mole config folder is redirected to a throwaway folder under /tmp.
///
/// The test runner is sandboxed, so it cannot read that folder; every check goes through
/// the UI. The fake leaves whitelisted (unchecked) paths out of its totals, so the sizes
/// Digby shows after a run prove whether exclusions reached Mole.
@MainActor
final class CleanFlowUITests: XCTestCase {
    private var app: XCUIApplication!

    // Sizes the fake reports: Google 800 MB, Homebrew 400 MB, logs 172 KB, Chrome 640 MB, npm 465.5 MB.
    private let everything = "2.3 GB"
    private let withoutGoogle = "1.5 GB"

    override func setUp() async throws {
        continueAfterFailure = false
        let fake = try XCTUnwrap(Bundle(for: Self.self).path(forResource: "fake-mo", ofType: "sh"), "fake-mo.sh missing from the test bundle")
        let configDir = "/tmp/digby-ui-\(UUID().uuidString)"

        app = XCUIApplication()
        app.launchArguments = [
            "-startView", "clean",
            "-moBinaryPath", fake,
            "-moleConfigDir", configDir,
            "-showTerminal", "NO",
        ]
        app.launchEnvironment["FAKE_MO_DIR"] = configDir
    }

    override func tearDown() async throws {
        app?.terminate()
    }

    // MARK: Tests

    func testScanShowsReviewableResults() throws {
        app.launch()
        scan()

        XCTAssertTrue(category("User essentials").exists)
        XCTAssertTrue(category("Browsers").exists)
        XCTAssertTrue(category("Developer tools").exists)
        XCTAssertEqual(summaryText, "5 of 5 locations")
        XCTAssertEqual(runButton.label, "Clean \(everything)")
        XCTAssertEqual(app.staticTexts["clean.headline"].exists, false, "results replace the centered screen")
    }

    func testUncheckingAnItemUpdatesTotals() throws {
        app.launch()
        scan()

        category("User essentials").click()
        let google = item("/Users/test/Library/Caches/Google")
        XCTAssertTrue(google.waitForExistence(timeout: 5))
        XCTAssertEqual(google.value as? String, "checked")
        google.click()

        XCTAssertEqual(google.value as? String, "unchecked")
        XCTAssertEqual(categoryCheckbox("User essentials").value as? String, "some")
        XCTAssertEqual(summaryText, "4 of 5 locations")
        XCTAssertEqual(runButton.label, "Clean \(withoutGoogle)")
    }

    func testNoneAndSelectAll() throws {
        app.launch()
        scan()

        app.buttons["None"].click()
        // Rows Mole cleans as a whole ("npm cache directory") cannot be excluded and stay selected.
        XCTAssertEqual(summaryText, "1 of 5 locations")
        XCTAssertEqual(categoryCheckbox("Browsers").value as? String, "none")
        XCTAssertEqual(categoryCheckbox("Developer tools").value as? String, "all")

        app.buttons["Select all"].click()
        XCTAssertEqual(summaryText, "5 of 5 locations")
        XCTAssertEqual(categoryCheckbox("Browsers").value as? String, "all")
    }

    func testDryRunPreviewHonoursExclusionsAndRestoresWhitelist() throws {
        app.launch()
        scan()

        category("User essentials").click()
        item("/Users/test/Library/Caches/Google").click()
        dryRunToggle.click()
        XCTAssertEqual(dryRunToggle.value as? String, "on")
        XCTAssertEqual(runButton.label, "Preview \(withoutGoogle)")

        // Preview with one location unchecked: Mole must skip it.
        runButton.click()
        XCTAssertTrue(headline(equals: "Dry run finished", timeout: 20))
        XCTAssertTrue(ringValue(equals: withoutGoogle), "the unchecked path reached Mole as an exclusion")

        // Back to results keeps the selection and the dry-run toggle.
        app.buttons["clean.backToResults"].click()
        XCTAssertTrue(runButton.waitForExistence(timeout: 5))
        XCTAssertEqual(summaryText, "4 of 5 locations")
        XCTAssertEqual(runButton.label, "Preview \(withoutGoogle)")

        // With everything selected Digby writes no exclusions. If the temporary whitelist had
        // not been restored, the fake would still skip Google and report 1.5 GB.
        app.buttons["Select all"].click()
        runButton.click()
        XCTAssertTrue(headline(equals: "Dry run finished", timeout: 20))
        XCTAssertTrue(ringValue(equals: everything), "the temporary whitelist was restored after the previous run")
    }

    func testCleanRunsMoleAndShowsDone() throws {
        app.launch()
        scan()

        XCTAssertEqual(dryRunToggle.value as? String, "off")
        runButton.click()
        XCTAssertTrue(headline(equals: "Your Mac is lighter", timeout: 20))
        XCTAssertTrue(ringValue(equals: everything))
        XCTAssertTrue(app.buttons["clean.scanAgain"].exists)
        XCTAssertFalse(app.buttons["clean.backToResults"].exists, "Back to results is only offered after a dry run")
    }

    func testStopCancelsScan() throws {
        app.launchEnvironment["FAKE_MO_DELAY"] = "0.6"
        app.launch()

        app.buttons["clean.scan"].click()
        let stop = app.buttons["clean.stop"]
        XCTAssertTrue(stop.waitForExistence(timeout: 5))
        stop.click()

        XCTAssertTrue(headline(equals: "Dig out the junk", timeout: 5))
        XCTAssertTrue(app.buttons["clean.scan"].waitForExistence(timeout: 5))
    }

    func testEmptyScanShowsNothingToClean() throws {
        app.launchEnvironment["FAKE_MO_EMPTY"] = "1"
        app.launch()

        app.buttons["clean.scan"].click()
        XCTAssertTrue(headline(equals: "Nothing left to clean", timeout: 20))
        XCTAssertTrue(app.buttons["clean.scanAgain"].exists)
    }

    // MARK: Helpers

    private func scan() {
        let scan = app.buttons["clean.scan"]
        XCTAssertTrue(scan.waitForExistence(timeout: 10), "Clean idle screen did not appear")
        scan.click()
        XCTAssertTrue(runButton.waitForExistence(timeout: 20), "scan did not reach the results screen")
    }

    private var runButton: XCUIElement { app.buttons["clean.run"] }
    private var dryRunToggle: XCUIElement { app.buttons["clean.dryRun"] }

    private var summaryText: String {
        let summary = app.staticTexts["clean.summary"]
        return (summary.value as? String).flatMap { $0.isEmpty ? nil : $0 } ?? summary.label
    }

    private func category(_ name: String) -> XCUIElement {
        app.descendants(matching: .any)["clean.category.\(name)"]
    }

    private func categoryCheckbox(_ name: String) -> XCUIElement {
        app.buttons["clean.category.checkbox.\(name)"]
    }

    private func item(_ path: String) -> XCUIElement {
        app.descendants(matching: .any)["clean.item.\(path)"]
    }

    private func headline(equals text: String, timeout: TimeInterval) -> Bool {
        waitForText(app.staticTexts["clean.headline"], text, timeout: timeout)
    }

    private func ringValue(equals text: String) -> Bool {
        waitForText(app.staticTexts["clean.ringValue"], text, timeout: 5)
    }

    private func waitForText(_ element: XCUIElement, _ text: String, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "label == %@ OR value == %@", text, text)
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: timeout) == .completed
    }
}

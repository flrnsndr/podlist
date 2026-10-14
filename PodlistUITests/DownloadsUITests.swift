import XCTest

/// Slice 5 flows (concept §4.7): download an episode, find it in the storage screen under its
/// podcast and delete it there (A55: the library's filter "Geladen" is gone). Files come from the
/// offline network.
final class DownloadsUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        return app
    }

    @MainActor
    func testDownloadingAnEpisodeAndDeletingItInStorage() {
        let app = launch()
        app.buttons["Methodisch inkorrekt"].firstMatch.tapWhenReady()
        app.staticTexts["Methodisch inkorrekt 3"].tapWhenReady()

        let download = app.buttons["downloadButton"]
        XCTAssertEqual(download.waitForLabel("Download"), true)
        download.tap()
        XCTAssertEqual(download.waitForLabel("Delete Download", timeout: 10), true, "the download finished")
        app.buttons["Done"].tap()
        app.navigationBars.buttons.firstMatch.tap()

        app.buttons["storageButton"].tapWhenReady()
        XCTAssertTrue(app.navigationBars["Storage"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Downloads"].exists)
        app.buttons["sortPodcastStorage"].tap()
        app.buttons["Name"].tapWhenReady()

        let podcast = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Methodisch inkorrekt")).firstMatch
        XCTAssertTrue(podcast.waitForExistence(timeout: 5), "listed under Downloads")
        podcast.tap()
        let row = app.cells.containing(NSPredicate(format: "label CONTAINS %@", "Methodisch inkorrekt 3")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "listed in the podcast's downloads")
        XCTAssertFalse(app.cells.containing(NSPredicate(format: "label CONTAINS %@", "Methodisch inkorrekt 2")).firstMatch.exists,
                       "only downloaded episodes")

        row.swipeLeft()
        app.buttons["Delete Download"].tapWhenReady()
        XCTAssertTrue(app.staticTexts["No Downloads"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["No downloaded episodes."].waitForExistence(timeout: 5))
    }
}

extension XCUIElement {
    /// Waits until the element's label is `label`.
    func waitForLabel(_ label: String, timeout: TimeInterval = 5) -> Bool {
        let predicate = NSPredicate(format: "label == %@", label)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }
}

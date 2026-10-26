import XCTest

/// Slice 5 flows (concept §4.7): download an episode from its row's context menu, find it in the storage screen under its
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
        // The download lives in the row's context menu (N103: not in the episode details).
        let episode = app.staticTexts["Methodisch inkorrekt 3"]
        XCTAssertTrue(episode.waitForExistence(timeout: 5))
        episode.press(forDuration: 1)
        app.buttons["Download"].tapWhenReady()
        XCTAssertTrue(app.buttons["Download"].waitForNonExistence(timeout: 5), "the context menu closed")
        app.navigationBars.buttons.firstMatch.tap()

        app.buttons["settingsButton"].tapWhenReady()
        app.buttons["Storage"].tapWhenReady()
        XCTAssertTrue(app.navigationBars["Storage"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Downloads"].exists)
        app.buttons["sortPodcastStorage"].tap()
        app.buttons["Name"].tapWhenReady()

        let podcast = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Methodisch inkorrekt")).firstMatch
        XCTAssertTrue(podcast.waitForExistence(timeout: 10), "the download finished and is listed under Downloads")
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

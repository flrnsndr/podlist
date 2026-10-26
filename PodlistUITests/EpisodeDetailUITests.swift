import XCTest

/// Episode details (N103): "Zu Playlists" adds the episode to its podcast's playlists with a
/// tap and a "Rückgängig" banner in the sheet; then it reads "In Playlists" and a tap leads to
/// "Zu Playlist …", as a long press does.
final class EpisodeDetailUITests: XCTestCase {
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
    func testToPlaylistsAddsWithUndoThenShowsItsStateAndOpensTheChoice() {
        let app = launch()
        app.buttons["Lage der Nation"].firstMatch.tapWhenReady()
        // In no playlist yet, its podcast is in News and Politics (sample data).
        app.staticTexts["Lage der Nation 4"].tapWhenReady()
        let add = app.buttons["addToPlaylist"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        XCTAssertEqual(add.label, "To Playlists")
        // The podcast page behind the sheet shows its playlists, too: count the chips.
        let news = app.buttons.matching(identifier: "News")
        let politics = app.buttons.matching(identifier: "Politics")
        let before = (news.count, politics.count)

        add.tap()
        XCTAssertTrue(news.element(boundBy: before.0).waitForExistence(timeout: 5), "added to News")
        XCTAssertEqual(politics.count, before.1 + 1, "added to Politics")
        XCTAssertTrue(app.buttons["undoBannerButton"].waitForExistence(timeout: 5), "banner in the sheet")
        XCTAssertEqual(add.label, "In Playlists")
        // The root view's banner waits behind the sheet; tap the one in the sheet.
        let undo = app.buttons.matching(identifier: "undoBannerButton").allElementsBoundByIndex.first(where: \.isHittable)
        XCTAssertNotNil(undo)
        undo?.tap()
        XCTAssertTrue(app.buttons["To Playlists"].waitForExistence(timeout: 5), "undo from the sheet")
        add.tap()
        XCTAssertTrue(app.buttons["In Playlists"].waitForExistence(timeout: 5))

        add.press(forDuration: 1)
        XCTAssertTrue(app.buttons["Choose Playlists…"].waitForExistence(timeout: 5))
        app.buttons["Choose Playlists…"].tap()
        XCTAssertTrue(app.navigationBars["Add to Playlist"].waitForExistence(timeout: 5))
        app.navigationBars["Add to Playlist"].buttons["Done"].tap()

        add.tapWhenReady()
        XCTAssertTrue(app.navigationBars["Add to Playlist"].waitForExistence(timeout: 5), "a tap opens the choice now")
        XCTAssertTrue(app.buttons["addToPlaylist.News"].isSelected)
    }
}

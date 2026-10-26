import XCTest

/// Slice 3 and 7 flows (concept §4.4, §6.6, §9): play a playlist (a tap replaces, a long press
/// offers all ways, the setting "Ask" shows a dialog), undo, Play Next, the Up Next list and
/// clearing it, Up Next in its own tab. Sample data: "News" holds "Lage der
/// Nation 1…3", "Entertainment" holds "Hotel Matze 1…3". Audio never loads; the player keeps
/// the episode.
final class UpNextUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(asking: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        if asking { app.launchArguments += ["-playlistStartPreference.v2", "ask"] }
        app.launch()
        return app
    }

    /// The row of a playlist in the Playlists tab (not an episode of the Up Next preview),
    /// scrolled into view below the preview.
    @MainActor
    private func playlistRow(_ name: String, in app: XCUIApplication) -> XCUIElement {
        let row = app.buttons.matching(identifier: "playlistRow").matching(NSPredicate(format: "label CONTAINS %@", name)).firstMatch
        let list = app.collectionViews.firstMatch
        // The list loads rows lazily: one below the screen exists only once scrolled to.
        for _ in 0..<4 where !row.waitForExistence(timeout: 2) { list.swipeUp() }
        row.scrollIntoView(in: list)
        return row
    }

    @MainActor
    private func playPlaylist(_ name: String, in app: XCUIApplication) {
        app.tabBars.buttons["Playlists"].tapWhenReady()
        playlistRow(name, in: app).tapWhenReady()
        app.buttons["playPlaylistButton"].tapWhenReady()
    }

    @MainActor
    private func assertMiniPlayer(_ title: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate(format: "label == %@", title)
        XCTAssertTrue(app.buttons["miniPlayer"].waitFor(predicate), "mini player does not show \(title)", file: file, line: line)
    }

    /// Up Next is its own tab (N92; the player has no button for it, N80).
    @MainActor
    private func openUpNext(in app: XCUIApplication) {
        app.tabBars.buttons["Queue"].tapWhenReady()
        XCTAssertTrue(app.navigationBars["Queue"].waitForExistence(timeout: 5))
    }

    /// The banner shows in the window and in the player sheet; tap the visible one.
    @MainActor
    private func tapUndo(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let banners = app.buttons.matching(identifier: "undoBannerButton")
        XCTAssertTrue(banners.firstMatch.waitForExistence(timeout: 5), "undo banner missing", file: file, line: line)
        let visible = banners.allElementsBoundByIndex.first(where: \.isHittable)
        XCTAssertNotNil(visible, "no visible undo banner", file: file, line: line)
        visible?.tap()
    }

    /// N43: a tap replaces Up Next right away, with "Rückgängig".
    @MainActor
    func testATapReplacesUpNextAndCanBeUndone() {
        let app = launch()
        playPlaylist("News", in: app)
        assertMiniPlayer("Lage der Nation 1", in: app)

        app.navigationBars.buttons["Playlists"].tap()
        playPlaylist("Entertainment", in: app)
        assertMiniPlayer("Hotel Matze 1", in: app)

        tapUndo(in: app)
        assertMiniPlayer("Lage der Nation 1", in: app)
    }

    /// Scenario 4c via the ▶ of a playlist row: a long press, "Play After Current Episode";
    /// the Queue tab shows the new playlist's episodes right after the running one (ADR 0008).
    @MainActor
    func testLongPressPlaysAPlaylistAfterTheCurrentEpisode() {
        let app = launch()
        playPlaylist("News", in: app)
        app.navigationBars.buttons["Playlists"].tap()
        _ = playlistRow("Entertainment", in: app)
        let play = app.buttons.matching(identifier: "playlistPlayButton")
            .matching(NSPredicate(format: "label CONTAINS %@", "Entertainment")).firstMatch
        play.press(forDuration: 1.2)
        app.buttons["Play After Current Episode"].firstMatch.tapWhenReady()
        assertMiniPlayer("Lage der Nation 1", in: app)

        XCTAssertTrue(app.staticTexts["Playing: Lage der Nation 1"].exists, "the running playlist says so")

        openUpNext(in: app)
        let first = app.staticTexts["Hotel Matze 1"]
        XCTAssertTrue(first.waitForExistence(timeout: 5), "Entertainment comes next")
        XCTAssertLessThan(first.frame.minY, app.staticTexts["Lage der Nation 2"].frame.minY, "before the rest of News")
    }

    /// "Add to End of Queue": the playlist's episodes follow the waiting ones as plain rows (A89).
    @MainActor
    func testAppendingAPlaylistShowsItsEpisodesAtTheEndOfUpNext() {
        let app = launch(asking: true)
        playPlaylist("News", in: app)
        app.navigationBars.buttons["Playlists"].tap()
        playPlaylist("Entertainment", in: app)
        app.buttons["Add to End of Queue"].firstMatch.tapWhenReady()
        assertMiniPlayer("Lage der Nation 1", in: app)

        openUpNext(in: app)
        XCTAssertTrue(app.staticTexts["Lage der Nation 2"].waitForExistence(timeout: 5), "the rest of News is missing")
        XCTAssertTrue(app.staticTexts["Hotel Matze 3"].exists, "Entertainment shows all its episodes")
        XCTAssertLessThan(app.staticTexts["Lage der Nation 3"].frame.minY, app.staticTexts["Hotel Matze 1"].frame.minY, "Entertainment comes last")
    }

    @MainActor
    func testPlayNextAndClearingUpNext() {
        let app = launch()
        playPlaylist("News", in: app)
        app.navigationBars.buttons["Playlists"].tap()
        playlistRow("Entertainment", in: app).tapWhenReady()
        app.staticTexts["Hotel Matze 2"].tapWhenReady()
        app.buttons["Play Next"].tapWhenReady()
        app.buttons["Done"].tapWhenReady()

        openUpNext(in: app)
        XCTAssertTrue(app.staticTexts["Hotel Matze 2"].waitForExistence(timeout: 5))
        app.buttons["clearUpNextButton"].tapWhenReady()
        XCTAssertTrue(app.staticTexts["Hotel Matze 2"].waitForNonExistence(timeout: 5), "the queue was not cleared")
        XCTAssertTrue(app.staticTexts["Previous Queues"].waitForExistence(timeout: 5))

        tapUndo(in: app)
        XCTAssertTrue(app.staticTexts["Hotel Matze 2"].waitForExistence(timeout: 5), "undo did not restore the queue")
    }

    /// The running episode and the waiting ones share a list section: the running one swipes away (the
    /// next one starts), and its details lead to the podcast through the podcast name.
    @MainActor
    func testRunningEpisodeSwipesAwayAndDetailsOpenThePodcast() {
        let app = launch()
        playPlaylist("News", in: app)
        assertMiniPlayer("Lage der Nation 1", in: app)

        // The player of the running episode opens its podcast the same way.
        app.buttons["miniPlayer"].tapWhenReady()
        app.buttons["playerPodcastLink"].tapWhenReady()
        XCTAssertTrue(app.staticTexts["Episodes"].waitForExistence(timeout: 5), "the podcast details were not pushed from the player")
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["Done"].tapWhenReady()

        openUpNext(in: app)
        let running = app.descendants(matching: .any).matching(identifier: "upNextNowPlaying").firstMatch
        XCTAssertTrue(running.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Lage der Nation 2"].exists, "the waiting episodes show with it")

        running.tap()
        app.buttons["episodePodcastLink"].tapWhenReady()
        XCTAssertTrue(app.staticTexts["Episodes"].waitForExistence(timeout: 5), "the podcast details were not pushed")
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["Done"].tapWhenReady()

        running.swipeLeft()
        app.buttons["Delete"].tapWhenReady()
        assertMiniPlayer("Lage der Nation 2", in: app)
    }
}

extension XCUIElement {
    func waitFor(_ predicate: NSPredicate, timeout: TimeInterval = 5) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }
}

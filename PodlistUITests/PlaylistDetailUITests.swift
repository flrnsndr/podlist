import XCTest

/// A playlist while it is in the queue (concept §4.4 v0.7, N106): the list splits into
/// "In the Queue" and "After That", dragging in the queue part reorders the queue, and a
/// swipe takes an episode out of the queue into the draft. Sample data: "News" holds
/// "Lage der Nation 1…3", "Entertainment" holds "Hotel Matze 1…3".
final class PlaylistDetailUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        app.tabBars.buttons["Playlists"].tapWhenReady()
        return app
    }

    @MainActor
    private func openPlaylist(_ name: String, in app: XCUIApplication) {
        app.buttons.matching(identifier: "playlistRow").matching(NSPredicate(format: "label CONTAINS %@", name)).firstMatch.tapWhenReady()
    }

    @MainActor
    func testQueuedPlaylistSplitsDragsInTheQueueAndSwipesOut() {
        let app = launch()
        openPlaylist("News", in: app)
        XCTAssertFalse(app.staticTexts["playlistLiveHeader"].exists, "nothing queued, no sections")
        app.buttons["playPlaylistButton"].tapWhenReady()

        // Entertainment: one episode queued next, the other two wait in the draft.
        app.navigationBars.buttons["Playlists"].tapWhenReady()
        openPlaylist("Entertainment", in: app)
        app.staticTexts["Hotel Matze 2"].tapWhenReady()
        app.buttons["Play Next"].tapWhenReady()
        app.buttons["Done"].tapWhenReady()
        XCTAssertTrue(app.staticTexts["playlistLiveHeader"].waitForExistence(timeout: 5), "the queue part is missing")
        XCTAssertTrue(app.staticTexts["playlistDraftHeader"].exists, "the draft part is missing")
        XCTAssertLessThan(app.staticTexts["Hotel Matze 2"].frame.minY, app.staticTexts["Hotel Matze 1"].frame.minY, "the queued episode comes first")

        // News: the running episode stays put, the two waiting ones swap by dragging.
        app.navigationBars.buttons["Playlists"].tapWhenReady()
        openPlaylist("News", in: app)
        let second = app.staticTexts["Lage der Nation 2"]
        let third = app.staticTexts["Lage der Nation 3"]
        XCTAssertTrue(third.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["playlistDraftHeader"].exists, "all of News is queued")
        app.buttons["Edit"].tapWhenReady()
        let handles = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Reorder"))
        XCTAssertTrue(handles.firstMatch.waitForExistence(timeout: 5), "no reorder handles")
        XCTAssertEqual(handles.count, 2, "the running episode has no handle")
        handles.element(boundBy: 1).press(forDuration: 0.6, thenDragTo: handles.element(boundBy: 0))
        app.buttons["Done"].tapWhenReady()
        XCTAssertLessThan(third.frame.minY, second.frame.minY, "the dragged episode moved up")

        // The queue follows, the playlist itself does not change (N104).
        app.tabBars.buttons["Queue"].tapWhenReady()
        XCTAssertTrue(third.waitForExistence(timeout: 5))
        XCTAssertLessThan(third.frame.minY, second.frame.minY, "the queue was reordered")

        // Swiping out of the queue: the episode moves to the draft.
        app.tabBars.buttons["Playlists"].tapWhenReady()
        XCTAssertTrue(third.waitForExistence(timeout: 5))
        third.swipeLeft()
        app.buttons["Remove from Queue"].tapWhenReady()
        XCTAssertTrue(app.staticTexts["playlistDraftHeader"].waitForExistence(timeout: 5), "the draft part did not appear")
        XCTAssertLessThan(second.frame.minY, third.frame.minY, "the removed episode waits below")
        XCTAssertLessThan(app.staticTexts["playlistDraftHeader"].frame.minY, third.frame.minY, "under \"After That\"")
    }
}

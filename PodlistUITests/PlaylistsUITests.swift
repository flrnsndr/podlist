import XCTest

/// Playlist flows: "Everything", dragging and deleting a playlist. Sample data: "News" holds
/// "Lage der Nation 1…3".
final class PlaylistsUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func launchAndOpenPlaylists() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        app.tabBars.buttons["Playlists"].tapWhenReady()
        return app
    }

    /// "Everything" (concept §4.1, N70–N73): first in the list, the episodes of all playlists,
    /// one fixed sort (N97); leaving out a playlist takes its episodes out.
    @MainActor
    func testEverythingMirrorsThePlaylistsAndLeavesOneOut() {
        let app = launchAndOpenPlaylists()
        app.buttons["everythingRow"].tapWhenReady()
        XCTAssertTrue(app.staticTexts["Hotel Matze 1"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Lage der Nation 1"].exists)

        app.buttons["playlistMenu"].tapWhenReady()
        XCTAssertTrue(app.buttons["everythingSelectionLink"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Release Date"].exists || app.buttons["Manual"].exists, "no sort to choose (N97)")
        app.buttons["everythingSelectionLink"].tapWhenReady()
        let entertainment = app.switches.matching(NSPredicate(format: "label CONTAINS %@", "Entertainment")).firstMatch
        XCTAssertTrue(entertainment.waitForExistence(timeout: 5))
        entertainment.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()

        XCTAssertTrue(app.staticTexts["Hotel Matze 1"].waitForNonExistence(timeout: 5), "Entertainment is left out")
        XCTAssertTrue(app.staticTexts["Lage der Nation 1"].exists)
    }

    /// N96: dragging works in a sorted playlist, too, and switches it to manual.
    @MainActor
    func testDraggingInASortedPlaylistSwitchesItToManual() {
        let app = launchAndOpenPlaylists()
        app.staticTexts["News"].firstMatch.tapWhenReady()
        app.buttons["playlistMenu"].tapWhenReady()
        app.buttons["Release Date"].tapWhenReady()
        app.buttons["playlistMenu"].tapWhenReady()
        app.buttons["Newest First"].tapWhenReady()
        let newest = app.staticTexts["Lage der Nation 3"]
        let oldest = app.staticTexts["Lage der Nation 1"]
        XCTAssertTrue(oldest.waitForExistence(timeout: 5))
        XCTAssertLessThan(newest.frame.minY, oldest.frame.minY)

        app.buttons["Edit"].tapWhenReady()
        let handles = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Reorder"))
        XCTAssertTrue(handles.firstMatch.waitForExistence(timeout: 5), "no reorder handles")
        handles.element(boundBy: handles.count - 1).press(forDuration: 0.6, thenDragTo: handles.element(boundBy: 0))
        app.buttons["Done"].tapWhenReady()
        XCTAssertLessThan(oldest.frame.minY, newest.frame.minY, "the dragged episode is on top")

        app.buttons["playlistMenu"].tapWhenReady()
        XCTAssertTrue(app.buttons["Manual"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Newest First"].exists, "manual has no direction")
    }

    /// N67: no swipe to delete; deleting lives at the bottom of the editor and asks first.
    @MainActor
    func testDeletingAPlaylistFromTheEditorAsksFirst() {
        let app = launchAndOpenPlaylists()
        let row = app.staticTexts["News"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.swipeLeft()
        XCTAssertFalse(app.buttons["Delete"].waitForExistence(timeout: 2), "swipe still offers Delete")
        row.swipeRight()

        row.tapWhenReady()
        app.buttons["playlistMenu"].tapWhenReady()
        app.buttons["Edit Playlist"].tapWhenReady()
        let delete = app.buttons["deletePlaylistButton"]
        for _ in 0..<5 where !delete.isHittable { app.swipeUp() }
        delete.tapWhenReady()

        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5), "no confirmation")
        alert.buttons["Cancel"].tap()
        XCTAssertTrue(delete.waitForExistence(timeout: 5), "cancel closed the editor")

        delete.tapWhenReady()
        app.alerts.firstMatch.buttons["Delete"].tapWhenReady()
        XCTAssertTrue(app.buttons["newPlaylistButton"].waitForExistence(timeout: 5), "not back in the Playlists tab")
        let newsRow = app.buttons.matching(identifier: "playlistRow").matching(NSPredicate(format: "label CONTAINS 'News'"))
        XCTAssertTrue(newsRow.firstMatch.waitForNonExistence(timeout: 5), "playlist still listed")
    }
}

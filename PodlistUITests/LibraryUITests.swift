import XCTest

/// Library flows: subscribe via search, filters and hidden playlists.
/// The app runs with sample data and an offline network (`-uiTesting`).
final class LibraryUITests: XCTestCase {
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
    func testSubscribingFromSearch() {
        let app = launch()
        app.tabBars.buttons["Search"].tapWhenReady()
        let field = app.searchFields.firstMatch
        field.tapWhenReady()
        field.typeText("Offline")

        app.staticTexts["Offline Radio"].firstMatch.tapWhenReady()
        XCTAssertTrue(app.staticTexts["Offline Episode 2"].waitForExistence(timeout: 5), "preview shows episodes")
        app.buttons["Subscribe"].tapWhenReady()

        // "In welche Playlists?": Technology is preselected from the feed's category.
        XCTAssertTrue(app.navigationBars["Add to Playlists"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Technology"].isSelected, "suggested by category")
        XCTAssertTrue(app.buttons["Technology, Off"].exists, "auto-add starts off (N93)")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["Subscribed"].waitForExistence(timeout: 5))

        app.tabBars.buttons["Library"].tap()
        XCTAssertTrue(app.buttons["Offline Radio"].waitForExistence(timeout: 5), "library shows the new podcast")

        // Auto-add is off and no existing episode is added (N93): the newest waits in the inbox.
        app.tabBars.buttons["Inbox"].tap()
        XCTAssertTrue(app.staticTexts["Offline Episode 2"].waitForExistence(timeout: 5), "the newest episode waits in the inbox")
        app.tabBars.buttons["Playlists"].tap()
        app.staticTexts["Technology"].firstMatch.tapWhenReady()
        XCTAssertFalse(app.staticTexts["Offline Episode 2"].waitForExistence(timeout: 2), "nothing was added to the playlist")
    }

    /// N42, N65, N66: "No Playlist" shows the podcasts without a playlist. A hidden playlist
    /// keeps its podcasts out of "All"; its chip waits behind "More", after "No Playlist".
    /// "More" works for the whole app and collapses in the background, where a filter on a
    /// hidden playlist goes back to "All"; the assignment sheet has its own "More". Sample
    /// data: "Entertainment" is Hotel Matze's only playlist. The inbox side is covered by
    /// `InboxRulesTests`.
    @MainActor
    func testHiddenPlaylistsAndTheirMoreButton() {
        let app = launch()
        hideEntertainment(in: app)
        XCTAssertTrue(app.buttons["hiddenPlaylistsRow"].waitForExistence(timeout: 5), "playlists tab: behind a row")
        XCTAssertFalse(app.staticTexts["Entertainment"].exists)

        app.tabBars.buttons["Library"].tap()
        XCTAssertTrue(app.buttons["Lage der Nation"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Hotel Matze"].exists, "hidden under All")
        let filterBar = app.scrollViews["libraryFilterBar"]
        let noPlaylist = filterBar.buttons["No Playlist"]
        noPlaylist.scrollIntoView(in: filterBar, left: true)
        noPlaylist.tap()
        XCTAssertTrue(app.buttons["Zeit Verbrechen"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Lage der Nation"].exists)

        let chip = filterBar.buttons["Entertainment"]
        XCTAssertFalse(chip.exists, "behind More")
        let more = filterBar.buttons["hiddenPlaylistsButton"]
        more.scrollIntoView(in: filterBar, left: true)
        XCTAssertGreaterThan(more.frame.minX, noPlaylist.frame.maxX, "More comes last")
        more.tap()
        chip.scrollIntoView(in: filterBar, left: true)
        XCTAssertGreaterThan(chip.frame.minX, noPlaylist.frame.maxX, "hidden chip comes last")
        XCTAssertEqual(chip.value as? String, "Hidden")
        chip.tap()
        XCTAssertTrue(app.buttons["Hotel Matze"].waitForExistence(timeout: 5), "shown under its chip")

        app.tabBars.buttons["Playlists"].tap()
        XCTAssertTrue(app.staticTexts["Entertainment"].waitForExistence(timeout: 5), "More in the library opened it here too")

        app.tabBars.buttons["Library"].tap()
        XCTAssertTrue(app.buttons["Hotel Matze"].waitForExistence(timeout: 5))
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.buttons["Lage der Nation"].waitForExistence(timeout: 5), "back on All")
        XCTAssertFalse(app.buttons["Hotel Matze"].exists)
        XCTAssertFalse(chip.exists, "collapsed")

        app.buttons["Lage der Nation"].firstMatch.tap()
        app.buttons["editPlaylists"].tapWhenReady()
        XCTAssertTrue(app.buttons["News"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Entertainment"].exists, "behind More in the sheet")
        app.buttons["hiddenPlaylistsButton"].firstMatch.tapWhenReady()
        XCTAssertTrue(app.buttons["Entertainment"].waitForExistence(timeout: 5))
    }
}

/// Hides "Entertainment" in its editor and goes back to the playlists list.
@MainActor
func hideEntertainment(in app: XCUIApplication) {
    app.tabBars.buttons["Playlists"].tapWhenReady()
    app.staticTexts["Entertainment"].firstMatch.tapWhenReady()
    app.buttons["playlistMenu"].tapWhenReady()
    app.buttons["Edit Playlist"].tapWhenReady()
    let toggle = app.switches["hiddenPlaylistToggle"]
    // The form loads its rows lazily: the toggle exists only once it was scrolled to.
    let form = app.collectionViews.firstMatch
    XCTAssertTrue(form.waitForExistence(timeout: 5))
    for _ in 0..<5 where !toggle.exists { form.swipeUp() }
    toggle.scrollIntoView(in: form)
    toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
    XCTAssertTrue(toggle.waitFor(NSPredicate(format: "value == '1'")), "switched on")
    app.buttons["savePlaylistButton"].tap()
    app.navigationBars.buttons["Playlists"].tapWhenReady()
}

extension XCUIElement {
    func tapWhenReady(timeout: TimeInterval = 5, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(waitForExistence(timeout: timeout), "\(self) not found", file: file, line: line)
        tap()
    }

    /// Swipes `container` (up by default) until the element is well inside the visible area,
    /// clear of the tab bar and the mini player: a row below the Up Next preview or a chip at
    /// the end of a filter bar.
    func scrollIntoView(in container: XCUIElement, left: Bool = false, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(waitForExistence(timeout: 5), "\(self) not found", file: file, line: line)
        let screen = XCUIApplication().windows.firstMatch.frame
        for _ in 0..<8 {
            if left ? frame.maxX < screen.maxX - 16 : frame.maxY < screen.height * 0.7 { return }
            if left { container.swipeLeft() } else { container.swipeUp() }
        }
    }
}

extension LibraryUITests {
    /// The layout menu: list rows open a podcast, and the choice goes back to tiles.
    @MainActor
    func testSwitchingLayoutAndOpeningAPodcast() {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let podcast = app.buttons["Methodisch inkorrekt"].firstMatch
        XCTAssertTrue(podcast.waitForExistence(timeout: 5), "tiles by default")

        app.buttons["libraryLayoutMenu"].tapWhenReady()
        app.buttons["List"].tapWhenReady()
        // A row's label also holds its tags and date.
        let row = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Methodisch inkorrekt")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(app.staticTexts["Methodisch inkorrekt 3"].waitForExistence(timeout: 5), "detail opens from a row")
        app.navigationBars.buttons.firstMatch.tap()

        app.buttons["libraryLayoutMenu"].tapWhenReady()
        app.buttons["Large Tiles"].tapWhenReady()
        XCTAssertTrue(podcast.waitForExistence(timeout: 5))
    }
}

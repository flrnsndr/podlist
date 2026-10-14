import XCTest

/// Settings → Notifications (N87): podcasts nested under their playlists, a playlist's switch
/// sets a podcast under every playlist it shows in and can be undone with the banner, the main
/// switch greys the list, hidden playlists wait behind "Mehr ›".
final class NotificationSettingsUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testGroupsUndoMainSwitchAndHiddenPlaylists() {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        hideEntertainment(in: app)
        app.tabBars.buttons["Library"].tapWhenReady()
        app.buttons["settingsButton"].tapWhenReady()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        let entry = app.buttons["notificationSettings"]
        for _ in 0..<4 where !entry.isHittable { app.swipeUp() }
        entry.tapWhenReady()
        XCTAssertTrue(app.navigationBars["Notifications"].waitForExistence(timeout: 5))

        // The sample podcasts start off; "Lage der Nation" is in News and Politics.
        let lage = app.switches.matching(identifier: "notifications.Lage der Nation")
        XCTAssertTrue(lage.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(lage.count, 2, "under News and Politics")
        XCTAssertFalse(app.switches["notifications.Hotel Matze"].exists, "Entertainment is hidden")

        let news = app.switches.matching(identifier: "notificationGroupToggle").firstMatch
        flip(news)
        XCTAssertTrue(lage.element(boundBy: 1).waitFor(NSPredicate(format: "value == '1'")), "on under Politics too")
        app.buttons["undoBannerButton"].tapWhenReady()
        XCTAssertTrue(lage.element(boundBy: 1).waitFor(NSPredicate(format: "value == '0'")), "undone")
        XCTAssertTrue(news.waitFor(NSPredicate(format: "value == '0'")))

        let main = app.switches["notificationsMainToggle"]
        flip(main)
        XCTAssertTrue(news.waitFor(NSPredicate(format: "isEnabled == false")), "greyed out")
        flip(main)
        XCTAssertTrue(news.waitFor(NSPredicate(format: "isEnabled == true")))

        let form = app.collectionViews.firstMatch
        let more = app.buttons["hiddenPlaylistsRow"]
        for _ in 0..<5 where !more.exists { form.swipeUp() }
        more.scrollIntoView(in: form)
        more.tap()
        let matze = app.switches["notifications.Hotel Matze"]
        for _ in 0..<5 where !matze.exists { form.swipeUp() }
        XCTAssertTrue(matze.waitForExistence(timeout: 5), "behind More")
    }

    /// Taps the switch itself, not its label.
    @MainActor
    private func flip(_ toggle: XCUIElement) {
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
    }
}

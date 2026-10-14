import XCTest

/// Slice 4 flows (concept §4.6, N25, A27, A28): speed and sleep timer in the player. Sample
/// data: "News" holds "Lage der Nation 1…3".
/// Audio never loads; the player keeps the episode.
final class PlayerUITests: XCTestCase {
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
    private func openPlayerWithNews(in app: XCUIApplication) {
        app.tabBars.buttons["Playlists"].tapWhenReady()
        app.staticTexts["News"].firstMatch.tapWhenReady()
        app.buttons["playPlaylistButton"].tapWhenReady()
        app.tabBars.buttons["Library"].tap()
        app.buttons["miniPlayer"].tapWhenReady()
    }

    @MainActor
    func testChangingTheSpeedAndSettingASleepTimer() {
        let app = launch()
        openPlayerWithNews(in: app)

        app.buttons["speedButton"].tapWhenReady()
        app.buttons["speedStepper-Increment"].tapWhenReady()
        app.navigationBars["Playback Speed"].buttons["Done"].tap()
        XCTAssertTrue(app.buttons["speedButton"].waitFor(NSPredicate(format: "label == %@", "Playback Speed: 1.1×")))

        app.buttons["sleepTimerButton"].tapWhenReady()
        app.buttons["sleepTimerEndOfEpisode"].tapWhenReady()
        XCTAssertTrue(app.buttons["sleepTimerButton"].waitFor(NSPredicate(format: "label == %@", "Sleep Timer: End of Episode")))
    }
}

/// Chapters (concept §4.6, A30, A31). Sample data: "Lage der Nation 1" has Podlove chapters
/// (Intro, Thema eins, Thema zwei); "Lage der Nation 2" has timestamps in its show notes.
final class ChapterUITests: XCTestCase {
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
    func testChaptersInThePlayer() {
        let app = launch()
        app.tabBars.buttons["Playlists"].tapWhenReady()
        app.staticTexts["News"].firstMatch.tapWhenReady()
        app.buttons["playPlaylistButton"].tapWhenReady()
        app.tabBars.buttons["Library"].tap()
        app.buttons["miniPlayer"].tapWhenReady()

        let title = app.staticTexts["currentChapterTitle"]
        XCTAssertTrue(title.waitFor(NSPredicate(format: "label == %@", "Chapter: Intro")))
        app.buttons["nextChapterButton"].tap()
        XCTAssertTrue(title.waitFor(NSPredicate(format: "label == %@", "Chapter: Thema eins")))

        app.buttons["chaptersButton"].tapWhenReady()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Thema zwei")).firstMatch.tapWhenReady()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(title.waitFor(NSPredicate(format: "label == %@", "Chapter: Thema zwei")))
    }

    @MainActor
    func testShowNotesTimestampsBecomeChaptersThatPlay() {
        let app = launch()
        app.buttons["Lage der Nation"].firstMatch.tapWhenReady()
        app.staticTexts["Lage der Nation 2"].tapWhenReady()
        let chapter = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Wahlrecht")).firstMatch
        chapter.tapWhenReady()
        app.buttons["Done"].tapWhenReady()
        XCTAssertTrue(app.buttons["miniPlayer"].waitFor(NSPredicate(format: "label == %@", "Lage der Nation 2")))
        XCTAssertTrue(app.buttons["miniPlayer"].waitFor(NSPredicate(format: "value == %@", "Wahlrecht")))
    }

    /// N80: below the player, its show notes. The sheet snaps between the two: a drag short of
    /// 30 % of the way springs back, a longer one snaps; a timestamp in the notes jumps there.
    @MainActor
    func testShowNotesBelowThePlayerSnap() {
        let app = launch()
        app.buttons["Lage der Nation"].firstMatch.tapWhenReady()
        app.staticTexts["Lage der Nation 2"].tapWhenReady()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Begrüßung")).firstMatch.tapWhenReady()
        app.buttons["Done"].tapWhenReady()
        app.buttons["miniPlayer"].tapWhenReady()

        let notes = app.staticTexts["showNotesTitle"]
        XCTAssertTrue(notes.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["upNextButton"].exists, "the queue is no longer in the player")
        let barBottom = app.navigationBars.firstMatch.frame.maxY
        let belowPlayer = restingTop(of: notes)
        XCTAssertGreaterThan(belowPlayer, app.windows.firstMatch.frame.height / 2, "the notes start below the player")

        drag(app, by: 80)
        XCTAssertEqual(restingTop(of: notes), belowPlayer, accuracy: 2, "a short drag springs back to the player")
        drag(app, by: 200)
        XCTAssertEqual(restingTop(of: notes), belowPlayer, accuracy: 2, "the player is sticky: a medium drag springs back too")
        drag(app, by: 320)
        XCTAssertEqual(restingTop(of: notes) - barBottom, 16, accuracy: 24, "the notes snap right below the bar")
        drag(app, by: -80)
        XCTAssertEqual(restingTop(of: notes) - barBottom, 16, accuracy: 24, "a short drag springs back to the notes")
        drag(app, by: -320)
        XCTAssertEqual(restingTop(of: notes), belowPlayer, accuracy: 2, "the player snaps back")

        app.buttons["showNotesHint"].tap()
        XCTAssertEqual(restingTop(of: notes) - barBottom, 16, accuracy: 24, "the hint scrolls to the notes")
        app.links["41:05"].tapWhenReady()
        XCTAssertTrue(app.staticTexts["currentChapterTitle"].waitFor(NSPredicate(format: "label == %@", "Chapter: Klimageld")))
    }

    /// Drags the player sheet slowly by `distance` points (up: towards the notes) and holds
    /// before letting go, so no momentum carries it.
    @MainActor
    private func drag(_ app: XCUIApplication, by distance: CGFloat) {
        let start = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: distance > 0 ? 0.6 : 0.3))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -distance)),
                    withVelocity: 200, thenHoldForDuration: 0.3)
    }

    /// The element's top once scrolling has come to rest.
    @MainActor
    private func restingTop(of element: XCUIElement) -> CGFloat {
        var last = element.frame.minY
        for _ in 0..<20 {
            Thread.sleep(forTimeInterval: 0.25)
            let now = element.frame.minY
            if abs(now - last) < 0.5 { return now }
            last = now
        }
        return last
    }
}

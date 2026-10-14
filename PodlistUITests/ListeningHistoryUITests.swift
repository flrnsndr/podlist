import XCTest

/// Slice 9 (concept §4.12): Settings → Listening History shows started episodes of the sample
/// data with "A Year Ago" on top, filters to unfinished ones, searches the short description
/// and links to the month's statistics and back.
final class ListeningHistoryUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testStartedEpisodesFilterAndSearch() {
        let app = openHistory()
        XCTAssertTrue(app.staticTexts["historyYearAgo"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Hotel Matze 1"].exists, "a year ago")
        XCTAssertTrue(app.staticTexts["Methodisch inkorrekt 1"].exists, "started today")
        let yesterday = app.staticTexts["Lage der Nation 1"]
        for _ in 0..<3 where !yesterday.exists { app.swipeUp() }
        XCTAssertTrue(yesterday.exists, "heard yesterday")

        // "Not Finished": only started, unplayed episodes; no "A Year Ago".
        app.buttons["historyFilterMenu"].tapWhenReady()
        app.buttons["Not Finished Only"].tapWhenReady()
        XCTAssertTrue(app.staticTexts["Methodisch inkorrekt 1"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Lage der Nation 1"].exists)
        XCTAssertFalse(app.staticTexts["historyYearAgo"].exists)
        app.buttons["historyFilterMenu"].tapWhenReady()
        app.buttons["Not Finished Only"].tapWhenReady()

        // The short description is searchable (N83).
        let search = app.searchFields.firstMatch
        search.tapWhenReady()
        search.typeText("himmel blau")
        XCTAssertTrue(app.staticTexts["Methodisch inkorrekt 1"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Hotel Matze 1"].exists)
        XCTAssertFalse(app.staticTexts["Lage der Nation 1"].exists)
    }

    /// A76: a month of the history links to its statistics; from an older month there the
    /// history opens at that month.
    @MainActor
    func testStatisticsOfAnOlderMonthJumpToItInTheHistory() {
        let app = openHistory()
        app.buttons["historyMonthStats"].firstMatch.tapWhenReady(timeout: 10)
        XCTAssertTrue(app.staticTexts["statsPeriod"].waitForExistence(timeout: 10))
        for _ in 0..<3 { app.buttons["statsPrevious"].tapWhenReady() }
        let month = Calendar.current.date(byAdding: .month, value: -3, to: Date())!
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        let title = formatter.string(from: month)
        XCTAssertTrue(app.staticTexts["statsPeriod"].waitFor(NSPredicate(format: "label == %@", title)))

        let link = app.buttons["statsHistory"]
        for _ in 0..<30 where !link.isHittable { app.swipeUp() }
        link.tapWhenReady()
        let heading = app.staticTexts[title]
        XCTAssertTrue(heading.waitForExistence(timeout: 10))
        XCTAssertTrue(heading.isHittable, "scrolled to the month")
    }

    @MainActor
    private func openHistory() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        app.buttons["settingsButton"].tapWhenReady()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        let entry = app.buttons["listeningHistory"]
        for _ in 0..<4 where !entry.isHittable { app.swipeUp() }
        entry.tapWhenReady()
        XCTAssertTrue(app.navigationBars["Listening History"].waitForExistence(timeout: 10))
        return app
    }
}

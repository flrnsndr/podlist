import XCTest

/// Slice 8 (concept §4.11, plan-hoerstatistik §9): Settings → Listening Stats shows the
/// sample listening log, switches between month and year, pages back and opens the share
/// preview.
final class ListeningStatsUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testMonthYearPagingAndSharing() {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        app.buttons["settingsButton"].tapWhenReady()
        // The last section of Settings (N62).
        let entry = app.buttons["listeningStats"]
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        for _ in 0..<4 where !entry.isHittable { app.swipeUp() }
        entry.tapWhenReady()

        let period = app.staticTexts["statsPeriod"]
        XCTAssertTrue(period.waitForExistence(timeout: 10))
        XCTAssertEqual(period.label, Self.title(of: Date(), format: "MMMM yyyy"))
        let total = app.descendants(matching: .any)["statsTotal"]
        XCTAssertTrue(total.waitForExistence(timeout: 5), "the sample data fills the month")
        XCTAssertFalse(app.buttons["statsNext"].isEnabled, "the current month is the newest")

        app.buttons["statsPrevious"].tap()
        let lastMonth = Calendar.current.date(byAdding: .month, value: -1, to: Date())!
        XCTAssertTrue(period.waitFor(NSPredicate(format: "label == %@", Self.title(of: lastMonth, format: "MMMM yyyy"))))
        XCTAssertTrue(total.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["statsNext"].isEnabled)

        app.segmentedControls["statsKind"].buttons["Year"].tap()
        XCTAssertTrue(period.waitFor(NSPredicate(format: "label == %@", Self.title(of: lastMonth, format: "yyyy"))))
        XCTAssertTrue(total.waitForExistence(timeout: 5))

        app.buttons["statsShare"].tap()
        XCTAssertTrue(app.images["statsShareCard"].waitForExistence(timeout: 10), "the card is rendered")
        XCTAssertTrue(app.buttons["Share Image"].exists)
    }

    private static func title(of date: Date, format: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.setLocalizedDateFormatFromTemplate(format)
        return formatter.string(from: date)
    }
}

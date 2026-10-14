import XCTest

/// The inbox tab (concept §4.10) with the sample data: open "Lage der Nation 4" and
/// "Zeit Verbrechen 1"; done "Lage der Nation 3", "Hotel Matze 3", "Methodisch inkorrekt 3"
/// (auto-added, so not shown, N74).
final class InboxUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func launchInbox() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        app.tabBars.buttons["Inbox"].tapWhenReady()
        XCTAssertTrue(app.navigationBars["Inbox"].waitForExistence(timeout: 5))
        return app
    }

    @MainActor
    private func row(_ app: XCUIApplication, _ title: String) -> XCUIElement {
        app.buttons.matching(identifier: "inboxRow").matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
    }

    @MainActor
    private func doneRow(_ app: XCUIApplication, _ title: String) -> XCUIElement {
        app.buttons.matching(identifier: "inboxDoneRow").matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
    }

    private let gone = NSPredicate(format: "exists == false")

    /// N74: only open episodes show, with their actions. An added episode leaves them and
    /// waits below under "Just Done"; undo brings it back.
    @MainActor
    func testAddedEpisodeMovesToJustDone() {
        let app = launchInbox()
        XCTAssertTrue(row(app, "Lage der Nation 4").waitForExistence(timeout: 5))
        XCTAssertTrue(row(app, "Zeit Verbrechen 1").exists)
        XCTAssertFalse(row(app, "Hotel Matze 3").exists, "done episodes leave the inbox (N74)")
        XCTAssertFalse(app.buttons["inboxDoneRow"].exists, "nothing done in this session yet")
        XCTAssertEqual(app.buttons.matching(identifier: "inboxAdd").count, 1, "only Lage der Nation 4 has playlists")
        XCTAssertTrue(app.buttons["inboxAdd"].label.contains("Add to News and Politics"), app.buttons["inboxAdd"].label)
        XCTAssertTrue(app.buttons["inboxDismissAll"].label.contains("Dismiss Rest (2)"), app.buttons["inboxDismissAll"].label)

        app.buttons["inboxAdd"].tapWhenReady()
        XCTAssertTrue(row(app, "Lage der Nation 4").waitFor(gone))
        let done = doneRow(app, "Lage der Nation 4")
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        XCTAssertTrue(done.label.contains("News"), done.label)
        XCTAssertFalse(app.buttons["inboxAddAll"].isEnabled, "nothing left to add")
        XCTAssertTrue(app.buttons["inboxDismissAll"].label.contains("(1)"), app.buttons["inboxDismissAll"].label)

        app.buttons["undoBannerButton"].tapWhenReady()
        XCTAssertTrue(row(app, "Lage der Nation 4").waitForExistence(timeout: 5))
        XCTAssertTrue(done.waitFor(gone))
    }

    /// N74, A67: the background empties "Just Done"; back in the app, what shows counts as
    /// seen again, so an episode done now goes there.
    @MainActor
    func testJustDoneEmptiesInTheBackground() {
        let app = launchInbox()
        app.buttons["inboxAdd"].tapWhenReady()
        let added = doneRow(app, "Lage der Nation 4")
        XCTAssertTrue(added.waitForExistence(timeout: 5))

        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(added.waitFor(gone))

        app.buttons["inboxMore"].firstMatch.tapWhenReady()
        app.buttons["inboxPlayNext"].tapWhenReady()
        XCTAssertTrue(row(app, "Zeit Verbrechen 1").waitFor(gone))
        XCTAssertTrue(doneRow(app, "Zeit Verbrechen 1").waitForExistence(timeout: 5))
    }
}

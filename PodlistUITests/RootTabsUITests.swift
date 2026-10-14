import XCTest

final class RootTabsUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// Library and inbox share one filter bar (concept §4.10 "Chips wie in der Bibliothek"):
    /// switching tabs must not move the chips by a single point, and an empty filter says so
    /// at the same place in both tabs, under the chips. Sample data: no podcast is in "Sports".
    @MainActor
    func testFilterBarAndEmptyFilterSitAtTheSamePlaceInLibraryAndInbox() {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        func frames(_ tab: String, prefix: String) -> (chips: [CGRect], emptyState: CGRect) {
            app.tabBars.buttons[tab].tapWhenReady()
            XCTAssertTrue(app.navigationBars[tab].waitForExistence(timeout: 5))
            let bar = app.scrollViews["\(prefix)FilterBar"]
            XCTAssertTrue(bar.waitForExistence(timeout: 5), "\(tab) has no filter bar")
            let chips = ["All", "News"].map { bar.buttons[$0].firstMatch.frame }
            bar.buttons["Sports"].firstMatch.tapWhenReady()
            let title = app.descendants(matching: .any)["\(prefix)EmptyState"].firstMatch
            XCTAssertTrue(title.waitForExistence(timeout: 5), "\(tab) shows no empty state")
            return (chips, title.frame)
        }

        let library = frames("Library", prefix: "library")
        let inbox = frames("Inbox", prefix: "inbox")
        XCTAssertEqual(library.chips, inbox.chips)
        XCTAssertEqual(library.emptyState.minY, inbox.emptyState.minY, accuracy: 0.5)
    }
}

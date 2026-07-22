import XCTest

@MainActor
final class LogicLyricsUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "-ApplePersistenceIgnoreState", "YES"]
        app.launch()
        app.activate()
        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertTrue(element("logic-lyrics-root").waitForExistence(timeout: 12))
    }

    override func tearDown() {
        app.terminate()
        app = nil
        super.tearDown()
    }

    func testHistoryNavigationSearchAndMigrationActions() {
        let plaid = element("history-row-11111111-1111-1111-1111-111111111111")
        let humanGeology = element("history-row-22222222-2222-2222-2222-222222222222")
        XCTAssertTrue(plaid.waitForExistence(timeout: 5))
        XCTAssertTrue(humanGeology.exists)

        plaid.click()
        XCTAssertTrue(element("history-detail").waitForExistence(timeout: 3))
        XCTAssertTrue(element("history-project-lyrics").exists)
        XCTAssertTrue(element("history-edited-lyrics").exists)

        let recovered = element("history-recovered-revisions")
        if recovered.exists { recovered.click() }
        let restore = element("history-restore-revision-0")
        XCTAssertTrue(restore.waitForExistence(timeout: 3))
        restore.click()
        XCTAssertTrue(element("history-revert-edit").waitForExistence(timeout: 3))
        element("history-revert-edit").click()
        XCTAssertTrue(element("history-edited-lyrics").waitForNonExistence(timeout: 3))

        let search = element("history-search-field")
        search.click()
        search.typeText("Human")
        XCTAssertTrue(humanGeology.waitForExistence(timeout: 3))
        XCTAssertFalse(plaid.exists)
        humanGeology.click()
        XCTAssertTrue(app.staticTexts["Human Geology"].waitForExistence(timeout: 3))

        attachScreenshot(named: "History-Migrated-State")
    }

    func testHistoryVoiceOverSemantics() throws {
        let plaid = element("history-row-11111111-1111-1111-1111-111111111111")
        XCTAssertTrue(plaid.waitForExistence(timeout: 5))
        plaid.click()
        XCTAssertTrue(element("history-open-project").waitForExistence(timeout: 3))
        XCTAssertFalse(element("history-open-project").label.isEmpty)
        XCTAssertFalse(element("history-locate-project").label.isEmpty)
        XCTAssertFalse(element("history-revert-edit").label.isEmpty)
        try app.performAccessibilityAudit(for: [.sufficientElementDescription, .elementDetection])
    }

    func testCompactAndLargeWindowLayouts() {
        app.terminate()
        app.launchArguments = [
            "--ui-testing", "--ui-test-compact-window",
            "-ApplePersistenceIgnoreState", "YES"
        ]
        app.launch()
        app.activate()
        let compactWindow = app.windows.firstMatch
        XCTAssertTrue(compactWindow.waitForExistence(timeout: 12))
        XCTAssertGreaterThanOrEqual(compactWindow.frame.width, 820)
        XCTAssertLessThan(compactWindow.frame.width, 1_100)
        XCTAssertTrue(element("recent-songs-section").exists)
        let compactWidth = compactWindow.frame.width
        attachScreenshot(named: "History-Compact-Window")

        app.terminate()
        app.launchArguments = [
            "--ui-testing", "--ui-test-large-window",
            "-ApplePersistenceIgnoreState", "YES"
        ]
        app.launch()
        app.activate()
        let largeWindow = app.windows.firstMatch
        XCTAssertTrue(largeWindow.waitForExistence(timeout: 12))
        XCTAssertGreaterThan(largeWindow.frame.width, compactWidth)
        XCTAssertTrue(element("recent-songs-section").exists)
        attachScreenshot(named: "History-Large-Window")
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

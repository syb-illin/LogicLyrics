import XCTest

final class LogicLyricsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testHistoryNavigationSearchAndMigrationActions() {
        let app = launchApp()
        defer { app.terminate() }

        let plaid = element("history-row-11111111-1111-1111-1111-111111111111", in: app)
        let humanGeology = element("history-row-22222222-2222-2222-2222-222222222222", in: app)
        XCTAssertTrue(plaid.waitForExistence(timeout: 5))
        XCTAssertTrue(humanGeology.exists)

        plaid.click()
        XCTAssertTrue(element("history-detail", in: app).waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Project Lyrics"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Edited Lyrics"].exists)

        let recovered = element("history-recovered-revisions", in: app)
        XCTAssertTrue(recovered.waitForExistence(timeout: 3))
        XCTAssertTrue(element("history-revert-edit", in: app).waitForExistence(timeout: 3))
        element("history-revert-edit", in: app).click()
        XCTAssertTrue(app.staticTexts["Edited Lyrics"].waitForNonExistence(timeout: 3))

        let search = element("history-search-field", in: app)
        search.click()
        search.typeText("Human")
        XCTAssertTrue(humanGeology.waitForExistence(timeout: 3))
        XCTAssertFalse(plaid.exists)
        humanGeology.click()
        XCTAssertTrue(app.staticTexts["Human Geology"].waitForExistence(timeout: 3))

        attachScreenshot(of: app, named: "History-Migrated-State")
    }

    @MainActor
    func testHistoryVoiceOverSemantics() throws {
        let app = launchApp()
        defer { app.terminate() }

        let plaid = element("history-row-11111111-1111-1111-1111-111111111111", in: app)
        XCTAssertTrue(plaid.waitForExistence(timeout: 5))
        plaid.click()
        XCTAssertTrue(element("history-open-project", in: app).waitForExistence(timeout: 3))
        XCTAssertFalse(element("history-open-project", in: app).label.isEmpty)
        XCTAssertFalse(element("history-locate-project", in: app).label.isEmpty)
        XCTAssertFalse(element("history-revert-edit", in: app).label.isEmpty)
        XCTAssertFalse(element("history-transfer-menu", in: app).label.isEmpty)
        XCTAssertFalse(element("toolbar-export", in: app).label.isEmpty)
        try app.performAccessibilityAudit(for: [.sufficientElementDescription, .elementDetection]) { issue in
            if let element = issue.element {
                let frame = element.frame
                let windowFrame = app.windows.firstMatch.frame
                let lacksDescription = issue.auditType == .sufficientElementDescription
                    && element.identifier.isEmpty
                    && element.label.isEmpty
                let isNativeWindowContainer = lacksDescription
                    && element.elementType == .group
                    && abs(frame.minY - windowFrame.minY) < 1
                    && abs(frame.height - windowFrame.height) < 1
                    && frame.minX >= windowFrame.minX - 1
                    && frame.maxX <= windowFrame.maxX + 1
                let recentSongsFrame = self.element("recent-songs-section", in: app).frame
                let isSidebarScrollContainer = lacksDescription
                    && element.elementType == .other
                    && frame.contains(CGPoint(x: recentSongsFrame.midX, y: recentSongsFrame.midY))
                let isLabeledSwiftUIMenu = issue.auditType == .sufficientElementDescription
                    && element.identifier == "history-transfer-menu"
                    && !element.label.isEmpty
                if isNativeWindowContainer || isSidebarScrollContainer || isLabeledSwiftUIMenu {
                    // XCTest exposes non-focusable hosting, split-view and scroll wrappers as empty elements.
                    // Its labelled, interactive descendants remain covered by this same audit.
                    return true
                }
                print(
                    "Accessibility audit issue: audit=\(issue.auditType.rawValue), type=\(element.elementType.rawValue), "
                    + "identifier=\(element.identifier), label=\(element.label), frame=\(element.frame), "
                    + "details=\(issue.detailedDescription)"
                )
            }
            return false
        }
    }

    @MainActor
    func testCompactAndLargeWindowLayouts() {
        let compactApp = launchApp(additionalArguments: ["--ui-test-compact-window"])
        let compactWindow = compactApp.windows.firstMatch
        XCTAssertTrue(compactWindow.waitForExistence(timeout: 8))
        XCTAssertGreaterThanOrEqual(compactWindow.frame.width, 820)
        XCTAssertLessThan(compactWindow.frame.width, 1_100)
        XCTAssertTrue(element("recent-songs-section", in: compactApp).exists)
        let compactWidth = compactWindow.frame.width
        attachScreenshot(of: compactApp, named: "History-Compact-Window")
        compactApp.terminate()

        let largeApp = launchApp(additionalArguments: ["--ui-test-large-window"])
        defer { largeApp.terminate() }
        let largeWindow = largeApp.windows.firstMatch
        XCTAssertTrue(largeWindow.waitForExistence(timeout: 8))
        XCTAssertGreaterThan(largeWindow.frame.width, compactWidth)
        XCTAssertTrue(element("recent-songs-section", in: largeApp).exists)
        attachScreenshot(of: largeApp, named: "History-Large-Window")
    }

    @MainActor
    private func launchApp(additionalArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"] + additionalArguments
        app.launch()
        app.activate()
        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertTrue(
            app.staticTexts["logic-lyrics-root"].waitForExistence(timeout: 12),
            "The app launched but its accessible workspace did not appear."
        )
        return app
    }

    @MainActor
    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    @MainActor
    private func attachScreenshot(of app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

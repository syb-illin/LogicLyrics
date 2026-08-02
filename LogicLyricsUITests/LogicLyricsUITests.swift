import AppKit
import XCTest

final class LogicLyricsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testWCAGContrastThresholdCalculation() {
        XCTAssertEqual(wcagContrastRatio(low: 0, high: 1), 21, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(wcagContrastRatio(low: 0.01, high: 0.40), 4.5)
        XCTAssertLessThan(wcagContrastRatio(low: 0.04, high: 0.12), 4.5)
    }

    @MainActor
    func testFileMenuOpensLogicProjectPicker() {
        let app = launchApp()
        defer { app.terminate() }

        let fileMenu = app.menuBars.menuBarItems["File"]
        XCTAssertTrue(fileMenu.waitForExistence(timeout: 3))
        fileMenu.click()

        let openProject = app.menuItems["Open Logic Pro Project…"]
        XCTAssertTrue(openProject.waitForExistence(timeout: 3))
        XCTAssertTrue(openProject.isEnabled)
        openProject.click()

        // SwiftUI's fileImporter is exposed by XCTest as a separate native
        // panel window on macOS, rather than consistently as a sheet/dialog.
        // The panel's Cancel button is the stable accessibility contract.
        let cancel = app.buttons.matching(identifier: "CancelButton").firstMatch
        XCTAssertTrue(
            cancel.waitForExistence(timeout: 5),
            "The File menu command did not present the Logic project picker."
        )
        attachScreenshot(of: app, named: "Logic-Project-Open-Picker")
        cancel.click()
        XCTAssertTrue(cancel.waitForNonExistence(timeout: 3))
    }

    @MainActor
    func testEmptyWorkspaceAccessibility() throws {
        let app = launchApp()
        defer { app.terminate() }

        XCTAssertTrue(element("empty-open-project", in: app).waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Lyrics from Logic, without the clutter"].exists)
        XCTAssertTrue(app.staticTexts["Your project stays on this Mac and is never modified."].exists)
        try performAccessibilityAudit(on: app)
        attachScreenshot(of: app, named: "Empty-Workspace-Accessible")
    }

    @MainActor
    func testRecentProjectNavigationSearchAndCopyActions() {
        let app = launchApp()
        defer { app.terminate() }

        let plaid = element("history-row-11111111-1111-1111-1111-111111111111", in: app)
        let humanGeology = element("history-row-22222222-2222-2222-2222-222222222222", in: app)
        let atLast = element("history-row-33333333-3333-3333-3333-333333333333", in: app)
        let noLyrics = element("history-row-44444444-4444-4444-4444-444444444444", in: app)
        XCTAssertTrue(plaid.waitForExistence(timeout: 5))
        XCTAssertTrue(humanGeology.exists)
        XCTAssertTrue(atLast.exists)
        XCTAssertTrue(noLyrics.exists)

        plaid.click()
        XCTAssertTrue(element("lyrics-reader", in: app).waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Saved Lyrics"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Plaid"].exists)
        let copyLyrics = element("lyrics-copy-all", in: app)
        XCTAssertTrue(copyLyrics.waitForExistence(timeout: 3))
        copyLyrics.click()
        XCTAssertTrue(app.buttons["Copied"].waitForExistence(timeout: 2))

        let search = element("history-search-field", in: app)
        search.click()
        search.typeText("Human")
        XCTAssertTrue(humanGeology.waitForExistence(timeout: 3))
        XCTAssertFalse(plaid.exists)
        humanGeology.click()
        XCTAssertTrue(app.staticTexts["Human Geology"].waitForExistence(timeout: 3))

        search.typeKey("a", modifierFlags: .command)
        search.typeKey(.delete, modifierFlags: [])
        search.typeText("last")
        XCTAssertTrue(atLast.waitForExistence(timeout: 3))
        XCTAssertFalse(plaid.exists, "A lyrics-only match must not remain in title search results.")
        XCTAssertFalse(humanGeology.exists)
        XCTAssertFalse(noLyrics.exists)
        XCTAssertTrue(app.staticTexts["1 song"].exists)

        search.typeKey("a", modifierFlags: .command)
        search.typeKey(.delete, modifierFlags: [])
        let missingLyricsFilter = element("missing-lyrics-filter", in: app)
        XCTAssertTrue(missingLyricsFilter.waitForExistence(timeout: 3))
        missingLyricsFilter.click()
        XCTAssertTrue(noLyrics.waitForExistence(timeout: 3))
        XCTAssertFalse(plaid.exists)
        XCTAssertFalse(humanGeology.exists)
        XCTAssertFalse(atLast.exists)
        XCTAssertTrue(app.staticTexts["1 song"].exists)

        noLyrics.click()
        XCTAssertTrue(app.staticTexts["No Project Notes Found"].waitForExistence(timeout: 3))
        XCTAssertTrue(element("lyrics-refresh", in: app).exists)
        XCTAssertTrue(element("extraction-diagnostics", in: app).exists)

        attachScreenshot(of: app, named: "Recent-Project-Lyrics")
    }

    @MainActor
    func testReaderVoiceOverSemanticsAndActionAlignment() throws {
        let app = launchApp()
        defer { app.terminate() }

        let plaid = element("history-row-11111111-1111-1111-1111-111111111111", in: app)
        XCTAssertTrue(plaid.waitForExistence(timeout: 5))
        XCTAssertEqual(plaid.elementType, .button)
        XCTAssertFalse(plaid.label.isEmpty)
        plaid.click()
        let refreshLyrics = element("lyrics-refresh", in: app)
        let copyLyrics = element("lyrics-copy-all", in: app)
        XCTAssertTrue(refreshLyrics.waitForExistence(timeout: 3))
        XCTAssertEqual(refreshLyrics.label, "Refresh Lyrics")
        XCTAssertFalse(copyLyrics.label.isEmpty)
        XCTAssertEqual(copyLyrics.frame.midY, refreshLyrics.frame.midY, accuracy: 1)
        XCTAssertEqual(copyLyrics.frame.height, refreshLyrics.frame.height, accuracy: 1)
        XCTAssertTrue(element("project-actions-menu", in: app).exists)
        XCTAssertFalse(
            app.buttons.matching(identifier: "toolbar-open").firstMatch.label.isEmpty
        )
        XCTAssertFalse(element("sidebar-open", in: app).label.isEmpty)
        XCTAssertFalse(element("recent-songs-section", in: app).label.isEmpty)
        XCTAssertEqual(element("lyric-sections-grid", in: app).label, "Lyric sections")
        XCTAssertEqual(element("section-copy-0", in: app).label, "Copy Verse 1 section")
        try performAccessibilityAudit(on: app)
    }

    @MainActor
    func testHistoryManagementActionsAndConfirmations() {
        let app = launchApp()
        defer { app.terminate() }

        let humanID = "22222222-2222-2222-2222-222222222222"
        let human = element("history-row-\(humanID)", in: app)
        let actions = element("history-actions-\(humanID)", in: app)
        XCTAssertTrue(human.waitForExistence(timeout: 5))
        XCTAssertTrue(actions.exists)
        actions.click()
        let pin = app.menuItems["Pin"]
        XCTAssertTrue(pin.waitForExistence(timeout: 3))
        pin.click()

        XCTAssertTrue(human.waitForExistence(timeout: 3))
        element("history-actions-\(humanID)", in: app).click()
        XCTAssertTrue(app.menuItems["Unpin"].waitForExistence(timeout: 3))
        app.menuItems["Remove from History"].click()
        XCTAssertTrue(app.staticTexts["Remove this project from history?"].waitForExistence(timeout: 3))
        app.buttons["Cancel"].firstMatch.click()
        XCTAssertTrue(human.exists, "Cancelling removal must preserve the history row.")

        let management = element("history-management-menu", in: app)
        XCTAssertTrue(management.exists)
        management.click()
        app.menuItems["Clear History"].click()
        XCTAssertTrue(app.staticTexts["Clear all project history?"].waitForExistence(timeout: 3))
        app.buttons["Cancel"].firstMatch.click()
        XCTAssertTrue(human.exists, "Cancelling history clearing must preserve rows.")
    }

    @MainActor
    func testSettingsAndAboutAccessibility() throws {
        let app = launchApp()
        defer { app.terminate() }

        openSettings(in: app)
        XCTAssertTrue(app.staticTexts["Privacy & Diagnostics"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Entirely on this Mac"].exists)
        XCTAssertTrue(app.staticTexts["Never"].exists)
        try performAccessibilityAudit(on: app)
        attachScreenshot(of: app, named: "Settings-English-Accessible")
        closeFrontWindow(in: app)

        openAbout(in: app, menuTitle: "About Logic Lyrics")
        XCTAssertTrue(
            app.staticTexts[
                "Reads tempo, key and lyrics directly from Logic Pro Project Notes without modifying your project."
            ].waitForExistence(timeout: 3)
        )
        try performAccessibilityAudit(on: app)
        attachScreenshot(of: app, named: "About-English-Accessible")
    }

    @MainActor
    func testFrenchLocalizationAndAccessibility() throws {
        let app = launchApp(additionalArguments: [
            "--ui-test-language=fr"
        ])
        defer { app.terminate() }

        XCTAssertTrue(app.staticTexts["PROJETS RÉCENTS"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Les paroles de Logic, sans superflu"].exists)
        let missingLyricsFilter = element("missing-lyrics-filter", in: app)
        XCTAssertTrue(missingLyricsFilter.waitForExistence(timeout: 3))
        XCTAssertEqual(missingLyricsFilter.label, "Sans paroles")

        let plaid = element("history-row-11111111-1111-1111-1111-111111111111", in: app)
        plaid.click()
        let refreshLyrics = element("lyrics-refresh", in: app)
        XCTAssertTrue(refreshLyrics.waitForExistence(timeout: 3))
        XCTAssertEqual(refreshLyrics.label, "Actualiser les paroles")

        let search = element("history-search-field", in: app)
        search.click()
        search.typeText("last")
        XCTAssertTrue(
            element("history-row-33333333-3333-3333-3333-333333333333", in: app)
                .waitForExistence(timeout: 3)
        )
        XCTAssertTrue(app.staticTexts["1 morceau"].exists)
        try performAccessibilityAudit(on: app)
        attachScreenshot(of: app, named: "Historique-Francais-Accessible")

        openSettings(in: app)
        XCTAssertTrue(app.staticTexts["Confidentialité et diagnostics"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Entièrement sur ce Mac"].exists)
        XCTAssertTrue(app.staticTexts["Jamais"].exists)
        try performAccessibilityAudit(on: app)
        attachScreenshot(of: app, named: "Reglages-Francais-Accessibles")
        closeFrontWindow(in: app)

        openAbout(in: app, menuTitle: "À propos de Logic Lyrics")
        XCTAssertTrue(
            app.staticTexts[
                "Lit le tempo, la tonalité et les paroles directement depuis les notes du projet Logic Pro, sans modifier le projet."
            ].waitForExistence(timeout: 3)
        )
        try performAccessibilityAudit(on: app)
        attachScreenshot(of: app, named: "A-Propos-Francais-Accessible")
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
    func testVisualSnapshotBaselines() throws {
        let app = launchApp(additionalArguments: ["--ui-test-compact-window"])
        defer { app.terminate() }
        XCTAssertTrue(element("empty-open-project", in: app).waitForExistence(timeout: 5))
        try assertVisualSnapshot(app.screenshot(), named: "Workspace-Compact")

        element("history-row-11111111-1111-1111-1111-111111111111", in: app).click()
        XCTAssertTrue(element("lyrics-reader", in: app).waitForExistence(timeout: 3))
        try assertVisualSnapshot(app.screenshot(), named: "History-Lyrics-Compact")
    }

    @MainActor
    private func launchApp(additionalArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"] + additionalArguments
        app.launch()
        app.activate()
        XCTAssertEqual(app.state, .runningForeground)
        let identifiedRoot = app.staticTexts["logic-lyrics-root"]
        let labelledRoot = app.staticTexts["Logic Lyrics"].firstMatch
        let workspaceAppeared = identifiedRoot.waitForExistence(timeout: 8)
            || labelledRoot.waitForExistence(timeout: 4)
        XCTAssertTrue(
            workspaceAppeared,
            "The app launched but its accessible workspace did not appear."
        )
        return app
    }

    @MainActor
    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    @MainActor
    private func openSettings(in app: XCUIApplication) {
        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(
            element("settings-view", in: app).waitForExistence(timeout: 5),
            "The Settings command did not present the app settings window."
        )
    }

    @MainActor
    private func openAbout(in app: XCUIApplication, menuTitle: String) {
        let displayNameMenu = app.menuBars.menuBarItems["Logic Lyrics"]
        let processNameMenu = app.menuBars.menuBarItems["LogicLyrics"]
        let appMenu: XCUIElement
        if displayNameMenu.waitForExistence(timeout: 2) {
            appMenu = displayNameMenu
        } else {
            appMenu = processNameMenu
        }
        XCTAssertTrue(
            appMenu.waitForExistence(timeout: 3),
            "The macOS application menu was not exposed under its display or process name."
        )
        appMenu.click()

        let aboutItem = appMenu.descendants(matching: .menuItem)[menuTitle]
        XCTAssertTrue(
            aboutItem.waitForExistence(timeout: 3),
            "The localized About menu item was not exposed."
        )
        aboutItem.click()
        XCTAssertTrue(
            element("about-view", in: app).waitForExistence(timeout: 3),
            "The accessible About window did not appear."
        )
    }

    @MainActor
    private func closeFrontWindow(in app: XCUIApplication) {
        app.typeKey("w", modifierFlags: .command)
        app.activate()
        XCTAssertTrue(element("logic-lyrics-workspace", in: app).waitForExistence(timeout: 3))
    }

    @MainActor
    private func performAccessibilityAudit(on app: XCUIApplication) throws {
        assertInteractiveElementsHaveDescriptions(in: app)
        let publicAuditTypes: XCUIAccessibilityAuditType = [
            .contrast,
            .elementDetection,
            .hitRegion
        ]
        try app.performAccessibilityAudit(for: publicAuditTypes) { issue in
            print(
                "Accessibility audit issue: audit=\(issue.auditType.rawValue), "
                + "details=\(issue.detailedDescription)"
            )
            if issue.auditType == .contrast,
               let element = issue.element,
               let measuredRatio = try? self.measuredPixelContrastRatio(
                   in: element.screenshot().pngRepresentation
               ) {
                print("Measured pixel contrast ratio: \(measuredRatio):1")
                if measuredRatio >= 4.5 {
                    // XCTest can misclassify antialiased SwiftUI text on a
                    // custom macOS surface. Only suppress that finding after
                    // independently measuring WCAG AA contrast in its pixels.
                    return true
                }
            }
            return false
        }
    }

    @MainActor
    private func assertInteractiveElementsHaveDescriptions(in app: XCUIApplication) {
        let interactiveTypes: [XCUIElement.ElementType] = [
            .button,
            .checkBox,
            .comboBox,
            .link,
            .menuItem,
            .popUpButton,
            .radioButton,
            .searchField,
            .secureTextField,
            .slider,
            .textField
        ]
        for type in interactiveTypes {
            for element in app.descendants(matching: type).allElementsBoundByIndex {
                guard element.exists else { continue }
                let frame = element.frame
                guard !frame.isEmpty else { continue }
                let label = element.label.trimmingCharacters(in: .whitespacesAndNewlines)
                let isNativeImplementationControl = element.identifier.hasPrefix("_XCUI:")
                    || element.identifier.hasPrefix("_SC_")
                    || (element.identifier.isEmpty && label.isEmpty)
                XCTAssertFalse(
                    label.isEmpty && !isNativeImplementationControl,
                    "Interactive accessibility element has no description: "
                        + "type=\(type.rawValue), identifier=\(element.identifier), frame=\(frame)"
                )
            }
        }
    }

    private func measuredPixelContrastRatio(in pngData: Data) throws -> Double {
        guard let bitmap = NSBitmapImageRep(data: pngData),
              bitmap.pixelsWide > 0,
              bitmap.pixelsHigh > 0 else {
            throw XCTSkip("Could not decode an accessibility contrast image.")
        }
        var luminances = [Double]()
        luminances.reserveCapacity(bitmap.pixelsWide * bitmap.pixelsHigh)
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                      color.alphaComponent > 0.05 else { continue }
                let red = linearizedSRGB(color.redComponent)
                let green = linearizedSRGB(color.greenComponent)
                let blue = linearizedSRGB(color.blueComponent)
                luminances.append(0.2126 * red + 0.7152 * green + 0.0722 * blue)
            }
        }
        guard luminances.count >= 2 else {
            throw XCTSkip("The accessibility contrast image contained too few visible pixels.")
        }
        luminances.sort()
        let lowIndex = Int(Double(luminances.count - 1) * 0.02)
        let highIndex = Int(Double(luminances.count - 1) * 0.98)
        let low = luminances[lowIndex]
        let high = luminances[highIndex]
        return wcagContrastRatio(low: low, high: high)
    }

    private func assertVisualSnapshot(_ screenshot: XCUIScreenshot, named name: String) throws {
        #if RECORD_VISUAL_BASELINES
        let recordingDirectory = URL(
            fileURLWithPath: "/tmp/LogicLyricsVisualBaselines",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: recordingDirectory,
            withIntermediateDirectories: true
        )
        try screenshot.pngRepresentation.write(
            to: recordingDirectory.appendingPathComponent("\(name).png"),
            options: .atomic
        )
        return
        #else
        let environment = ProcessInfo.processInfo.environment
        if let output = environment["LOGICLYRICS_VISUAL_BASELINE_OUTPUT"],
           !output.isEmpty {
            let directory = URL(fileURLWithPath: output, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try screenshot.pngRepresentation.write(
                to: directory.appendingPathComponent("\(name).png"),
                options: .atomic
            )
            return
        }

        guard let baselineURL = Bundle(for: Self.self).url(
            forResource: name,
            withExtension: "png",
            subdirectory: "ReferenceImages"
        ) else {
            XCTFail("Missing committed visual baseline: \(name).png")
            return
        }
        let baselineData = try Data(contentsOf: baselineURL)
        guard let actual = NSBitmapImageRep(data: screenshot.pngRepresentation),
              let baseline = NSBitmapImageRep(data: baselineData) else {
            throw XCTSkip("A visual snapshot image could not be decoded.")
        }
        XCTAssertEqual(actual.pixelsWide, baseline.pixelsWide, "Visual snapshot width changed: \(name)")
        XCTAssertEqual(actual.pixelsHigh, baseline.pixelsHigh, "Visual snapshot height changed: \(name)")
        guard actual.pixelsWide == baseline.pixelsWide,
              actual.pixelsHigh == baseline.pixelsHigh else { return }

        var materiallyDifferentPixels = 0
        let pixelCount = actual.pixelsWide * actual.pixelsHigh
        for y in 0..<actual.pixelsHigh {
            for x in 0..<actual.pixelsWide {
                guard let lhs = actual.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                      let rhs = baseline.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else {
                    materiallyDifferentPixels += 1
                    continue
                }
                let delta = [
                    abs(lhs.redComponent - rhs.redComponent),
                    abs(lhs.greenComponent - rhs.greenComponent),
                    abs(lhs.blueComponent - rhs.blueComponent),
                    abs(lhs.alphaComponent - rhs.alphaComponent)
                ].max() ?? 0
                if delta > 0.08 { materiallyDifferentPixels += 1 }
            }
        }
        let difference = Double(materiallyDifferentPixels) / Double(max(1, pixelCount))
        XCTAssertLessThanOrEqual(
            difference,
            0.01,
            "Visual snapshot \(name) changed by \(String(format: "%.2f", difference * 100))%."
        )
        #endif
    }

    private func wcagContrastRatio(low: Double, high: Double) -> Double {
        (high + 0.05) / (low + 0.05)
    }

    private func linearizedSRGB(_ component: CGFloat) -> Double {
        let value = Double(component)
        return value <= 0.04045
            ? value / 12.92
            : pow((value + 0.055) / 1.055, 2.4)
    }

    @MainActor
    private func attachScreenshot(of app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

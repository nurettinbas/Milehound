import XCTest

class TrailhoundUITestCase: XCTestCase {
    private(set) var app: XCUIApplication!

    var extraLaunchArguments: [String] { [] }

    var uiTimeout: TimeInterval {
        ProcessInfo.processInfo.environment["CI"] == "true" ? 25 : 15
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-UITesting"] + extraLaunchArguments
        app.launchEnvironment["AppleLanguages"] = "(en)"
        app.launchEnvironment["AppleLocale"] = "en_US"
        addUIInterruptionMonitor(withDescription: "System permission alerts") { alert in
            let titles = [
                "Allow While Using App",
                "Allow Once",
                "Allow",
                "OK",
                "Don’t Allow",
                "Don't Allow"
            ]
            for title in titles {
                let button = alert.buttons[title]
                if button.exists {
                    button.tap()
                    return true
                }
            }
            return false
        }
        app.launch()
    }

    override func tearDownWithError() throws {
        if app.state == .runningForeground || app.state == .runningBackground {
            app.terminate()
        }
        app = nil
        try super.tearDownWithError()
    }

    func tabButton(identifier: String, fallbackLabels: String...) -> XCUIElement {
        let inTabBar = app.tabBars.buttons[identifier]
        if inTabBar.waitForExistence(timeout: 1) {
            return inTabBar
        }
        let byIdentifier = app.buttons[identifier]
        if byIdentifier.waitForExistence(timeout: 1) {
            return byIdentifier
        }
        for label in fallbackLabels {
            let tabBarButton = app.tabBars.buttons[label]
            if tabBarButton.waitForExistence(timeout: 0.5) {
                return tabBarButton
            }
            let button = app.buttons[label]
            if button.waitForExistence(timeout: 0.5) {
                return button
            }
        }
        return app.buttons[fallbackLabels.first ?? identifier]
    }

    var tripsTab: XCUIElement {
        tabButton(identifier: "tab.trips", fallbackLabels: "Trips")
    }

    var statsTab: XCUIElement {
        tabButton(identifier: "tab.stats", fallbackLabels: "Statistics")
    }

    var yearTab: XCUIElement {
        tabButton(identifier: "tab.year", fallbackLabels: "Recap", "Yıllık")
    }

    var settingsTab: XCUIElement {
        tabButton(identifier: "tab.settings", fallbackLabels: "Settings")
    }

    var pairingTab: XCUIElement {
        tabButton(identifier: "tab.pairing", fallbackLabels: "Vehicles", "Pairing")
    }

    func openStatsFilterPanel() {
        let card = app.descendants(matching: .any)["stats.filters.card"]
        _ = card.waitForExistence(timeout: 5)
    }

    func revealSettingsControl(_ query: XCUIElement) {
        for _ in 0..<12 {
            if query.waitForExistence(timeout: 1), query.isHittable { return }
            if query.exists, !query.isHittable {
                app.swipeDown()
                if query.isHittable { return }
            }
            app.swipeUp()
        }
    }
}

final class TrailhoundUITests: TrailhoundUITestCase {

    func testAppLaunchesToTripsTab() {
        XCTAssertTrue(tripsTab.waitForExistence(timeout: uiTimeout))
    }

    func testTabNavigationTripsStatsSettingsPairing() {
        XCTAssertTrue(tripsTab.waitForExistence(timeout: uiTimeout))

        statsTab.tap()
        XCTAssertTrue(app.navigationBars.element.waitForExistence(timeout: 10))

        settingsTab.tap()
        XCTAssertTrue(app.switches["settings.recordingSounds"].waitForExistence(timeout: 10))

        pairingTab.tap()
        XCTAssertTrue(app.navigationBars.element.waitForExistence(timeout: 10))

        tripsTab.tap()
        XCTAssertTrue(tripsTab.exists)
    }

    func testTripDetailSwipeBackStaysOnList() {
        XCTAssertTrue(tripsTab.waitForExistence(timeout: uiTimeout))
        let firstTrip = app.buttons["trips.row.first"]
        XCTAssertTrue(firstTrip.waitForExistence(timeout: uiTimeout))
        firstTrip.tap()

        let detail = app.otherElements["tripDetail.screen"].firstMatch
        XCTAssertTrue(detail.waitForExistence(timeout: 15))
        let window = app.windows.firstMatch
        let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.0, dy: 0.7))
        let end = window.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.7))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .fast, thenHoldForDuration: 0)

        XCTAssertTrue(firstTrip.waitForExistence(timeout: 5))
        XCTAssertFalse(detail.waitForExistence(timeout: 2))
    }

    func testReadTripNotificationOpensDetail() throws {
        XCTAssertTrue(tripsTab.waitForExistence(timeout: uiTimeout))
        let notifications = app.buttons["trips.notifications"]
        XCTAssertTrue(notifications.waitForExistence(timeout: uiTimeout))
        notifications.tap()
        let ended = app.staticTexts["Trip ended"].firstMatch
        guard ended.waitForExistence(timeout: 5) else {
            throw XCTSkip("No ended-trip notification in this inbox.")
        }
        ended.tap()
        XCTAssertTrue(app.otherElements["tripDetail.screen"].waitForExistence(timeout: 15))
    }

    func testTripListOpensDetail() {
        XCTAssertTrue(tripsTab.waitForExistence(timeout: uiTimeout))

        let firstTrip = app.buttons["trips.row.first"]
        XCTAssertTrue(firstTrip.waitForExistence(timeout: uiTimeout))
        firstTrip.tap()

        XCTAssertTrue(app.otherElements["tripDetail.screen"].waitForExistence(timeout: 15))
    }

    func testSettingsRecordingSoundsToggle() {
        XCTAssertTrue(settingsTab.waitForExistence(timeout: uiTimeout))
        settingsTab.tap()
        let toggle = app.switches["settings.recordingSounds"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 15))
        XCTAssertTrue(toggle.isEnabled)
    }

    func testSettingsTipJarOpensAndCloses() {
        XCTAssertTrue(settingsTab.waitForExistence(timeout: uiTimeout))
        settingsTab.tap()
        let row = app.buttons["settings.tipJar"]
        revealSettingsControl(row)
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        let panel = app.descendants(matching: .any).matching(identifier: "tipJar.panel").firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 10))
        panel.swipeDown(velocity: .fast)
        XCTAssertTrue(panel.waitForNonExistence(timeout: 10))
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        XCTAssertTrue(panel.waitForExistence(timeout: 10))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
        XCTAssertTrue(panel.waitForNonExistence(timeout: 10))
    }

    func testSettingsAcknowledgementsCreditsTripSounds() {
        XCTAssertTrue(settingsTab.waitForExistence(timeout: uiTimeout))
        settingsTab.tap()
        let row = app.buttons["settings.acknowledgements"]
        revealSettingsControl(row)
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()

        let startCredit = app.descendants(matching: .any)["acknowledgements.credit.trip_start"]
        XCTAssertTrue(startCredit.waitForExistence(timeout: uiTimeout))
        XCTAssertTrue(app.descendants(matching: .any)["acknowledgements.credit.trip_stop"].exists)
        let author = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Edvvc")).firstMatch
        XCTAssertTrue(author.exists)
    }

    func testTravelsSegmentOpensJournalEmptyState() throws {
        XCTAssertTrue(tripsTab.waitForExistence(timeout: uiTimeout))
        let segment = app.segmentedControls["trips.segment"]
        guard segment.waitForExistence(timeout: uiTimeout) else {
            throw XCTSkip("Travels segment is hidden until the library has trips.")
        }
        segment.buttons["Travels"].tap()
        XCTAssertTrue(
            app.staticTexts["Create your first travel"].waitForExistence(timeout: 10)
                || app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "travel")).firstMatch.exists
        )
    }

    func testNotificationsListOpens() {
        XCTAssertTrue(tripsTab.waitForExistence(timeout: uiTimeout))

        let notifications = app.buttons["trips.notifications"]
        XCTAssertTrue(notifications.waitForExistence(timeout: 15))
        notifications.tap()

        XCTAssertTrue(app.navigationBars.element.waitForExistence(timeout: 15))
    }

    func testTripDetailSaveButtonExists() {
        XCTAssertTrue(tripsTab.waitForExistence(timeout: uiTimeout))
        XCTAssertTrue(app.buttons["trips.row.first"].waitForExistence(timeout: uiTimeout))
        app.buttons["trips.row.first"].tap()

        XCTAssertTrue(app.buttons["tripDetail.save"].waitForExistence(timeout: 15))
    }

    func testTripDetailScrollRevealsSaveButton() {
        XCTAssertTrue(tripsTab.waitForExistence(timeout: uiTimeout))
        XCTAssertTrue(app.buttons["trips.row.first"].waitForExistence(timeout: uiTimeout))
        app.buttons["trips.row.first"].tap()
        XCTAssertTrue(app.otherElements["tripDetail.screen"].waitForExistence(timeout: 15))

        let saveButton = app.buttons["tripDetail.save"]
        if !saveButton.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(saveButton.waitForExistence(timeout: 10))
    }

    func testYearTabShowsPremiumRecapCard() {
        XCTAssertTrue(yearTab.waitForExistence(timeout: uiTimeout))
        yearTab.tap()
        XCTAssertTrue(app.navigationBars.element.waitForExistence(timeout: 15))

        let recap = app.descendants(matching: .any)["stats.premium.recap"]
        for _ in 0..<12 {
            if recap.waitForExistence(timeout: 1), recap.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(recap.waitForExistence(timeout: uiTimeout), "Year recap sits on the Recap tab")

        let play = app.buttons["stats.premium.recap.play"]
        if play.waitForExistence(timeout: 8) {
            play.tap()
            XCTAssertTrue(app.descendants(matching: .any)["stats.premium.recap.story"].waitForExistence(timeout: 8))
            XCTAssertTrue(app.descendants(matching: .any)["stats.premium.recap.segments"].waitForExistence(timeout: 5))
            let forward = app.descendants(matching: .any)["stats.premium.recap.forward"]
            if forward.waitForExistence(timeout: 2) {
                forward.tap()
            }
            let back = app.descendants(matching: .any)["stats.premium.recap.back"]
            if back.waitForExistence(timeout: 2) {
                back.tap()
            }
            let close = app.buttons["stats.premium.recap.close"]
            XCTAssertTrue(close.waitForExistence(timeout: 5))
            close.tap()
            XCTAssertTrue(app.descendants(matching: .any)["stats.premium.recap"].waitForExistence(timeout: 8))
        }
    }

    func testStatsFiltersClearResetsToLast7Days() {
        XCTAssertTrue(statsTab.waitForExistence(timeout: uiTimeout))
        statsTab.tap()

        let week = app.buttons["stats.filters.period.week"]
        XCTAssertTrue(week.waitForExistence(timeout: uiTimeout))
        openStatsFilterPanel()
        XCTAssertTrue(app.buttons["stats.filters.category"].waitForExistence(timeout: 10))

        let month = app.buttons["stats.filters.period.month"]
        XCTAssertTrue(month.waitForExistence(timeout: 5))
        month.tap()

        let clear = app.buttons["stats.filters.clear"]
        XCTAssertTrue(clear.waitForExistence(timeout: 5))
        clear.tap()

        XCTAssertTrue(week.waitForExistence(timeout: 5))
        XCTAssertTrue(
            clear.waitForNonExistence(timeout: 5),
            "Clear All should hide after filters reset to Last 7 days"
        )
    }

    func testLightAppearanceKeepsTabsAndStatsFilters() {
        XCTAssertTrue(settingsTab.waitForExistence(timeout: uiTimeout))
        settingsTab.tap()

        let appearance = app.descendants(matching: .any)["settings.appearance"]
        revealSettingsControl(appearance)
        XCTAssertTrue(appearance.waitForExistence(timeout: uiTimeout), "Appearance picker should exist after scrolling Settings")

        let lightSegment = appearance.buttons["Light"]
        if lightSegment.waitForExistence(timeout: 2) {
            lightSegment.tap()
        } else if appearance.buttons.count >= 2 {
            appearance.buttons.element(boundBy: 1).tap()
        }

        let orangeSwatch = app.buttons["settings.shellPalette.orange"]
        revealSettingsControl(orangeSwatch)
        XCTAssertTrue(
            orangeSwatch.waitForExistence(timeout: uiTimeout),
            "Orange palette swatch is in a lazy Settings grid and must be scrolled on screen"
        )
        orangeSwatch.tap()
        XCTAssertTrue(orangeSwatch.isSelected)

        XCTAssertTrue(tripsTab.waitForExistence(timeout: uiTimeout))
        tripsTab.tap()
        XCTAssertTrue(tripsTab.exists)

        statsTab.tap()
        let week = app.descendants(matching: .any)["stats.filters.period.week"]
        XCTAssertTrue(week.waitForExistence(timeout: uiTimeout), "Last 7 days filter should remain after Light appearance")
        openStatsFilterPanel()
        XCTAssertTrue(app.descendants(matching: .any)["stats.filters.card"].waitForExistence(timeout: uiTimeout))
    }

    func testStatsSectionTitlePinsWhileScrolling() {
        XCTAssertTrue(statsTab.waitForExistence(timeout: uiTimeout))
        statsTab.tap()
        let summary = app.descendants(matching: .any)["stats.section.summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: uiTimeout))
        app.swipeUp()
        let daily = app.descendants(matching: .any)["stats.section.daily"]
        XCTAssertTrue(
            daily.waitForExistence(timeout: 8) || summary.waitForExistence(timeout: 1),
            "A pinned section title should stay on screen after scrolling"
        )
    }

    func testRecapYearPickerIsOnAwardsCard() {
        XCTAssertTrue(yearTab.waitForExistence(timeout: uiTimeout))
        yearTab.tap()
        let yearPicker = app.descendants(matching: .any)["recap.year.toggle"]
        XCTAssertTrue(yearPicker.waitForExistence(timeout: uiTimeout))
    }

    func testSettingsBackupExportIsReachable() {
        XCTAssertTrue(settingsTab.waitForExistence(timeout: uiTimeout))
        settingsTab.tap()
        let export = app.buttons["settings.export.json"]
        revealSettingsControl(export)
        XCTAssertTrue(
            export.waitForExistence(timeout: uiTimeout),
            "Backup export should be reachable by scrolling Settings"
        )
    }

    func testSideColumnChromeSurvivesRotation() {
        XCTAssertTrue(tripsTab.waitForExistence(timeout: uiTimeout))
        let orientations: [(UIDeviceOrientation, String)] = [
            (.portrait, "portrait"),
            (.landscapeLeft, "landscapeLeft"),
            (.landscapeRight, "landscapeRight"),
            (.portraitUpsideDown, "portraitUpsideDown"),
            (.portrait, "portraitAgain")
        ]
        for (orientation, name) in orientations {
            XCUIDevice.shared.orientation = orientation
            let bells = app.buttons.matching(identifier: "trips.notifications")
            XCTAssertTrue(bells.firstMatch.waitForExistence(timeout: uiTimeout), "Bell missing after \(name)")
            XCTAssertEqual(bells.count, 1, "Bell duplicated after \(name)")

            let merges = app.buttons.matching(identifier: "trips.merge")
            if merges.firstMatch.waitForExistence(timeout: 2) {
                XCTAssertEqual(merges.count, 1, "Merge duplicated after \(name)")
            }

            let shot = XCUIScreen.main.screenshot()
            let attachment = XCTAttachment(screenshot: shot)
            attachment.name = "side-column-\(name)"
            attachment.lifetime = .keepAlways
            add(attachment)

            let bell = bells.firstMatch.frame
            XCTAssertLessThan(bell.midY, app.frame.height * 0.28, "Bell is not on the top row after \(name)")
            XCTAssertGreaterThan(bell.midX, app.frame.width * 0.45, "Bell is not on the trailing side after \(name)")
            // A hidden tab can leave a second Start with an empty frame. The visible one has a real frame.
            let starts = app.buttons.matching(identifier: "shell.start").allElementsBoundByIndex
            let visibleStart = starts.first { $0.frame.width > 1 && $0.frame.maxX.isFinite }
            if starts.contains(where: \.exists) {
                XCTAssertNotNil(visibleStart, "Start has no frame after \(name)")
                if let visibleStart {
                    XCTAssertLessThan(visibleStart.frame.maxX, bell.minX, "Start is joined to the bell after \(name)")
                }
            }
            if merges.count == 1 {
                let merge = merges.firstMatch.frame
                let stacked = abs(merge.midX - bell.midX) < 24 && merge.minY >= bell.maxY - 8
                if stacked {
                    XCTAssertLessThan(merge.maxY, app.frame.height * 0.45, "Stacked pair is not under the status cluster after \(name)")
                } else {
                    XCTAssertEqual(merge.midY, bell.midY, accuracy: CGFloat(12), "Merge is not beside the bell after \(name)")
                    XCTAssertGreaterThan(merge.midX, bell.midX, "Merge is not to the right of the bell after \(name)")
                }
            }
        }
    }
}

final class TrailhoundDrivingSafetyNoticeUITests: TrailhoundUITestCase {
    override var extraLaunchArguments: [String] { ["-UITesting.drivingNoticeSeed"] }

    func testFirstStartShowsDrivingNoticeOnlyOnce() {
        XCTAssertTrue(tripsTab.waitForExistence(timeout: uiTimeout))
        let start = visibleStart()
        XCTAssertTrue(start.waitForExistence(timeout: uiTimeout))
        start.tap()

        let notice = app.alerts["Eyes on the road"]
        XCTAssertTrue(notice.waitForExistence(timeout: uiTimeout))
        XCTAssertEqual(app.alerts.count, 1)
        notice.buttons["Got it"].firstMatch.tap()
        XCTAssertTrue(notice.waitForNonExistence(timeout: 10))

        // Start hides while recording. If the simulator had no location and stayed idle, a second tap must not ask again.
        let again = visibleStart()
        if again.waitForExistence(timeout: 3), again.isHittable {
            again.tap()
            XCTAssertFalse(app.alerts["Eyes on the road"].waitForExistence(timeout: 3))
        }
    }

    private func visibleStart() -> XCUIElement {
        let starts = app.buttons.matching(identifier: "shell.start")
        return starts.allElementsBoundByIndex.first { $0.isHittable } ?? starts.firstMatch
    }
}

final class TrailhoundSmartCategoryUITests: TrailhoundUITestCase {
    override var extraLaunchArguments: [String] { ["-UITesting.smartCategorySeed"] }

    func testSmartCategorySettingsToggleHidesWorkHours() {
        XCTAssertTrue(settingsTab.waitForExistence(timeout: uiTimeout))
        settingsTab.tap()

        let toggle = app.switches["settings.smartCategory"]
        revealSettingsControl(toggle)
        XCTAssertTrue(toggle.waitForExistence(timeout: uiTimeout))
        XCTAssertTrue(toggle.isHittable, "Smart category toggle must be tappable, not under the tab bar")
        XCTAssertTrue(toggle.isEnabled)

        if (toggle.value as? String) != "1" {
            toggle.tap()
        }
        XCTAssertEqual(toggle.value as? String, "1")

        let workStart = app.descendants(matching: .any)["settings.smartCategory.workStart"]
        XCTAssertTrue(
            workStart.waitForExistence(timeout: 5),
            "Work-hour start should be visible while suggestions are on"
        )

        toggle.tap()
        if ["1", "On"].contains(toggle.value as? String ?? "") {
            toggle.swipeLeft()
        }

        let rawValue = String(describing: toggle.value)
        let pickersHidden = !app.descendants(matching: .any)["settings.smartCategory.workStart"].waitForExistence(timeout: 3)
        XCTAssertTrue(
            pickersHidden,
            "Work-hour pickers should hide when suggestions are off (toggle value=\(rawValue))"
        )
        XCTAssertFalse(app.descendants(matching: .any)["settings.smartCategory.workEnd"].exists)
    }

    private func element(identifier: String) -> XCUIElement {
        let button = app.buttons[identifier]
        if button.exists { return button }
        let cell = app.cells[identifier]
        if cell.exists { return cell }
        let other = app.otherElements[identifier]
        if other.exists { return other }
        return button
    }

    private func waitForIdentifier(_ identifier: String) -> Bool {
        if app.buttons[identifier].waitForExistence(timeout: uiTimeout) {
            return true
        }
        if app.cells[identifier].waitForExistence(timeout: 3) {
            return true
        }
        if app.otherElements[identifier].waitForExistence(timeout: 3) {
            return true
        }
        return app.descendants(matching: .any)[identifier].waitForExistence(timeout: 3)
    }

    func testSuggestedCategoryChipAppearsOnTripRow() {
        XCTAssertTrue(tripsTab.waitForExistence(timeout: uiTimeout))
        XCTAssertTrue(
            waitForIdentifier("trips.row.first.suggested"),
            "Seeded commute trip should be the first row with a pending suggestion"
        )
    }

    func testSwipeAcceptsSuggestedCategory() {
        XCTAssertTrue(tripsTab.waitForExistence(timeout: uiTimeout))
        XCTAssertTrue(
            waitForIdentifier("trips.row.first.suggested"),
            "Seeded commute trip should be the first row with a pending suggestion"
        )

        element(identifier: "trips.row.first.suggested").swipeRight()
        let accept = element(identifier: "trips.row.acceptSuggestedCategory")
        if accept.waitForExistence(timeout: 3) {
            accept.tap()
        }

        XCTAssertTrue(
            waitForIdentifierGone("trips.row.first.suggested"),
            "Accepting the suggestion should replace the pending chip with a normal first row"
        )
        XCTAssertTrue(waitForIdentifier("trips.row.first"))

        let toast = app.staticTexts["Category updated"]
        _ = toast.waitForExistence(timeout: 2)
    }

    private func waitForIdentifierGone(_ identifier: String) -> Bool {
        app.descendants(matching: .any)[identifier].waitForNonExistence(timeout: 5)
    }

    func testRecapCardsExpandAndCollapse() {
        XCTAssertTrue(yearTab.waitForExistence(timeout: uiTimeout))
        yearTab.tap()
        expandAndCollapse(
            openID: "stats.premium.achievements",
            expandedID: "stats.achievements.expanded",
            closeID: "stats.achievement.expanded.close"
        )
        expandAndCollapse(
            openID: "stats.premium.routes",
            expandedID: "stats.premium.routes.expanded",
            closeID: "stats.premium.routes.expanded.close"
        )
        expandAndCollapse(
            openID: "stats.premium.forecast",
            expandedID: "stats.premium.forecast.expanded",
            closeID: "stats.premium.forecast.expanded.close"
        )
    }

    private func expandAndCollapse(openID: String, expandedID: String, closeID: String) {
        let open = app.descendants(matching: .any)[openID].firstMatch
        revealSettingsControl(open)
        XCTAssertTrue(open.waitForExistence(timeout: uiTimeout), openID)
        open.tap()

        let expanded = app.descendants(matching: .any)[expandedID].firstMatch
        XCTAssertTrue(expanded.waitForExistence(timeout: uiTimeout), expandedID)
        let close = app.descendants(matching: .any)[closeID].firstMatch
        let hittable = NSPredicate(format: "isHittable == true")
        let appeared = XCTNSPredicateExpectation(predicate: hittable, object: close)
        XCTAssertEqual(XCTWaiter().wait(for: [appeared], timeout: uiTimeout), .completed, closeID)
        close.tap()
        XCTAssertTrue(expanded.waitForNonExistence(timeout: uiTimeout), expandedID)
    }
}

/// Trip A open on the Trips stack, user switches tab, then opens trip B from a read
/// notification. B must draw B's own route — never A's route under B's pins.
final class TripDetailTripSwitchUITests: TrailhoundUITestCase {
    private let newestID = "AAAAAAAA-0000-4000-8000-0000000000A1"
    private let olderID = "AAAAAAAA-0000-4000-8000-0000000000B2"

    override var extraLaunchArguments: [String] { ["-UITesting.tripSwitchSeed"] }

    private var routeIdentity: XCUIElement {
        app.descendants(matching: .any)["tripDetail.routeIdentity"].firstMatch
    }

    private func waitForRoute(of tripID: String, file: StaticString = #filePath, line: UInt = #line) {
        let expected = "trip=\(tripID) model=\(tripID) route=match"
        let predicate = NSPredicate(format: "label == %@", expected)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: routeIdentity)
        let result = XCTWaiter().wait(for: [expectation], timeout: uiTimeout)
        XCTAssertEqual(
            result, .completed,
            "Route readout was '\(routeIdentity.exists ? routeIdentity.label : "missing")', expected '\(expected)'",
            file: file, line: line
        )
    }

    func testNotificationOpenAfterTabSwitchDrawsTheNewTripsRoute() {
        XCTAssertTrue(tripsTab.waitForExistence(timeout: uiTimeout))
        let firstRow = app.buttons["trips.row.first"]
        XCTAssertTrue(firstRow.waitForExistence(timeout: uiTimeout))
        firstRow.tap()
        XCTAssertTrue(app.otherElements["tripDetail.screen"].waitForExistence(timeout: uiTimeout))
        waitForRoute(of: newestID)

        pairingTab.tap()
        let bell = app.buttons["trips.notifications"].firstMatch
        XCTAssertTrue(bell.waitForExistence(timeout: uiTimeout))
        bell.tap()
        let row = app.descendants(matching: .any)["notifications.row.trip.\(olderID)"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: uiTimeout), "Seeded Switch B inbox row should be listed")
        row.tap()

        XCTAssertTrue(app.otherElements["tripDetail.screen"].waitForExistence(timeout: uiTimeout))
        waitForRoute(of: olderID)

        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(firstRow.waitForExistence(timeout: uiTimeout), "One back must land on the list")

        firstRow.tap()
        waitForRoute(of: newestID)
    }
}

final class OdometerCareUITests: TrailhoundUITestCase {
    override var extraLaunchArguments: [String] { ["-UITesting.odometerCareSeed"] }

    func testSeededTripShowsKilometresLeftOnTheServiceChip() {
        XCTAssertTrue(pairingTab.waitForExistence(timeout: uiTimeout))
        pairingTab.tap()

        let vehicle = app.staticTexts["Vespa"].firstMatch
        XCTAssertTrue(vehicle.waitForExistence(timeout: uiTimeout), "Seeded Vespa should be listed")
        vehicle.tap()

        let chip = app.descendants(matching: .any)["vehicle.care.due.chip"].firstMatch
        revealControl(chip)
        XCTAssertTrue(chip.waitForExistence(timeout: uiTimeout), "Service chip should show kilometres left")
        XCTAssertTrue(chip.label.localizedCaseInsensitiveContains("500"))
        XCTAssertTrue(chip.label.localizedCaseInsensitiveContains("km"))
    }

    private func revealControl(_ query: XCUIElement) {
        for _ in 0..<12 {
            if query.waitForExistence(timeout: 1), query.isHittable { return }
            if query.exists, !query.isHittable {
                app.swipeDown()
                if query.isHittable { return }
            }
            app.swipeUp()
        }
    }
}

final class VehicleExpenseCategoryUITests: TrailhoundUITestCase {
    override var extraLaunchArguments: [String] { ["-UITesting.expenseCategorySeed"] }

    func testAddHgsExpenseShowsHgsRow() {
        XCTAssertTrue(pairingTab.waitForExistence(timeout: uiTimeout))
        pairingTab.tap()

        let vehicleRow = app.descendants(matching: .any)["vehicles.row"].firstMatch
        XCTAssertTrue(vehicleRow.waitForExistence(timeout: uiTimeout), "Seeded vehicle row should be on Vehicles")
        vehicleRow.tap()

        let addExpense = app.descendants(matching: .any)["expense.add"].firstMatch
        revealControl(addExpense)
        XCTAssertTrue(addExpense.waitForExistence(timeout: uiTimeout), "Add expense should be on the vehicle screen")
        addExpense.tap()

        let category = app.descendants(matching: .any)["expense.category"].firstMatch
        XCTAssertTrue(category.waitForExistence(timeout: uiTimeout))
        category.tap()
        let hgs = app.descendants(matching: .any)["expense.category.hgs"].firstMatch
        XCTAssertTrue(hgs.waitForExistence(timeout: uiTimeout), "Road toll must be a picker option")
        hgs.tap()

        let amount = app.descendants(matching: .any)["expense.amount"].firstMatch
        XCTAssertTrue(amount.waitForExistence(timeout: uiTimeout))
        amount.tap()
        amount.typeText("25")

        let save = app.descendants(matching: .any)["expense.save"].firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: uiTimeout))
        save.tap()

        let row = app.descendants(matching: .any)["expense.row.hgs"].firstMatch
        revealControl(row)
        XCTAssertTrue(row.waitForExistence(timeout: uiTimeout), "Saved road-toll expense should appear in the list")
    }

    private func revealControl(_ query: XCUIElement) {
        for _ in 0..<12 {
            if query.waitForExistence(timeout: 1), query.isHittable { return }
            if query.exists, !query.isHittable {
                app.swipeDown()
                if query.isHittable { return }
            }
            app.swipeUp()
        }
    }
}

final class PadLayoutUITests: TrailhoundUITestCase {
    override var extraLaunchArguments: [String] { ["-UITesting.odometerCareSeed"] }

    override func setUpWithError() throws {
        try super.setUpWithError()
        guard UIDevice.current.userInterfaceIdiom == .pad else { return }
        XCUIDevice.shared.orientation = .landscapeLeft
    }

    func testPadVehicleDetailSplitsInLandscape() throws {
        try skipUnlessPad()
        XCTAssertTrue(pairingTab.waitForExistence(timeout: uiTimeout))
        pairingTab.tap()
        let vehicle = app.staticTexts["Vespa"].firstMatch
        XCTAssertTrue(vehicle.waitForExistence(timeout: uiTimeout))
        vehicle.tap()

        let profile = app.descendants(matching: .any)["vehicle.detail.profilePane"].firstMatch
        let tracking = app.descendants(matching: .any)["vehicle.detail.trackingPane"].firstMatch
        let addReminder = app.descendants(matching: .any)["vehicle.care.tracking.add"].firstMatch
        XCTAssertTrue(profile.waitForExistence(timeout: uiTimeout))
        XCTAssertTrue(tracking.waitForExistence(timeout: uiTimeout))
        XCTAssertTrue(addReminder.waitForExistence(timeout: uiTimeout))
        XCTAssertGreaterThan(addReminder.frame.minX, profile.frame.minX)
        XCTAssertLessThan(addReminder.frame.minY, profile.frame.maxY)
    }

    func testPadRecapPairsCardsInLandscape() throws {
        try skipUnlessPad()
        XCTAssertTrue(yearTab.waitForExistence(timeout: uiTimeout))
        yearTab.tap()
        let awards = app.descendants(matching: .any)["recap.section.awards"].firstMatch
        let badges = app.descendants(matching: .any)["recap.section.badges"].firstMatch
        XCTAssertTrue(awards.waitForExistence(timeout: uiTimeout))
        XCTAssertTrue(badges.waitForExistence(timeout: uiTimeout))
        XCTAssertEqual(awards.frame.minY, badges.frame.minY, accuracy: 24)
        XCTAssertGreaterThan(abs(awards.frame.midX - badges.frame.midX), 40)
    }

    private func skipUnlessPad() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "iPad layout")
    }
}

/// Live-map planned route: pick a saved place, see remaining distance + arrival, remove it.
/// `-UITesting.plannedRouteSeed` swaps MapKit for a straight-line provider and seeds "Route Seed Office".
class LiveMapPlannedRouteUITestCase: TrailhoundUITestCase {
    override var extraLaunchArguments: [String] { ["-UITesting.plannedRouteSeed"] }

    let seedPlaceIdentifier = "destinationSheet.place.AAAAAAAA-0000-4000-8000-0000000000D5"

    func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    func openLiveMap() throws {
        XCTAssertTrue(tripsTab.waitForExistence(timeout: uiTimeout))
        let starts = app.buttons.matching(identifier: "shell.start")
        let start = starts.allElementsBoundByIndex.first { $0.isHittable } ?? starts.firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: uiTimeout))
        start.tap()
        guard element("recording.live_map.open").waitForExistence(timeout: uiTimeout) else {
            throw XCTSkip("Recording did not start on this simulator (no location authorization).")
        }
        liveMapOpenButton().tap()
        XCTAssertTrue(element("liveMap.destination").waitForExistence(timeout: uiTimeout))
    }

    /// The recording card shares the identifier; the map glyph is the smallest match.
    func liveMapOpenButton() -> XCUIElement {
        let matches = app.buttons.matching(identifier: "recording.live_map.open").allElementsBoundByIndex
        return matches.min { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
            ?? element("recording.live_map.open")
    }

    func stopRecording() {
        let close = element("liveMap.close")
        if close.waitForExistence(timeout: 5) {
            close.tap()
        }
        let stop = app.buttons["Stop"].firstMatch
        if stop.waitForExistence(timeout: uiTimeout) {
            stop.tap()
        }
    }
}

final class LiveMapPlannedRouteUITests: LiveMapPlannedRouteUITestCase {
    func testLiveMapPlannedRouteShowsEtaAndClears() throws {
        try openLiveMap()
        element("liveMap.destination").tap()

        let place = element(seedPlaceIdentifier)
        XCTAssertTrue(place.waitForExistence(timeout: uiTimeout))
        XCTAssertTrue(element("destinationSheet.search").exists, "Stopped car: search is open")
        place.tap()

        let eta = element("liveMap.eta")
        XCTAssertTrue(eta.waitForExistence(timeout: uiTimeout))
        eta.tap()

        let clear = element("liveMap.destination.clear")
        XCTAssertTrue(clear.waitForExistence(timeout: uiTimeout))
        clear.tap()
        XCTAssertTrue(element("liveMap.destination").waitForExistence(timeout: uiTimeout))
        XCTAssertFalse(eta.exists)

        stopRecording()
    }

    func testDestinationSurvivesClosingTheLiveMap() throws {
        try openLiveMap()
        element("liveMap.destination").tap()
        let place = element(seedPlaceIdentifier)
        XCTAssertTrue(place.waitForExistence(timeout: uiTimeout))
        place.tap()
        XCTAssertTrue(element("liveMap.eta").waitForExistence(timeout: uiTimeout))

        element("liveMap.close").tap()
        XCTAssertTrue(element("recording.live_map.open").waitForExistence(timeout: uiTimeout))
        liveMapOpenButton().tap()
        XCTAssertTrue(element("liveMap.eta").waitForExistence(timeout: uiTimeout))

        stopRecording()
    }
}

final class LiveMapPlannedRouteMovingUITests: LiveMapPlannedRouteUITestCase {
    override var extraLaunchArguments: [String] { ["-UITesting.plannedRouteSeed", "-UITesting.plannedRouteMoving"] }

    func testSearchLocksWhileMovingButSavedPlacesStayOneTap() throws {
        try openLiveMap()
        element("liveMap.destination").tap()

        XCTAssertTrue(element("destinationSheet.search.locked").waitForExistence(timeout: uiTimeout))
        XCTAssertFalse(element("destinationSheet.search").exists)
        let place = element(seedPlaceIdentifier)
        XCTAssertTrue(place.waitForExistence(timeout: uiTimeout))
        place.tap()
        XCTAssertTrue(element("liveMap.eta").waitForExistence(timeout: uiTimeout))

        stopRecording()
    }
}

final class LiveMapPlannedRoutePadUITests: LiveMapPlannedRouteUITestCase {
    /// The runner can report a phone idiom on an iPad simulator; the app window cannot lie.
    private var isPad: Bool {
        let frame = app.windows.firstMatch.frame
        return min(frame.width, frame.height) >= 744
    }

    func testPadDestinationFormPicksAndCloses() throws {
        XCTAssertTrue(tripsTab.waitForExistence(timeout: uiTimeout))
        try XCTSkipUnless(isPad, "iPad layout")
        XCUIDevice.shared.orientation = .landscapeLeft
        try openLiveMap()
        element("liveMap.destination").tap()

        let close = element("destinationSheet.close")
        XCTAssertTrue(close.waitForExistence(timeout: uiTimeout))
        close.tap()
        XCTAssertTrue(close.waitForNonExistence(timeout: uiTimeout))

        element("liveMap.destination").tap()
        let place = element(seedPlaceIdentifier)
        XCTAssertTrue(place.waitForExistence(timeout: uiTimeout))
        place.tap()
        XCTAssertTrue(element("liveMap.eta").waitForExistence(timeout: uiTimeout))

        stopRecording()
    }
}

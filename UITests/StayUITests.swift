import XCTest

/// Walks the critical flows end to end. Set SCREENSHOT_DIR (via the
/// TEST_RUNNER_SCREENSHOT_DIR build environment) to save a PNG of every step.
final class StayUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTestReset"]
        if let size = ProcessInfo.processInfo.environment["CONTENT_SIZE"] {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", size]
        }
    }

    // MARK: Owner

    func testOwnerOnboardingMissionReviewAndTabs() {
        app.launch()
        completeOwnerOnboarding(dogName: "Biscuit")
        snap("05-today-baseline")

        // Baseline mission, start to finish.
        tap(app.buttons["Start baseline"].firstMatch)
        snap("06-brief")
        tap(app.buttons["brief.start"])
        XCTAssertTrue(app.buttons["run.back"].waitForExistence(timeout: 5))
        sleep(3)
        snap("07-running")
        tap(app.buttons["run.noticed"])
        sleep(1)
        tap(app.buttons["run.back"])
        XCTAssertTrue(app.buttons["review.save"].waitForExistence(timeout: 5))
        snap("08-review")
        tap(app.buttons["review.save"])
        XCTAssertTrue(app.buttons["result.done"].waitForExistence(timeout: 5))
        snap("09-result")
        tap(app.buttons["result.done"])

        // Baseline done for today; another round is still possible.
        XCTAssertTrue(app.staticTexts["Done for today"].waitForExistence(timeout: 5))
        snap("10-today-mission")

        // Cue practice logs a reaction.
        let calm = app.buttons["Didn't care"]
        if calm.waitForExistence(timeout: 2) {
            calm.tap()
            snap("11-cue-logged")
        }

        tapTab("Progress")
        snap("12-progress")
        tapTab("Coach")
        snap("13-coach")
        tapTab("Settings")
        snap("14-settings")

        // Paywall: plans, legal links and restore are present.
        let pro = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Try Stay Pro'")).firstMatch
        tap(pro)
        XCTAssertTrue(app.buttons["Restore purchases"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.links["Terms of Use"].exists || app.buttons["Terms of Use"].exists)
        XCTAssertTrue(app.links["Privacy Policy"].exists || app.buttons["Privacy Policy"].exists)
        snap("15-paywall")
        tap(app.buttons["Close"])
    }

    func testSecondDogNeedsPro() {
        app.launch()
        completeOwnerOnboarding(dogName: "Pip")
        tapTab("Settings")
        let add = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Add a dog'")).firstMatch
        tap(add)
        // Free tier allows one dog, so the paywall opens.
        XCTAssertTrue(app.buttons["Restore purchases"].waitForExistence(timeout: 8))
        tap(app.buttons["Close"])
    }

    // MARK: Camera

    func testCameraModeWithPermissionsDenied() {
        addUIInterruptionMonitor(withDescription: "Permissions") { alert in
            for title in ["Don’t Allow", "Don't Allow"] where alert.buttons[title].exists {
                alert.buttons[title].tap()
                return true
            }
            return false
        }
        app.launch()
        tap(app.buttons["Get started"])
        tap(app.buttons.matching(NSPredicate(format: "label CONTAINS 'This is the dog camera'")).firstMatch)
        snap("20-camera-permissions")
        tap(app.buttons["Continue"])
        // Let the interruption monitor answer the system prompts.
        for _ in 0..<4 {
            sleep(1)
            app.swipeUp()
        }
        let later = app.buttons["Pair later"]
        XCTAssertTrue(later.waitForExistence(timeout: 10))
        snap("21-camera-pairing")
        later.tap()
        XCTAssertTrue(app.buttons["Arm camera"].waitForExistence(timeout: 5))
        snap("22-camera-setup")
        app.buttons["Arm camera"].tap()
        XCTAssertTrue(app.buttons["Disarm"].waitForExistence(timeout: 10))
        snap("23-camera-armed")
        app.buttons["Disarm"].tap()
        XCTAssertTrue(app.buttons["Arm camera"].waitForExistence(timeout: 5))
    }

    // MARK: Helpers

    private func completeOwnerOnboarding(dogName: String) {
        tap(app.buttons["Get started"])
        snap("01-role")
        tap(app.buttons.matching(NSPredicate(format: "label CONTAINS 'This is my phone'")).firstMatch)
        let name = app.textFields.firstMatch
        tap(name)
        name.typeText(dogName)
        snap("02-profile")
        tap(app.buttons["Continue"])
        for answer in ["A few minutes", "Sometimes", "No", "No", "A little — they follow me around", "Yes", "No"] {
            let option = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", answer)).firstMatch
            tap(option)
            sleep(1)
        }
        XCTAssertTrue(app.staticTexts["\(dogName)'s plan is ready"].waitForExistence(timeout: 5))
        snap("03-plan-ready")
        tap(app.buttons["Continue"])
        tap(app.buttons["Not now"])
        XCTAssertTrue(app.buttons["Continue without an account"].waitForExistence(timeout: 5))
        snap("04-account")
        app.buttons["Continue without an account"].tap()
    }

    private func tap(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 8), "Missing \(element)", file: file, line: line)
        element.tap()
    }

    private func tapTab(_ name: String) {
        tap(app.tabBars.buttons[name].firstMatch)
        sleep(1)
    }

    private func snap(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"] {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? shot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
    }
}

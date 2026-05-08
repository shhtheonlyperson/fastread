import XCTest

@MainActor
final class FastReadHappyPathUITests: XCTestCase {
    private static let epubFilenameStem = "test"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testEpubHappyPath() throws {
        let epubPath = try Self.resolveEpubHostPath()

        let app = XCUIApplication()
        app.launchArguments = [
            "-FASTREAD_RESET_LIBRARY", "1",
            "-FASTREAD_SEED_EPUB", epubPath
        ]
        app.launch()

        dismissSplash(app: app)

        let addTab = app.buttons["ADD"]
        XCTAssertTrue(addTab.waitForExistence(timeout: 10), "Add tab did not appear")
        addTab.tap()

        let pickButton = app.buttons["Pick EPUB"]
        XCTAssertTrue(pickButton.waitForExistence(timeout: 5), "Pick EPUB button did not appear")
        pickButton.tap()

        try navigateFilesPickerAndPickEpub(app: app, epubFilename: (epubPath as NSString).lastPathComponent)

        let title = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'local-test-book'")).firstMatch
        if !title.waitForExistence(timeout: 20) {
            attachScreenshot(name: "no-title-after-pick")
            XCTFail("Reader title for local-test-book did not appear. Tree:\n\(app.debugDescription)")
        }

        let positionRegex = NSPredicate(format: "label MATCHES %@", "^[0-9,]+ / [0-9,]+$")
        let positionLabel = app.staticTexts.matching(positionRegex).firstMatch
        XCTAssertTrue(positionLabel.waitForExistence(timeout: 8), "Position counter not visible")
        let preIndex = Self.parseLeadingInt(positionLabel.label)

        let skipButton = app.buttons.matching(NSPredicate(format: "label CONTAINS 'SKIP'")).firstMatch
        XCTAssertTrue(skipButton.waitForExistence(timeout: 5), "SKIP banner did not appear")
        skipButton.tap()

        XCTAssertTrue(
            waitUntil(timeout: 6) {
                let updated = app.staticTexts.matching(positionRegex).firstMatch
                guard updated.exists else { return false }
                return Self.parseLeadingInt(updated.label) > preIndex
            },
            "Playhead did not advance after SKIP"
        )

        let contentsButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Contents'")).firstMatch
        XCTAssertTrue(contentsButton.waitForExistence(timeout: 5), "Contents header button missing")
        contentsButton.tap()

        let drawerTitle = app.staticTexts["Contents"].firstMatch
        XCTAssertTrue(drawerTitle.waitForExistence(timeout: 5), "TOC drawer did not present")

        // After SKIP we are sitting on chapter 01, so tap a different chapter row
        // so the playhead clearly moves when the drawer dismisses.
        let chapterNumbers = app.staticTexts.matching(NSPredicate(format: "label MATCHES '^[0-9]{2}$'"))
        XCTAssertTrue(
            waitUntil(timeout: 5) { chapterNumbers.count >= 2 },
            "Expected at least two numbered chapter rows in drawer"
        )
        let preTocIndex = Self.parseLeadingInt(app.staticTexts.matching(positionRegex).firstMatch.label)
        let targetChapter = chapterNumbers.element(boundBy: min(chapterNumbers.count - 1, 2))
        if !targetChapter.isHittable {
            app.swipeUp()
        }
        targetChapter.tap()

        XCTAssertTrue(
            waitUntil(timeout: 5) { !drawerTitle.exists },
            "TOC drawer did not dismiss after chapter tap"
        )

        let updatedAfterToc = app.staticTexts.matching(positionRegex).firstMatch
        XCTAssertTrue(updatedAfterToc.waitForExistence(timeout: 5))
        let postTocIndex = Self.parseLeadingInt(updatedAfterToc.label)
        XCTAssertNotEqual(preTocIndex, postTocIndex, "Reader position should change after TOC selection")

        XCTAssertTrue(title.exists, "Reader title should remain visible after TOC dismiss")

        attachScreenshot(name: "reader-final")
    }

    private func attachScreenshot(name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func dismissSplash(app: XCUIApplication) {
        // Splash auto-dismisses ~2s; tap to skip.
        if app.wait(for: .runningForeground, timeout: 10) {
            app.tap()
        }
    }

    private func navigateFilesPickerAndPickEpub(app: XCUIApplication, epubFilename: String) throws {
        let containsEpub = NSPredicate(format: "label CONTAINS %@", epubFilename)

        // First try: pick the cell straight away if the picker landed on JustRead.
        if tapEpubCell(in: app, predicate: containsEpub, timeout: 4) {
            return
        }

        // Otherwise: Browse → On My iPhone → JustRead → epub
        let browseTab = app.tabBars.buttons["Browse"]
        if browseTab.waitForExistence(timeout: 3) { browseTab.tap() }

        for candidate in [
            app.cells.staticTexts["On My iPhone"],
            app.staticTexts["On My iPhone"]
        ] where candidate.waitForExistence(timeout: 4) {
            candidate.tap()
            break
        }

        for candidate in [
            app.cells.staticTexts["JustRead"],
            app.staticTexts["JustRead"]
        ] where candidate.waitForExistence(timeout: 4) {
            candidate.tap()
            break
        }

        XCTAssertTrue(
            tapEpubCell(in: app, predicate: containsEpub, timeout: 6),
            "Could not find or open \(epubFilename) in Files picker"
        )
    }

    private func tapEpubCell(
        in app: XCUIApplication,
        predicate: NSPredicate,
        timeout: TimeInterval
    ) -> Bool {
        let cell = app.cells.matching(predicate).firstMatch
        guard cell.waitForExistence(timeout: timeout) else { return false }
        cell.tap()
        return true
    }

    private func waitUntil(timeout: TimeInterval, condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            usleep(150_000)
        }
        return condition()
    }

    private static func parseLeadingInt(_ label: String) -> Int {
        let digits = label.split(separator: " ").first.map(String.init) ?? label
        let cleaned = digits.replacingOccurrences(of: ",", with: "")
        return Int(cleaned) ?? -1
    }

    private static func resolveEpubHostPath() throws -> String {
        let env = ProcessInfo.processInfo.environment
        var probed: [String] = []

        if let envPath = env["FASTREAD_E2E_EPUB"], !envPath.isEmpty {
            probed.append("env=\(envPath)")
            if FileManager.default.fileExists(atPath: envPath) {
                return envPath
            }
        }

        if let bundleURL = Bundle(for: FastReadHappyPathUITests.self)
            .url(forResource: epubFilenameStem, withExtension: "epub") {
            probed.append("bundle=\(bundleURL.path)")
            if FileManager.default.fileExists(atPath: bundleURL.path) {
                return bundleURL.path
            }
        }

        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<10 {
            let candidate = dir.appendingPathComponent("test.epub")
            probed.append("walk=\(candidate.path)")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate.path
            }
            dir.deleteLastPathComponent()
        }

        throw XCTSkip("test.epub not found. Tried: \(probed.joined(separator: " | "))")
    }
}

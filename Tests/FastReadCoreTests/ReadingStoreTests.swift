import XCTest
@testable import FastReadCore

// Direct unit coverage of the central reader state machine. ReadingStore
// owns the library, the playback timer, the WPM/punctuation/focus
// settings, the stats roll-up, and the UserDefaults persistence layer.
// Each test boots a fresh store against a private UserDefaults suite and
// tears it down at the end so suites stay hermetic and don't leak into
// the user's real shared defaults.
@MainActor
final class ReadingStoreTests: XCTestCase {
    nonisolated(unsafe) private var suiteName: String!
    nonisolated(unsafe) private var defaults: UserDefaults!

    override func setUpWithError() throws {
        suiteName = "test.justread.\(UUID().uuidString)"
        guard let suite = UserDefaults(suiteName: suiteName) else {
            throw XCTSkip("Could not create UserDefaults suite \(suiteName!)")
        }
        defaults = suite
    }

    override func tearDown() {
        defaults?.removePersistentDomain(forName: suiteName)
    }

    private func makeStore() -> ReadingStore {
        ReadingStore(defaults: defaults)
    }

    // MARK: - Library lifecycle

    func testAddDraftArticleAddsToLibraryAndSelectsIt() {
        let store = makeStore()
        XCTAssertEqual(store.articles.count, 0)

        store.addDraftArticle(text: "Hello world this is a tiny pasted note that is long enough to count.", title: "Tiny note")

        XCTAssertEqual(store.articles.count, 1)
        XCTAssertEqual(store.currentArticle?.title, "Tiny note")
        XCTAssertEqual(store.selectedArticleID, store.articles[0].id)
        XCTAssertGreaterThan(store.currentTokens.count, 0)
        XCTAssertEqual(store.currentIndex, 0)
        XCTAssertFalse(store.isPlaying)
    }

    func testAddDraftArticleIgnoresWhitespaceOnlyText() {
        let store = makeStore()
        store.addDraftArticle(text: "   \n   \n   ")
        XCTAssertEqual(store.articles.count, 0)
    }

    func testAddArticleMostRecentArticleAppearsFirst() {
        let store = makeStore()
        store.addDraftArticle(text: "first article body that is long enough.", title: "First")
        store.addDraftArticle(text: "second article body that is also long enough.", title: "Second")
        XCTAssertEqual(store.articles.count, 2)
        XCTAssertEqual(store.articles[0].title, "Second")
        XCTAssertEqual(store.articles[1].title, "First")
        XCTAssertEqual(store.currentArticle?.title, "Second")
    }

    func testDeleteArticleRemovesFromLibraryAndAdvancesSelection() {
        let store = makeStore()
        store.addDraftArticle(text: "a a a a a a a a a a a a", title: "A")
        store.addDraftArticle(text: "b b b b b b b b b b b b", title: "B")
        let firstID = store.articles[0].id
        XCTAssertEqual(store.currentArticle?.title, "B")

        store.deleteArticle(firstID)

        XCTAssertEqual(store.articles.count, 1)
        XCTAssertEqual(store.articles[0].title, "A")
        XCTAssertEqual(store.currentArticle?.title, "A", "deleting the selected article should fall back to a sibling")
    }

    func testDeleteUnselectedArticleLeavesSelectionAlone() {
        let store = makeStore()
        store.addDraftArticle(text: "a a a a a a a a", title: "A")
        store.addDraftArticle(text: "b b b b b b b b", title: "B")
        // newest is current ("B"); delete the older ("A") and selection should stay on B
        let oldestID = store.articles[1].id
        XCTAssertEqual(oldestID, store.articles.last?.id)
        store.deleteArticle(oldestID)
        XCTAssertEqual(store.articles.count, 1)
        XCTAssertEqual(store.currentArticle?.title, "B")
    }

    // MARK: - Reader navigation

    func testJumpToTokenSetsIndexAndPauses() {
        let store = makeStore()
        store.addDraftArticle(text: Self.longBody(120), title: "Long")
        XCTAssertGreaterThan(store.currentTokens.count, 100)
        store.play()
        XCTAssertTrue(store.isPlaying)

        store.jumpToToken(42)

        XCTAssertEqual(store.currentIndex, 42)
        XCTAssertFalse(store.isPlaying, "jumpToToken should pause playback")
    }

    func testJumpToTokenClampsToValidRange() {
        let store = makeStore()
        store.addDraftArticle(text: Self.longBody(50), title: "Bounded")
        let count = store.currentTokens.count

        store.jumpToToken(-99)
        XCTAssertEqual(store.currentIndex, 0)

        store.jumpToToken(count + 200)
        XCTAssertEqual(store.currentIndex, count - 1)
    }

    func testScrubMovesProgressProportionally() {
        let store = makeStore()
        store.addDraftArticle(text: Self.longBody(100), title: "Scrubbable")
        let count = store.currentTokens.count

        store.scrub(to: 0.5)
        // scrubbing to 50% should land at roughly the middle index
        XCTAssertEqual(store.currentIndex, Int((0.5 * Double(count - 1)).rounded()))
        XCTAssertFalse(store.isPlaying, "scrub from idle stays paused")
    }

    func testMarkReadFinishesArticle() {
        let store = makeStore()
        store.addDraftArticle(text: Self.longBody(40), title: "Finishable")
        XCTAssertEqual(store.currentArticle?.isFinished, false)

        store.markRead()

        XCTAssertEqual(store.currentArticle?.isFinished, true)
        XCTAssertEqual(store.currentArticle?.progress, 1)
        XCTAssertNotNil(store.currentArticle?.finishedAt)
        XCTAssertEqual(store.currentArticle?.tag, "Finished")
        XCTAssertFalse(store.isPlaying)
    }

    // MARK: - Playback toggling

    func testPlayRequiresMoreThanOneToken() {
        let store = makeStore()
        store.addDraftArticle(text: "single", title: "Single token")
        // single tokenizable token; play() guards on count > 1
        store.play()
        XCTAssertFalse(store.isPlaying)
    }

    func testPlayThenPauseTransitions() {
        let store = makeStore()
        store.addDraftArticle(text: Self.longBody(40), title: "Playable")
        store.play()
        XCTAssertTrue(store.isPlaying)
        store.pause()
        XCTAssertFalse(store.isPlaying)
    }

    func testTogglePlayFlipsState() {
        let store = makeStore()
        store.addDraftArticle(text: Self.longBody(40), title: "Toggle")
        store.togglePlay()
        XCTAssertTrue(store.isPlaying)
        store.togglePlay()
        XCTAssertFalse(store.isPlaying)
    }

    // MARK: - Settings + clamping

    func testSetWPMClampsToBounds() {
        let store = makeStore()
        store.setWPM(50)
        XCTAssertEqual(store.wpm, 300)
        store.setWPM(99_999)
        XCTAssertEqual(store.wpm, 1_000)
        store.setWPM(450)
        XCTAssertEqual(store.wpm, 450)
        store.setWPM(463)
        XCTAssertEqual(store.wpm, 475)
    }

    func testSettingsRoundTripThroughUserDefaults() {
        do {
            let store = makeStore()
            store.setWPM(620)
            store.punctuationPause = false
            store.focusIndicator = .crosshair
        }

        let reborn = makeStore()
        XCTAssertEqual(reborn.wpm, 625)
        XCTAssertEqual(reborn.punctuationPause, false)
        XCTAssertEqual(reborn.focusIndicator, .crosshair)
    }

    func testPreviewWPMDoesNotPersistUntilCommitted() {
        do {
            let store = makeStore()
            store.setWPM(500)
            store.previewWPM(720)
            XCTAssertEqual(store.wpm, 725)
        }

        XCTAssertEqual(makeStore().wpm, 500)

        do {
            let store = makeStore()
            store.setWPM(720)
        }

        XCTAssertEqual(makeStore().wpm, 725)
    }

    func testArticlesPersistAcrossInstances() {
        do {
            let store = makeStore()
            store.addDraftArticle(text: Self.longBody(60), title: "Persisted")
            store.jumpToToken(7)
        }

        let reborn = makeStore()
        XCTAssertEqual(reborn.articles.count, 1)
        XCTAssertEqual(reborn.articles[0].title, "Persisted")
        XCTAssertEqual(reborn.currentArticle?.wordIndex, 7, "wordIndex survives a UserDefaults round trip")
    }

    // MARK: - Section / front matter glue

    func testCurrentSectionBoundariesUsesActiveDocument() throws {
        let document = Document(
            sourceKind: "epub",
            sections: [
                Section(id: "ch1", title: "One", kind: .chapter, text: "alpha beta gamma delta epsilon zeta eta theta iota"),
                Section(id: "ch2", title: "Two", kind: .chapter, text: "kappa lambda mu nu xi omicron pi rho sigma"),
            ]
        )
        let store = makeStore()
        store.addArticle(document: document, source: "EPUB")

        let boundaries = store.currentSectionBoundaries()
        XCTAssertEqual(boundaries.count, 2)
        XCTAssertEqual(boundaries[0].sectionId, "ch1")
        XCTAssertEqual(boundaries[1].sectionId, "ch2")
        XCTAssertGreaterThan(boundaries[1].tokenStart, 0)
    }

    func testCurrentFrontMatterDetectionUsesActiveDocument() {
        let document = Document(
            sourceKind: "epub",
            sections: [
                Section(id: "cov", title: "封面", kind: .chapter, text: "封面"),
                Section(id: "ch1", title: "第一章", kind: .chapter, text: Self.longBody(2_000)),
            ]
        )
        let store = makeStore()
        store.addArticle(document: document, source: "EPUB")

        let fm = store.currentFrontMatterDetection()
        XCTAssertNotNil(fm)
        XCTAssertEqual(fm?.firstChapterSectionIndex, 1)
        XCTAssertEqual(fm?.frontMatterSectionIds, ["cov"])
        XCTAssertTrue(fm?.hasSkippableFrontMatter ?? false)
    }

    // MARK: - User dictionary

    func testUserDictionaryStartsEmptyAndAccepts新詞() {
        let store = makeStore()
        XCTAssertEqual(store.userDictionary, [])

        store.addToUserDictionary("黃士旗")
        store.addToUserDictionary("星巴克")
        XCTAssertEqual(store.userDictionary, ["黃士旗", "星巴克"])
    }

    func testUserDictionaryDeduplicatesAndTrimsInput() {
        let store = makeStore()
        store.addToUserDictionary("  黃士旗  ")
        store.addToUserDictionary("黃士旗")
        store.addToUserDictionary("")
        XCTAssertEqual(store.userDictionary, ["黃士旗"])
    }

    func testUserDictionaryAffectsCurrentArticleTokens() {
        // Picking an input the ChunkShaper alone can't fix: ICU splits
        // 張三 / 王 / 老師 into a 2-char chunk + a single Han + a 2-char
        // chunk. The shaper has to guess where the boundary belongs and
        // absorbs 王 backward into 張三 (= 張三王 | 老師). Adding 王老師
        // to the dictionary tells the merge step to fuse 王 + 老師 *before*
        // the shaper sees the input, fixing the chunk.
        let store = makeStore()
        store.addDraftArticle(text: "張三王老師很嚴格,蔡英文也是。", title: "Note")

        // Without dictionary, the 王 lands with the wrong neighbour.
        XCTAssertTrue(store.currentTokens.contains("張三王"))
        XCTAssertFalse(store.currentTokens.contains("王老師"))

        store.addToUserDictionary("王老師")

        // Cache invalidated; the new tokens reflect the dictionary.
        XCTAssertFalse(store.currentTokens.contains("張三王"))
        XCTAssertTrue(store.currentTokens.contains("王老師"))
    }

    func testUserDictionaryRoundTripsThroughUserDefaults() {
        do {
            let store = makeStore()
            store.addToUserDictionary("黃士旗")
            store.addToUserDictionary("陽明山")
        }
        let reborn = makeStore()
        XCTAssertEqual(reborn.userDictionary, ["黃士旗", "陽明山"])
    }

    func testRemoveAndClearUserDictionary() {
        let store = makeStore()
        store.addToUserDictionary("黃士旗")
        store.addToUserDictionary("星巴克")

        store.removeFromUserDictionary("黃士旗")
        XCTAssertEqual(store.userDictionary, ["星巴克"])

        store.clearUserDictionary()
        XCTAssertEqual(store.userDictionary, [])
    }

    // MARK: - Helpers

    private static func longBody(_ words: Int) -> String {
        Array(repeating: "alpha", count: words).joined(separator: " ")
    }
}

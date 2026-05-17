import XCTest
@testable import FastReadCore

// End-to-end EPUB ingest test against a real local EPUB. Drives the
// full pipeline that the iOS app uses for an EPUB pick:
//   file bytes -> EpubImporter -> Document
//                 -> Document.flattenText -> RSVPEngine.tokenize
//                 -> simulated RSVP playback
//                 -> StorageMigration round-trip
//
// Skipped if the EPUB is not present so CI and other machines stay green.
// Override the path via FASTREAD_E2E_EPUB.
final class EpubE2ETests: XCTestCase {
    // Resolution order:
    //   1. FASTREAD_E2E_EPUB (absolute or ~ expanded)
    //   2. <repoRoot>/test.epub (gitignored convenience copy)
    // Skips with a hint if no local fixture is readable.
    private static let defaultPath: String = resolveDefaultPath()

    private static func repoRoot(file: StaticString = #filePath) -> URL {
        URL(fileURLWithPath: String(describing: file))
            .deletingLastPathComponent() // FastReadCoreTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // <repo>
    }

    private static func resolveDefaultPath() -> String {
        if let override = ProcessInfo.processInfo.environment["FASTREAD_E2E_EPUB"], !override.isEmpty {
            return (override as NSString).expandingTildeInPath
        }
        let local = repoRoot().appendingPathComponent("test.epub").path
        if FileManager.default.isReadableFile(atPath: local) {
            return local
        }
        return local
    }

    private static let epubAvailable: Bool = FileManager.default.isReadableFile(atPath: defaultPath)

    private func loadDocument(file: StaticString = #filePath, line: UInt = #line) throws -> Document {
        let url = URL(fileURLWithPath: Self.defaultPath)
        let data = try Data(contentsOf: url)
        return try EpubImporter().import(data: data, options: ImportOptions())
    }

    private func skipIfMissing() throws {
        try XCTSkipUnless(
            Self.epubAvailable,
            """
            EPUB not readable at \(Self.defaultPath).
            • Drop a copy at <repoRoot>/test.epub — gitignored, picked up automatically.
            • Or override the default with FASTREAD_E2E_EPUB=/absolute/path/to/book.epub.
            """
        )
    }

    func testEpubImportsAsMultiChapterDocument() throws {
        try skipIfMissing()
        let document = try loadDocument()

        XCTAssertEqual(document.sourceKind, "epub", "sourceKind should be epub")
        XCTAssertFalse(document.title.isEmpty, "expected non-empty title, got: \(document.title)")
        XCTAssertGreaterThan(document.sections.count, 1, "expected a multi-chapter document, got \(document.sections.count) section(s)")

        let titledSections = document.sections.filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        XCTAssertGreaterThan(titledSections.count, 0, "expected at least one section to have a title from the TOC")

        let flat = Document.flattenText(document)
        XCTAssertGreaterThan(flat.count, 50_000, "expected > 50k chars of body text, got \(flat.count)")
        XCTAssertTrue(RSVPEngine.containsCJK(flat), "expected CJK content in a Traditional Chinese novel")
    }

    func testTokenizationYieldsReasonableReadingWorkload() throws {
        try skipIfMissing()
        let document = try loadDocument()
        let tokens = RSVPEngine.tokenize(Document.flattenText(document))
        XCTAssertGreaterThan(tokens.count, 5_000, "expected > 5k tokens for a novel, got \(tokens.count)")

        let minutes = RSVPEngine.estimateMinutes(wordCount: tokens.count, wpm: 450.0)
        XCTAssertGreaterThan(minutes, 30, "expected estimated read time > 30min at 450wpm, got \(minutes)")
        XCTAssertLessThan(minutes, 2_000, "estimated read time should not be absurd, got \(minutes)")
    }

    func testSectionBoundariesAreMonotonicAndCoverAllTokens() throws {
        try skipIfMissing()
        let document = try loadDocument()
        let boundaries = Document.sectionBoundaries(document)

        XCTAssertEqual(boundaries.count, document.sections.count, "one boundary per section")
        XCTAssertEqual(boundaries.first?.tokenStart, 0, "first section starts at 0")

        for i in 0..<boundaries.count {
            let b = boundaries[i]
            XCTAssertGreaterThanOrEqual(b.tokenEnd, b.tokenStart, "section \(b.sectionId) tokenEnd >= tokenStart")
            if i > 0 {
                XCTAssertEqual(b.tokenStart, boundaries[i - 1].tokenEnd, "section \(b.sectionId) starts where \(boundaries[i - 1].sectionId) ended")
            }
        }

        let totalTokens = RSVPEngine.tokenize(Document.flattenText(document)).count
        XCTAssertEqual(boundaries.last?.tokenEnd, totalTokens, "last boundary ends at total token count")
    }

    func testSimulatedRSVPPlaybackStaysInSaneBounds() throws {
        try skipIfMissing()
        let document = try loadDocument()
        let tokens = RSVPEngine.tokenize(Document.flattenText(document))
        let sampleSize = min(500, tokens.count)
        let wpm = 450
        var totalMs = 0
        for i in 0..<sampleSize {
            let token = tokens[i]
            let split = RSVPEngine.splitForFocus(token)
            XCTAssertNotNil(split.before)
            XCTAssertNotNil(split.focus)
            XCTAssertNotNil(split.after)
            let ms = RSVPEngine.duration(for: token, wpm: Double(wpm), punctuationPause: true)
            XCTAssertGreaterThanOrEqual(ms, 50, "duration for \(token) was \(ms)ms, below floor")
            XCTAssertLessThanOrEqual(ms, 2_000, "duration for \(token) was \(ms)ms, above ceiling")
            totalMs += ms
        }
        let avgMs = Double(totalMs) / Double(sampleSize)
        XCTAssertGreaterThanOrEqual(avgMs, 60, "average duration \(avgMs)ms below floor")
        XCTAssertLessThanOrEqual(avgMs, 600, "average duration \(avgMs)ms above ceiling")
    }

    func testFrontMatterDetectionLandsOnFirstRealChapter() throws {
        try skipIfMissing()
        let document = try loadDocument()
        let fm = Document.detectFrontMatter(document)

        XCTAssertTrue(fm.hasSkippableFrontMatter, "expected the EPUB to have at least one front-matter section")
        XCTAssertGreaterThan(fm.frontMatterSectionIds.count, 0, "expected non-empty front matter list")
        if let firstChapterIndex = fm.firstChapterSectionIndex {
            XCTAssertLessThan(firstChapterIndex, document.sections.count, "first chapter index in bounds")
            // Sanity: the chapter we land on should have substantive content.
            let firstRealSection = document.sections[firstChapterIndex]
            XCTAssertGreaterThan(firstRealSection.text.count, 1_000, "first real chapter should have > 1k chars")
        } else {
            XCTFail("detectFrontMatter returned nil index for a known multi-chapter book")
        }
    }

    func testStorageMigrationRoundTripPreservesDocument() throws {
        try skipIfMissing()
        let document = try loadDocument()
        let flat = Document.flattenText(document)

        // Build a synthetic legacy v1 article (text-only) and run it through
        // StorageMigration.documentFromLegacy. The v1 -> v2 migration wraps
        // the flat text blob in a single body Section.
        let legacy = ReadingArticle(
            id: "legacy-1",
            title: document.title,
            source: "EPUB",
            sourceURL: nil,
            author: "You",
            date: "2026-05-08",
            readTime: "0 min",
            lede: "",
            tag: "Reading now",
            text: flat,
            progress: 0,
            wordIndex: 0,
            timesOpened: 1,
            isFinished: false
        )
        let migratedDoc = StorageMigration.documentFromLegacy(article: legacy)
        XCTAssertEqual(migratedDoc.sections.count, 1, "v1 -> v2 wraps text into a single body section")
        XCTAssertEqual(migratedDoc.sections[0].kind, .body)
        XCTAssertEqual(migratedDoc.sections[0].text, flat, "no text loss across migration")

        // Already-v2 articles (with the EPUB-built Document) round-trip
        // through Codable unchanged.
        let v2 = ReadingArticle(
            id: "epub-1",
            title: document.title,
            source: "EPUB",
            sourceURL: nil,
            author: "",
            date: "2026-05-08",
            readTime: "0 min",
            lede: "",
            tag: "Reading now",
            document: document,
            progress: 0,
            wordIndex: 0,
            timesOpened: 1,
            isFinished: false
        )
        let reEncoded = try JSONEncoder().encode(v2)
        let reDecoded = try JSONDecoder().decode(ReadingArticle.self, from: reEncoded)
        XCTAssertEqual(reDecoded.document, document)
    }
}

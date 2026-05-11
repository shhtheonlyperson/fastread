import XCTest
@testable import FastReadCore

final class ReadingArticleCodableTests: XCTestCase {
    func testRoundTripPreservesAllFields() throws {
        let createdAt = Date(timeIntervalSince1970: 1_714_000_000)
        let lastOpenedAt = Date(timeIntervalSince1970: 1_714_500_000)
        let finishedAt = Date(timeIntervalSince1970: 1_715_000_000)

        let original = ReadingArticle(
            id: "article-roundtrip-1",
            title: "Round-Trip Title 你好",
            source: "example.com",
            sourceURL: "https://example.com/post",
            author: "Ada Lovelace",
            date: "May 7, 2026",
            createdAt: createdAt,
            lastOpenedAt: lastOpenedAt,
            finishedAt: finishedAt,
            readTime: "5 min",
            lede: "Lede paragraph with CJK 中文 and emoji 📚.",
            tag: "readingNow",
            text: "Body text — supports em-dash, NBSP\u{00A0}runs, and 漢字.",
            progress: 0.75,
            wordIndex: 123,
            timesOpened: 4,
            isFinished: true
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ReadingArticle.self, from: data)

        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.title, original.title)
        XCTAssertEqual(decoded.source, original.source)
        XCTAssertEqual(decoded.sourceURL, original.sourceURL)
        XCTAssertEqual(decoded.author, original.author)
        XCTAssertEqual(decoded.date, original.date)
        XCTAssertEqual(decoded.createdAt, original.createdAt)
        XCTAssertEqual(decoded.lastOpenedAt, original.lastOpenedAt)
        XCTAssertEqual(decoded.finishedAt, original.finishedAt)
        XCTAssertEqual(decoded.readTime, original.readTime)
        XCTAssertEqual(decoded.lede, original.lede)
        XCTAssertEqual(decoded.tag, original.tag)
        XCTAssertEqual(decoded.text, original.text)
        XCTAssertEqual(decoded.progress, original.progress)
        XCTAssertEqual(decoded.wordIndex, original.wordIndex)
        XCTAssertEqual(decoded.timesOpened, original.timesOpened)
        XCTAssertEqual(decoded.isFinished, original.isFinished)
    }

    func testRoundTripWithNilOptionals() throws {
        let original = ReadingArticle(
            id: "article-nils",
            title: "Nil Optionals",
            source: "Clipboard",
            sourceURL: nil,
            author: "You",
            date: "May 7, 2026",
            createdAt: nil,
            lastOpenedAt: nil,
            finishedAt: nil,
            readTime: "1 min",
            lede: "",
            tag: "readingNow",
            text: "Short body.",
            progress: 0.0,
            wordIndex: 0,
            timesOpened: 1,
            isFinished: false
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ReadingArticle.self, from: data)

        XCTAssertEqual(decoded, original)
        XCTAssertNil(decoded.sourceURL)
        XCTAssertNil(decoded.createdAt)
        XCTAssertNil(decoded.lastOpenedAt)
        XCTAssertNil(decoded.finishedAt)
    }

    func testRoundTripPreservesPersistedTokens() throws {
        let original = ReadingArticle(
            id: "article-tokens",
            title: "Persisted tokens",
            source: "Clipboard",
            author: "You",
            date: "May 11, 2026",
            readTime: "1 min",
            lede: "...",
            tag: "Reading now",
            text: "黃士旗 去吃飯。",
            progress: 0,
            wordIndex: 0,
            timesOpened: 1,
            isFinished: false,
            tokens: ["黃士旗", "去吃飯。"],
            tokenizerVersion: RSVPEngine.version
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ReadingArticle.self, from: data)

        XCTAssertEqual(decoded.tokens, ["黃士旗", "去吃飯。"])
        XCTAssertEqual(decoded.tokenizerVersion, RSVPEngine.version)
        XCTAssertEqual(decoded, original)
    }

    func testDecodesLegacyV0Fixture() throws {
        guard let url = Bundle.module.url(
            forResource: "legacy-article-v0",
            withExtension: "json",
            subdirectory: "Fixtures"
        ) else {
            XCTFail("legacy-article-v0.json fixture not found in test bundle")
            return
        }
        let data = try Data(contentsOf: url)
        let article = try JSONDecoder().decode(ReadingArticle.self, from: data)

        XCTAssertEqual(article.id, "article-1714000000000")
        XCTAssertEqual(article.title, "Legacy Article")
        XCTAssertEqual(article.source, "example.com")
        XCTAssertNil(article.sourceURL)
        XCTAssertEqual(article.author, "You")
        XCTAssertEqual(article.date, "Apr 25, 2024")
        XCTAssertNil(article.createdAt)
        XCTAssertNil(article.lastOpenedAt)
        XCTAssertNil(article.finishedAt)
        XCTAssertEqual(article.readTime, "3 min")
        XCTAssertEqual(article.tag, "readingNow")
        XCTAssertEqual(article.progress, 0.42, accuracy: 1e-9)
        XCTAssertEqual(article.wordIndex, 17)
        XCTAssertEqual(article.timesOpened, 2)
        XCTAssertFalse(article.isFinished)
        XCTAssertTrue(article.text.contains("legacy reading article"))
        // Legacy v0 records pre-date the persisted-tokens fields, so the
        // decoder should leave both slots nil for ReadingStore to backfill.
        XCTAssertNil(article.tokens)
        XCTAssertNil(article.tokenizerVersion)
    }
}

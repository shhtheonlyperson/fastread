import XCTest
@testable import FastReadCore

final class StorageMigrationTests: XCTestCase {
    private func loadLegacyFixture() throws -> Data {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "legacy-store-v1", withExtension: "json", subdirectory: "Fixtures")
        )
        return try Data(contentsOf: url)
    }

    func testDocumentFromLegacyWrapsTextIntoSingleBodySection() {
        let article = ReadingArticle(
            id: "article-1",
            title: "Hello",
            source: "Pasted text",
            sourceURL: "https://example.com/x",
            author: "You",
            date: "May 1, 2026",
            createdAt: nil,
            lastOpenedAt: nil,
            finishedAt: nil,
            readTime: "1 min",
            lede: "Hello.",
            tag: "Saved",
            text: "Hello world.\n\nSecond paragraph.",
            progress: 0,
            wordIndex: 0,
            timesOpened: 0,
            isFinished: false
        )

        let document = StorageMigration.documentFromLegacy(article: article)
        XCTAssertEqual(document.title, "Hello")
        XCTAssertEqual(document.author, "You")
        XCTAssertEqual(document.sourceUrl, "https://example.com/x")
        XCTAssertEqual(document.sourceKind, "text")
        XCTAssertEqual(document.sections.count, 1)
        XCTAssertEqual(document.sections[0].id, "body")
        XCTAssertEqual(document.sections[0].kind, .body)
        XCTAssertEqual(document.sections[0].text, article.text)
        XCTAssertEqual(Document.flattenText(document), article.text)
    }

    func testDocumentFromLegacyHandlesMissingSourceURL() {
        let article = ReadingArticle(
            id: "article-2",
            title: "No URL",
            source: "Pasted text",
            sourceURL: nil,
            author: "You",
            date: "May 1, 2026",
            readTime: "1 min",
            lede: "...",
            tag: "Saved",
            text: "Body.",
            progress: 0,
            wordIndex: 0,
            timesOpened: 0,
            isFinished: false
        )

        let document = StorageMigration.documentFromLegacy(article: article)
        XCTAssertEqual(document.sourceUrl, "")
    }

    func testLoadAndMigrateLegacyV1FixtureProducesDocumentPerArticle() throws {
        let data = try loadLegacyFixture()
        let result = try XCTUnwrap(StorageMigration.loadAndMigrate(legacyData: data))

        XCTAssertEqual(result.articles.count, 2)
        XCTAssertEqual(result.documents.count, 2)

        for article in result.articles {
            let document = try XCTUnwrap(result.documents[article.id])
            XCTAssertEqual(document.sections.count, 1)
            XCTAssertEqual(document.sections[0].id, "body")
            XCTAssertEqual(document.sections[0].kind, .body)
            XCTAssertEqual(document.sections[0].text, article.text)
            XCTAssertEqual(Document.flattenText(document), article.text)
        }

        let cjk = try XCTUnwrap(result.articles.first { $0.id == "article-1714000000001" })
        let cjkDoc = try XCTUnwrap(result.documents[cjk.id])
        XCTAssertEqual(cjkDoc.sections[0].text, "閱讀是一種技能。")
        XCTAssertEqual(cjkDoc.title, "中文文章")
    }

    func testMigrateLegacyArticlesIsIdempotent() throws {
        let data = try loadLegacyFixture()
        let articles = try JSONDecoder().decode([ReadingArticle].self, from: data)
        let first = StorageMigration.migrateLegacyArticles(articles)
        let second = StorageMigration.migrateLegacyArticles(articles)
        XCTAssertEqual(first, second)
    }

    func testLoadAndMigrateReturnsNilForUnrelatedJSON() {
        let data = "{\"unrelated\":true}".data(using: .utf8)!
        XCTAssertNil(StorageMigration.loadAndMigrate(legacyData: data))
    }
}

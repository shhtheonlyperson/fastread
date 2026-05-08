import XCTest
@testable import FastReadCore

// Replays the committed HTML fixtures through the Swift HtmlAdapter and pins
// the title, reading-unit count, and head/tail snippets of the extracted body
// text. Mirrors what was previously asserted by test/article-extract.golden
// .test.mjs on the JS side; the JS reference implementation has been retired
// so this is now the canonical regression gate for ArticleTextExtractor.
final class HtmlGoldenTests: XCTestCase {
    private struct ExpectedFixture: Codable {
        let title: String
        let wordCount: Int
        let head: String
        let tail: String
    }

    // Run with `FASTREAD_UPDATE_GOLDENS=1 swift test --filter HtmlGoldenTests`
    // to rewrite the *.expected.json fixtures from Swift's current output
    // when extraction behavior intentionally changes. Tests still pass on
    // that run; subsequent runs compare against the fresh snapshots.
    private static let shouldUpdateGoldens =
        ProcessInfo.processInfo.environment["FASTREAD_UPDATE_GOLDENS"] == "1"

    private static let htmlFixtures = [
        "01-clean-article",
        "02-jsonld-article",
        "03-cjk-article",
        "04-paywalled-chrome",
        "06-no-semantic-tags",
    ]

    private func fixtureURL(_ name: String, ext: String) throws -> URL {
        guard let url = Bundle.module.url(
            forResource: name,
            withExtension: ext,
            subdirectory: "Fixtures/articles"
        ) else {
            XCTFail("Missing fixture \(name).\(ext)")
            throw ImporterError.invalidInput("missing fixture \(name).\(ext)")
        }
        return url
    }

    private func loadExpected(_ name: String) throws -> ExpectedFixture {
        // Files are committed as "<name>.expected.json" so the filename is
        // "<name>.expected" with extension "json" from Bundle's perspective.
        let url = try fixtureURL("\(name).expected", ext: "json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(ExpectedFixture.self, from: data)
    }

    // Resolves the source-repo path for the .expected.json sibling of a
    // fixture so the update mode can write back into the working tree
    // rather than the test bundle.
    private func sourceExpectedURL(_ name: String, file: StaticString = #filePath) -> URL {
        let testFile = URL(fileURLWithPath: String(describing: file))
        let repoRoot = testFile
            .deletingLastPathComponent() // Tests/FastReadCoreTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // <repo>
        return repoRoot
            .appendingPathComponent("Tests/Fixtures/articles")
            .appendingPathComponent("\(name).expected.json")
    }

    private func snapshot(text: String, title: String) -> ExpectedFixture {
        ExpectedFixture(
            title: title,
            wordCount: RSVPEngine.countReadingUnits(text),
            head: String(text.prefix(200)),
            tail: String(text.suffix(200))
        )
    }

    private func writeSnapshot(_ snap: ExpectedFixture, name: String) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snap)
        try data.write(to: sourceExpectedURL(name))
    }

    func testHtmlGoldenFixturesMatchExpectedSnapshot() throws {
        let adapter = HtmlAdapter()
        for name in Self.htmlFixtures {
            let html = try String(contentsOf: try fixtureURL(name, ext: "html"), encoding: .utf8)
            let doc = try adapter.import(html, options: ImportOptions(sourceUrl: "https://example.test/\(name)"))
            let text = Document.flattenText(doc)
            let actual = snapshot(text: text, title: doc.title)

            if Self.shouldUpdateGoldens {
                try writeSnapshot(actual, name: name)
                continue
            }

            let expected = try loadExpected(name)
            XCTAssertEqual(actual.title, expected.title, "[\(name)] title")
            XCTAssertEqual(actual.wordCount, expected.wordCount, "[\(name)] reading-unit count")
            XCTAssertEqual(actual.head, expected.head, "[\(name)] first 200 chars of normalized text drifted")
            XCTAssertEqual(actual.tail, expected.tail, "[\(name)] last 200 chars of normalized text drifted")
        }
    }

    func testPlaintextFixtureMatchesExpectedSnapshot() throws {
        let url = try fixtureURL("05-plaintext", ext: "txt")
        let raw = try String(contentsOf: url, encoding: .utf8)
        let title: String
        if Self.shouldUpdateGoldens {
            title = (try? loadExpected("05-plaintext").title) ?? "Plain Note"
        } else {
            title = try loadExpected("05-plaintext").title
        }
        let doc = try PlainTextAdapter().import(raw, options: ImportOptions(title: title))
        let text = Document.flattenText(doc)
        let actual = snapshot(text: text, title: doc.title)

        if Self.shouldUpdateGoldens {
            try writeSnapshot(actual, name: "05-plaintext")
            return
        }

        let expected = try loadExpected("05-plaintext")
        XCTAssertEqual(actual.title, expected.title, "[05-plaintext] title")
        XCTAssertEqual(actual.wordCount, expected.wordCount, "[05-plaintext] reading-unit count")
        XCTAssertEqual(actual.head, expected.head, "[05-plaintext] head")
        XCTAssertEqual(actual.tail, expected.tail, "[05-plaintext] tail")
    }
}

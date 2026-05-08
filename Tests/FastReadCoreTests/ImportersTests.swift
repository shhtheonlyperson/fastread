import XCTest
@testable import FastReadCore

final class ImportersTests: XCTestCase {
    private let htmlFixtures = [
        "01-clean-article",
        "02-jsonld-article",
        "03-cjk-article",
        "04-paywalled-chrome",
        "06-no-semantic-tags",
    ]

    private func loadFixture(_ name: String, ext: String) throws -> String {
        guard let url = Bundle.module.url(
            forResource: name,
            withExtension: ext,
            subdirectory: "Fixtures/articles"
        ) else {
            XCTFail("Missing fixture \(name).\(ext)")
            throw ImporterError.invalidInput("missing fixture")
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    func testHtmlAdapterRunsOnGoldenCorpus() throws {
        let adapter = HtmlAdapter()
        for name in htmlFixtures {
            let html = try loadFixture(name, ext: "html")
            let expectedText = ArticleTextExtractor.readableText(from: html)
            let doc = try adapter.import(html, options: ImportOptions(sourceUrl: "https://example.test/\(name)"))

            XCTAssertEqual(doc.sourceKind, "html", "\(name): sourceKind")
            XCTAssertEqual(doc.sections.count, 1, "\(name): single section")
            XCTAssertEqual(doc.sections[0].id, "body", "\(name): section id")
            XCTAssertEqual(doc.sections[0].kind, .body, "\(name): section kind")
            XCTAssertEqual(Document.flattenText(doc), expectedText, "\(name): flattenText mirrors ArticleTextExtractor.readableText")
            XCTAssertFalse(Document.flattenText(doc).isEmpty, "\(name): flatten non-empty")
            XCTAssertEqual(doc.sourceUrl, "https://example.test/\(name)", "\(name): sourceUrl preserved")
        }
    }

    func testPlainTextAdapterRunsOnPlaintextFixture() throws {
        let raw = try loadFixture("05-plaintext", ext: "txt")
        let doc = try PlainTextAdapter().import(raw, options: ImportOptions(title: "Plain Note"))
        XCTAssertEqual(doc.sourceKind, "text")
        XCTAssertEqual(doc.title, "Plain Note")
        XCTAssertEqual(doc.sections.count, 1)
        XCTAssertEqual(doc.sections[0].id, "body")
        XCTAssertEqual(doc.sections[0].kind, .body)
        XCTAssertEqual(Document.flattenText(doc), ArticleTextExtractor.normalize(raw))
        XCTAssertFalse(Document.flattenText(doc).isEmpty)
    }

    func testRegistryDispatchesByKind() throws {
        let registry = ImporterRegistry.shared
        let html = try loadFixture("01-clean-article", ext: "html")
        let doc = try registry.importDocument(kind: .html, input: html)
        XCTAssertEqual(doc.sourceKind, "html")
        XCTAssertEqual(Document.flattenText(doc), ArticleTextExtractor.readableText(from: html))

        let textDoc = try registry.importDocument(kind: .text, input: "hello   world")
        XCTAssertEqual(Document.flattenText(textDoc), "hello world")
    }

    func testRegistryUnknownKindThrows() {
        let registry = ImporterRegistry()
        registry.register(PlainTextAdapter())
        XCTAssertThrowsError(try registry.importDocument(kind: .html, input: "<p>x</p>")) { err in
            XCTAssertEqual(err as? ImporterError, .unknownKind("html"))
        }
    }

    func testHtmlAdapterCanHandleDetectsTags() {
        let adapter = HtmlAdapter()
        XCTAssertTrue(adapter.canHandle("<p>hi</p>"))
        XCTAssertTrue(adapter.canHandle("<!DOCTYPE html><html></html>"))
        XCTAssertFalse(adapter.canHandle("just a plain string with no tags"))
    }
}

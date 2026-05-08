import XCTest
@testable import FastReadCore

/// Mirrors the FastReadApp `ReadingStore.addDraftArticle` flow at the
/// FastReadCore level: route input through `ImporterRegistry.shared` and
/// persist the resulting `Document` on a `ReadingArticle`. The Xcode app
/// target is not visible to SwiftPM tests, so we reproduce the registry
/// integration here.
final class ReadingStoreImportTests: XCTestCase {
    private func makeArticle(from document: Document, source: String, sourceURL: String? = nil) -> ReadingArticle {
        let flattened = Document.flattenText(document)
        let tokens = RSVPEngine.tokenize(flattened)
        let title = document.title.isEmpty ? "Pasted text" : document.title
        let author = document.author.isEmpty ? "You" : document.author
        return ReadingArticle(
            id: "draft-test-\(UUID().uuidString)",
            title: title,
            source: source,
            sourceURL: sourceURL,
            author: author,
            date: "May 7, 2026",
            createdAt: Date(),
            lastOpenedAt: Date(),
            finishedAt: nil,
            readTime: "1 min",
            lede: String(flattened.prefix(40)),
            tag: "Reading now",
            document: document,
            progress: 0,
            wordIndex: 0,
            timesOpened: 1,
            isFinished: false
        )
    }

    func testPasteTextRoutesThroughRegistry() throws {
        let pasted = "  Hello world.\n\nThis is a paste test. \n"
        let document = try ImporterRegistry.shared.importDocument(
            kind: .text,
            input: pasted,
            options: ImportOptions(sourceUrl: "", title: "Pasted text", author: "You")
        )

        XCTAssertEqual(document.sourceKind, "text")
        XCTAssertEqual(document.sections.count, 1)
        XCTAssertEqual(document.sections[0].kind, .body)
        XCTAssertEqual(document.sections[0].id, "body")
        XCTAssertTrue(document.sections[0].text.contains("Hello world."))
        XCTAssertTrue(document.sections[0].text.contains("This is a paste test."))

        let article = makeArticle(from: document, source: "Clipboard")

        XCTAssertEqual(article.document, document)
        XCTAssertEqual(article.text, Document.flattenText(document))
        XCTAssertFalse(article.text.isEmpty)
        XCTAssertEqual(article.title, "Pasted text")
        XCTAssertEqual(article.source, "Clipboard")
    }

    func testStubbedUrlFetchRoutesThroughRegistry() async throws {
        StubURLProtocol.respond(
            status: 200,
            headers: ["Content-Type": "text/html; charset=utf-8"],
            body: Data(#"""
            <!doctype html>
            <html>
              <head><title>Stub Fetch Article</title></head>
              <body>
                <article>
                  <h1>Stub Fetch Article</h1>
                  <p>The quick brown fox jumps over the lazy dog. Repeated content here so the word count is well over the minimum threshold.</p>
                  <p>A second paragraph adds even more readable body so the importer registry has plenty to work with.</p>
                </article>
              </body>
            </html>
            """#.utf8)
        )

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }

        let url = "https://example.com/stub-article"
        let result = try await ArticleLoader.fetch(urlString: url, session: session)

        XCTAssertGreaterThan(result.wordCount, 10)

        let document = try ImporterRegistry.shared.importDocument(
            kind: .text,
            input: result.text,
            options: ImportOptions(sourceUrl: result.url, title: result.title, author: "You")
        )
        let article = makeArticle(from: document, source: result.source, sourceURL: result.url)

        XCTAssertEqual(article.title, result.title)
        XCTAssertEqual(article.sourceURL, result.url)
        XCTAssertEqual(article.document.sections.count, 1)
        XCTAssertEqual(article.document.sections[0].kind, .body)
        XCTAssertTrue(article.text.contains("quick brown fox"))
        XCTAssertEqual(article.document.sourceUrl, result.url)
    }
}

private final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) private static var status: Int = 200
    nonisolated(unsafe) private static var headers: [String: String] = [:]
    nonisolated(unsafe) private static var body: Data = Data()
    private static let lock = NSLock()

    static func respond(status: Int, headers: [String: String], body: Data) {
        lock.lock(); defer { lock.unlock() }
        Self.status = status
        Self.headers = headers
        Self.body = body
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        let status = Self.status
        let headers = Self.headers
        let body = Self.body
        Self.lock.unlock()

        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://example.com")!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

import FastReadCore
import XCTest

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class UrlIngestTests: XCTestCase {
    private var session: URLSession!

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        session = URLSession(configuration: config)
    }

    override func tearDown() {
        StubURLProtocol.reset()
        session.invalidateAndCancel()
        session = nil
        super.tearDown()
    }

    func testFetchHappyPath() async throws {
        let html = Self.makeArticleHTML()
        StubURLProtocol.handler = { _ in
            (Self.httpResponse(status: 200, headers: ["Content-Type": "text/html; charset=utf-8"]), html.data(using: .utf8)!)
        }

        let result = try await ArticleLoader.fetch(urlString: "https://example.com/post", session: session)
        XCTAssertEqual(result.source, "example.com")
        XCTAssertEqual(result.url, "https://example.com/post")
        XCTAssertGreaterThan(result.wordCount, 20)
        XCTAssertTrue(result.text.contains("Lorem"))
        XCTAssertEqual(result.title, "Sample Article")
    }

    func test404ThrowsHttpError() async {
        StubURLProtocol.handler = { _ in
            (Self.httpResponse(status: 404, headers: ["Content-Type": "text/html"]), Data("not found".utf8))
        }

        await assertThrows(ArticleFetchError.httpError(404)) {
            _ = try await ArticleLoader.fetch(urlString: "https://example.com/missing", session: self.session)
        }
    }

    func testOversizedViaContentLength() async {
        StubURLProtocol.handler = { _ in
            (Self.httpResponse(status: 200, headers: [
                "Content-Type": "text/html",
                "Content-Length": "999999999",
            ]), Data("tiny".utf8))
        }

        await assertThrows(ArticleFetchError.oversized) {
            _ = try await ArticleLoader.fetch(urlString: "https://example.com/big", session: self.session, maxBytes: 1024)
        }
    }

    func testOversizedViaStreamedBody() async {
        let big = Data(repeating: 0x41, count: 4096)
        StubURLProtocol.handler = { _ in
            (Self.httpResponse(status: 200, headers: ["Content-Type": "text/html"]), big)
        }

        await assertThrows(ArticleFetchError.oversized) {
            _ = try await ArticleLoader.fetch(urlString: "https://example.com/big", session: self.session, maxBytes: 1024)
        }
    }

    func testUnsupportedContentType() async {
        StubURLProtocol.handler = { _ in
            (Self.httpResponse(status: 200, headers: ["Content-Type": "application/pdf"]), Data("%PDF-1.4".utf8))
        }

        await assertThrows(ArticleFetchError.unsupportedContentType("application/pdf")) {
            _ = try await ArticleLoader.fetch(urlString: "https://example.com/file.pdf", session: self.session)
        }
    }

    func testTimeout() async {
        StubURLProtocol.handler = { _ in
            throw URLError(.timedOut)
        }

        await assertThrows(ArticleFetchError.timeout) {
            _ = try await ArticleLoader.fetch(urlString: "https://example.com/slow", session: self.session)
        }
    }

    func testNonHttpSchemeThrowsInvalidURL() async {
        await assertThrows(ArticleFetchError.invalidURL) {
            _ = try await ArticleLoader.fetch(urlString: "ftp://example.com/file", session: self.session)
        }
    }

    // MARK: - Helpers

    private func assertThrows(
        _ expected: ArticleFetchError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ block: () async throws -> Void
    ) async {
        do {
            try await block()
            XCTFail("Expected \(expected) but no error was thrown", file: file, line: line)
        } catch let error as ArticleFetchError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Expected \(expected) but got \(error)", file: file, line: line)
        }
    }

    private static func httpResponse(status: Int, headers: [String: String], url: URL? = URL(string: "https://example.com/post")) -> HTTPURLResponse {
        HTTPURLResponse(url: url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
    }

    private static func makeArticleHTML() -> String {
        let body = String(repeating: "Lorem ipsum dolor sit amet consectetur adipiscing elit. ", count: 4)
        return """
        <html><head><title>Sample Article</title></head>
        <body><article><p>\(body)</p></article></body></html>
        """
    }
}

private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = (URLRequest) throws -> (HTTPURLResponse, Data)
    private static let lock = NSLock()
    nonisolated(unsafe) private static var _handler: Handler?

    static var handler: Handler? {
        get { lock.lock(); defer { lock.unlock() }; return _handler }
        set { lock.lock(); defer { lock.unlock() }; _handler = newValue }
    }

    static func reset() { handler = nil }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = StubURLProtocol.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

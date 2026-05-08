import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum ArticleFetchError: LocalizedError, Equatable, Sendable {
    case invalidURL
    case httpError(Int)
    case oversized
    case unsupportedContentType(String)
    case timeout

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            "Enter a valid http(s) URL."
        case let .httpError(status):
            "Fetch failed with HTTP \(status)."
        case .oversized:
            "Page is too large to extract."
        case let .unsupportedContentType(type):
            "Unsupported content type: \(type.isEmpty ? "unknown" : type)."
        case .timeout:
            "Fetching the page timed out."
        }
    }
}

public struct ArticleFetchResult: Equatable, Sendable {
    public var title: String
    public var source: String
    public var url: String
    public var text: String
    public var wordCount: Int

    public init(title: String, source: String, url: String, text: String, wordCount: Int) {
        self.title = title
        self.source = source
        self.url = url
        self.text = text
        self.wordCount = wordCount
    }
}

public protocol URLDataFetching: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: URLDataFetching {}

public enum ArticleLoader {
    public static let defaultMaxBytes = 6 * 1024 * 1024

    public static func fetch(
        urlString: String,
        session: URLDataFetching = URLSession.shared,
        maxBytes: Int = defaultMaxBytes
    ) async throws -> ArticleFetchResult {
        guard let normalized = SourceInputClassifier.normalizedURLString(from: urlString) else {
            throw ArticleFetchError.invalidURL
        }
        guard let url = URL(string: normalized), let scheme = url.scheme,
              ["http", "https"].contains(scheme.lowercased()) else {
            throw ArticleFetchError.invalidURL
        }

        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("text/html,application/xhtml+xml,text/plain;q=0.9,*/*;q=0.2", forHTTPHeaderField: "Accept")
        request.setValue("Mozilla/5.0 JustRead iOS reader", forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError where urlError.code == .timedOut || urlError.code == .cancelled {
            throw ArticleFetchError.timeout
        } catch is CancellationError {
            throw ArticleFetchError.timeout
        }

        guard let http = response as? HTTPURLResponse else {
            throw ArticleFetchError.invalidURL
        }
        if !(200..<300).contains(http.statusCode) {
            throw ArticleFetchError.httpError(http.statusCode)
        }

        if let lengthHeader = http.value(forHTTPHeaderField: "Content-Length"),
           let declared = Int(lengthHeader.trimmingCharacters(in: .whitespaces)),
           declared > maxBytes {
            throw ArticleFetchError.oversized
        }
        if data.count > maxBytes {
            throw ArticleFetchError.oversized
        }

        let contentType = http.value(forHTTPHeaderField: "Content-Type") ?? ""
        if !contentType.isEmpty,
           contentType.range(of: #"text/html|application/xhtml\+xml|text/plain"#, options: [.regularExpression, .caseInsensitive]) == nil {
            throw ArticleFetchError.unsupportedContentType(contentType)
        }

        let html = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""
        let text = ArticleTextExtractor.readableText(from: html)
        let words = RSVPEngine.tokenize(text)

        let title = ArticleTextExtractor.extractTitle(from: html) ?? url.host(percentEncoded: false) ?? "Fetched article"
        return ArticleFetchResult(
            title: title,
            source: url.host(percentEncoded: false) ?? "Web",
            url: http.url?.absoluteString ?? url.absoluteString,
            text: text,
            wordCount: words.count
        )
    }
}

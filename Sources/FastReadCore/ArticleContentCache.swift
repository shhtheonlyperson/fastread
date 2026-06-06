import Foundation
import OSLog

/// Tokenization + document-metadata memo layer extracted from ReadingStore.
///
/// Tokens and section boundaries both depend on the user dictionary, so it is
/// passed in per call rather than owned here — the cache stays a pure memo of
/// "given this article (and dictionary), here are its tokens / boundaries."
/// ReadingStore drives invalidation when the dictionary or an article changes.
final class ArticleContentCache {
    struct DocumentMetadataEntry {
        var boundaries: [Document.SectionBoundary]
        var frontMatter: Document.FrontMatterDetection
    }

    /// In-memory fallback for articles whose persisted `tokens` slot is nil
    /// (legacy upgrade, or after a user-dictionary change). Lookups hit
    /// `article.tokens` first; this dict only matters until the next mutation
    /// re-persists tokens on the article record.
    private var tokenCache: [String: [String]] = [:]
    private var documentMetadataCache: [String: DocumentMetadataEntry] = [:]

    func tokens(for article: ReadingArticle, userDictionary: [String]) -> [String] {
        // Fast path: the article carries its tokens from import / last
        // mutation and the recorded version still matches the engine.
        if let persisted = article.tokens,
           let recorded = article.tokenizerVersion,
           recorded == RSVPEngine.version {
            return persisted
        }
        // Memo path: read-only callers (list rows, lede previews) hit here on
        // a legacy upgrade or right after an invalidate. `ensureTokens`
        // re-persists tokens on the next mutation.
        if let cached = tokenCache[article.id] {
            return cached
        }
        let tokens = PerformanceTrace.measure("Tokenize Article") {
            RSVPEngine.tokenize(article.text, userDictionary: userDictionary)
        }
        tokenCache[article.id] = tokens
        return tokens
    }

    @discardableResult
    func ensureTokens(for article: inout ReadingArticle, userDictionary: [String]) -> [String] {
        if let persisted = article.tokens,
           let recorded = article.tokenizerVersion,
           recorded == RSVPEngine.version {
            return persisted
        }
        let fresh = PerformanceTrace.measure("Tokenize Article") {
            RSVPEngine.tokenize(article.text, userDictionary: userDictionary)
        }
        article.tokens = fresh
        article.tokenizerVersion = RSVPEngine.version
        tokenCache[article.id] = fresh
        return fresh
    }

    func documentMetadata(for article: ReadingArticle, userDictionary: [String]) -> DocumentMetadataEntry {
        if let cached = documentMetadataCache[article.id] {
            return cached
        }
        let metadata = PerformanceTrace.measure("Build Document Metadata") {
            let boundaries = Document.sectionBoundaries(article.document, userDictionary: userDictionary)
            return DocumentMetadataEntry(
                boundaries: boundaries,
                frontMatter: Document.detectFrontMatter(article.document, boundaries: boundaries)
            )
        }
        documentMetadataCache[article.id] = metadata
        return metadata
    }

    /// Seed the token memo for a freshly-created article so the first read
    /// doesn't re-tokenize.
    func store(tokens: [String], for id: String) {
        tokenCache[id] = tokens
    }

    /// Drop everything — used when the user dictionary changes and every
    /// cached tokenization / boundary set is now stale.
    func invalidateAll() {
        tokenCache.removeAll(keepingCapacity: true)
        documentMetadataCache.removeAll(keepingCapacity: true)
    }

    func remove(_ id: String) {
        tokenCache.removeValue(forKey: id)
        documentMetadataCache.removeValue(forKey: id)
    }
}

enum PerformanceTrace {
    private static let log = OSLog(subsystem: "com.shh.fastread", category: .pointsOfInterest)

    static func measure<T>(_ name: StaticString, _ operation: () throws -> T) rethrows -> T {
        let id = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: name, signpostID: id)
        defer {
            os_signpost(.end, log: log, name: name, signpostID: id)
        }
        return try operation()
    }
}

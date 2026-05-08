import Foundation

/// Storage migration helpers that mirror `src/storage-migration.js` (JS).
///
/// The legacy ("v1") shape persists each ReadingArticle with a flat `text`
/// field. The v2 shape carries a `Document` with a single body Section
/// alongside the article. ReadingArticle's on-disk codable shape is
/// unchanged (the `text` field is preserved for backward compatibility);
/// the Document is reconstructed in-memory at load time.
public enum StorageMigration {
    /// Builds a single-body-section `Document` from a legacy `ReadingArticle`.
    public static func documentFromLegacy(article: ReadingArticle) -> Document {
        let section = Section(id: "body", title: "", kind: .body, text: article.text)
        return Document(
            title: article.title,
            author: article.author,
            sourceUrl: article.sourceURL ?? "",
            sourceKind: "text",
            sections: [section]
        )
    }

    /// Maps a legacy article list into a `[articleId: Document]` lookup.
    /// Existing v2 callers can use this map alongside the original article
    /// list — the article's `text` is preserved as the source of truth so
    /// re-running this migration is idempotent.
    public static func migrateLegacyArticles(_ articles: [ReadingArticle]) -> [String: Document] {
        var map: [String: Document] = [:]
        for article in articles {
            map[article.id] = documentFromLegacy(article: article)
        }
        return map
    }

    /// Decodes a legacy `[ReadingArticle]` JSON blob and returns both the
    /// articles and the Document map produced by the migration. Returns
    /// `nil` if the data does not decode as the legacy article array.
    public static func loadAndMigrate(legacyData data: Data) -> (articles: [ReadingArticle], documents: [String: Document])? {
        guard let articles = try? JSONDecoder().decode([ReadingArticle].self, from: data) else {
            return nil
        }
        return (articles, migrateLegacyArticles(articles))
    }
}

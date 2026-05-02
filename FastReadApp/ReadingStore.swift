import Combine
import Foundation

@MainActor
final class ReadingStore: ObservableObject {
    @Published var articles: [ReadingArticle]
    @Published var selectedArticleID: String
    @Published var stats: ReadingStats
    @Published var wpm: Double {
        didSet { persistSettings() }
    }
    @Published var punctuationPause: Bool {
        didSet { persistSettings() }
    }
    @Published var focusIndicator: FocusIndicatorStyle {
        didSet { persistSettings() }
    }
    @Published var wordTypeface: WordTypeface {
        didSet { persistSettings() }
    }
    @Published private(set) var isPlaying = false
    @Published var sourceStatus = ""

    private var playbackTask: Task<Void, Never>?
    private let defaults: UserDefaults

    var currentArticle: ReadingArticle {
        articles[selectedArticleIndex]
    }

    var currentTokens: [String] {
        currentArticle.tokens
    }

    var currentIndex: Int {
        RSVPEngine.clamp(currentArticle.wordIndex, min: 0, max: max(currentTokens.count - 1, 0))
    }

    var currentToken: String {
        guard !currentTokens.isEmpty else { return "" }
        return currentTokens[currentIndex]
    }

    var readerProgress: Double {
        guard !currentTokens.isEmpty else { return 0 }
        return Double(currentIndex + 1) / Double(currentTokens.count)
    }

    var minutesRemaining: Double {
        RSVPEngine.estimateMinutes(wordCount: max(currentTokens.count - currentIndex, 0), wpm: wpm)
    }

    var selectedArticleIndex: Int {
        articles.firstIndex { $0.id == selectedArticleID } ?? 0
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let settings = Self.loadSettings(from: defaults)

        self.articles = Self.loadArticles(from: defaults)
        self.selectedArticleID = defaults.string(forKey: StorageKey.selectedArticle) ?? SampleData.currentArticle.id
        self.stats = Self.loadStats(from: defaults)
        self.wpm = settings.wpm
        self.punctuationPause = settings.punctuationPause
        self.focusIndicator = settings.focusIndicator
        self.wordTypeface = settings.wordTypeface

        if !articles.contains(where: { $0.id == selectedArticleID }) {
            selectedArticleID = SampleData.currentArticle.id
        }
    }

    deinit {
        playbackTask?.cancel()
    }

    func openArticle(_ id: ReadingArticle.ID, resume: Bool) {
        pause()
        guard articles.contains(where: { $0.id == id }) else { return }
        selectedArticleID = id
        defaults.set(id, forKey: StorageKey.selectedArticle)

        updateSelectedArticle { article in
            article.timesOpened += 1
            if !resume {
                article.wordIndex = 0
                if !article.isFinished {
                    article.progress = 0
                }
            }
        }
    }

    func setWPM(_ value: Double) {
        wpm = RSVPEngine.clamp(value.rounded(.toNearestOrAwayFromZero), min: 150, max: 1_000)
    }

    func togglePlay() {
        isPlaying ? pause() : play()
    }

    func play() {
        guard !currentTokens.isEmpty, currentIndex < currentTokens.count - 1 else { return }
        isPlaying = true
        scheduleNext()
    }

    func pause() {
        isPlaying = false
        playbackTask?.cancel()
        playbackTask = nil
    }

    func move(by delta: Int) {
        pause()
        setIndex(currentIndex + delta)
    }

    func scrub(to progress: Double) {
        let wasPlaying = isPlaying
        pause()
        let target = Int((progress * Double(max(currentTokens.count - 1, 0))).rounded())
        setIndex(target)
        if wasPlaying {
            play()
        }
    }

    func setIndex(_ index: Int) {
        updateSelectedArticle { article in
            article.wordIndex = RSVPEngine.clamp(index, min: 0, max: max(RSVPEngine.tokenize(article.text).count - 1, 0))
            article.isFinished = false
            article.tag = article.progress > 0 ? "Reading now" : article.tag
        }
    }

    func markRead() {
        let wasFinished = currentArticle.isFinished
        pause()
        updateSelectedArticle { article in
            article.wordIndex = max(RSVPEngine.tokenize(article.text).count - 1, 0)
            article.progress = 1
            article.isFinished = true
            article.tag = "Finished"
        }

        if !wasFinished {
            stats.today.articles += 1
            stats.totalArticles += 1
            persistStats()
        }
    }

    func addDraftArticle(text: String, title: String = "Pasted text", source: String = "Clipboard") {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        pause()
        let article = ReadingArticle(
            id: "draft-\(UUID().uuidString)",
            title: title,
            source: source,
            author: "You",
            date: "Today",
            readTime: "\(max(1, Int(ceil(RSVPEngine.estimateMinutes(wordCount: RSVPEngine.tokenize(trimmed).count, wpm: wpm))))) min",
            lede: RSVPEngine.tokenize(trimmed).prefix(18).joined(separator: " "),
            tag: "Reading now",
            text: trimmed,
            progress: 0,
            wordIndex: 0,
            timesOpened: 1,
            isFinished: false
        )
        articles.insert(article, at: 0)
        selectedArticleID = article.id
        defaults.set(article.id, forKey: StorageKey.selectedArticle)
        persistArticles()
    }

    func addFetchedArticle(title: String, source: String, text: String) {
        addDraftArticle(text: text, title: title, source: source)
    }

    private func scheduleNext() {
        playbackTask?.cancel()
        guard isPlaying, !currentTokens.isEmpty else { return }

        let delay = RSVPEngine.duration(
            for: currentToken,
            wpm: wpm,
            punctuationPause: punctuationPause
        )

        playbackTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000)
            self?.advanceFromTimer()
        }
    }

    private func advanceFromTimer() {
        guard isPlaying else { return }

        if currentIndex >= currentTokens.count - 1 {
            pause()
            return
        }

        updateSelectedArticle { article in
            article.wordIndex += 1
        }
        stats.today.words += 1
        if let lastIndex = stats.week.indices.last {
            stats.week[lastIndex].words += 1
        }
        persistStats()
        scheduleNext()
    }

    private func updateSelectedArticle(_ mutate: (inout ReadingArticle) -> Void) {
        guard articles.indices.contains(selectedArticleIndex) else { return }
        var article = articles[selectedArticleIndex]
        mutate(&article)

        let count = RSVPEngine.tokenize(article.text).count
        article.wordIndex = RSVPEngine.clamp(article.wordIndex, min: 0, max: max(count - 1, 0))
        if count > 0 {
            article.progress = article.isFinished ? 1 : Double(article.wordIndex + 1) / Double(count)
        }
        articles[selectedArticleIndex] = article
        persistArticles()
    }

    private func persistSettings() {
        let payload = SettingsPayload(
            wpm: wpm,
            punctuationPause: punctuationPause,
            focusIndicator: focusIndicator,
            wordTypeface: wordTypeface
        )
        encode(payload, forKey: StorageKey.settings)
    }

    private func persistArticles() {
        encode(articles, forKey: StorageKey.articles)
    }

    private func persistStats() {
        encode(stats, forKey: StorageKey.stats)
    }

    private func encode<T: Encodable>(_ value: T, forKey key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }

    private static func loadSettings(from defaults: UserDefaults) -> SettingsPayload {
        guard
            let data = defaults.data(forKey: StorageKey.settings),
            let payload = try? JSONDecoder().decode(SettingsPayload.self, from: data)
        else {
            return SettingsPayload(
                wpm: 540,
                punctuationPause: true,
                focusIndicator: .dot,
                wordTypeface: .serif
            )
        }
        return payload
    }

    private static func loadArticles(from defaults: UserDefaults) -> [ReadingArticle] {
        guard
            let data = defaults.data(forKey: StorageKey.articles),
            let articles = try? JSONDecoder().decode([ReadingArticle].self, from: data),
            !articles.isEmpty
        else {
            return SampleData.articles
        }
        return articles
    }

    private static func loadStats(from defaults: UserDefaults) -> ReadingStats {
        guard
            let data = defaults.data(forKey: StorageKey.stats),
            let stats = try? JSONDecoder().decode(ReadingStats.self, from: data)
        else {
            return SampleData.stats
        }
        return stats
    }
}

private struct SettingsPayload: Codable {
    var wpm: Double
    var punctuationPause: Bool
    var focusIndicator: FocusIndicatorStyle
    var wordTypeface: WordTypeface
}

private enum StorageKey {
    static let settings = "justread.settings.v1"
    static let articles = "justread.articles.v1"
    static let stats = "justread.stats.v1"
    static let selectedArticle = "justread.selectedArticle.v1"
}

enum ArticleFetchError: LocalizedError {
    case invalidURL
    case unsupportedScheme
    case badStatus(Int)
    case unreadable

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "Enter a valid URL."
        case .unsupportedScheme:
            "Only http and https URLs are supported."
        case let .badStatus(status):
            "Fetch failed with HTTP \(status)."
        case .unreadable:
            "Could not find enough readable text on that page."
        }
    }
}

struct ArticleFetchResult {
    var title: String
    var source: String
    var text: String
    var wordCount: Int
}

enum ArticleLoader {
    static func fetch(urlString: String) async throws -> ArticleFetchResult {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme else {
            throw ArticleFetchError.invalidURL
        }
        guard ["http", "https"].contains(scheme.lowercased()) else {
            throw ArticleFetchError.unsupportedScheme
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ArticleFetchError.badStatus(http.statusCode)
        }

        let html = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""
        let attributed = try? NSAttributedString(
            data: Data(html.utf8),
            options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue,
            ],
            documentAttributes: nil
        )
        let text = normalizeExtractedText(attributed?.string ?? stripTags(html))
        let words = RSVPEngine.tokenize(text)

        guard words.count >= 20 else {
            throw ArticleFetchError.unreadable
        }

        let title = extractTitle(from: html) ?? url.host(percentEncoded: false) ?? "Fetched article"
        return ArticleFetchResult(
            title: title,
            source: url.host(percentEncoded: false) ?? "Web",
            text: text,
            wordCount: words.count
        )
    }

    private static func extractTitle(from html: String) -> String? {
        guard let range = html.range(of: #"<title[^>]*>(.*?)</title>"#, options: [.regularExpression, .caseInsensitive]) else {
            return nil
        }
        let raw = html[range]
            .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        let title = normalizeExtractedText(String(raw))
        return title.isEmpty ? nil : title
    }

    private static func stripTags(_ html: String) -> String {
        html
            .replacingOccurrences(of: #"<(script|style|noscript|svg)[\s\S]*?</\1>"#, with: " ", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"</(p|div|article|section|h[1-6]|li|br)[^>]*>"#, with: "\n", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&rsquo;", with: "'")
            .replacingOccurrences(of: "&ldquo;", with: "\"")
            .replacingOccurrences(of: "&rdquo;", with: "\"")
    }

    private static func normalizeExtractedText(_ text: String) -> String {
        text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

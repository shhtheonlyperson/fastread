import Combine
import Foundation

@MainActor
public final class ReadingStore: ObservableObject {
    @Published public var articles: [ReadingArticle]
    @Published public var selectedArticleID: String?
    @Published public var stats: ReadingStats
    @Published public private(set) var wpm: Double
    @Published public var punctuationPause: Bool {
        didSet { persistSettings() }
    }
    @Published public var focusIndicator: FocusIndicatorStyle {
        didSet { persistSettings() }
    }
    @Published public private(set) var userDictionary: [String] = []
    @Published public private(set) var isPlaying = false
    @Published public var sourceStatus = ""

    private var playbackTask: Task<Void, Never>?
    /// Tokenization + section-boundary memo. Owns the per-article caches and
    /// the version-gated fast path (see ArticleContentCache).
    private let contentCache = ArticleContentCache()
    private let defaults: UserDefaults

    public var currentArticle: ReadingArticle? {
        guard let selectedArticleIndex else { return articles.first }
        return articles[selectedArticleIndex]
    }

    public var currentTokens: [String] {
        guard let currentArticle else { return [] }
        return tokens(for: currentArticle)
    }

    public var currentIndex: Int {
        guard let currentArticle else { return 0 }
        return RSVPEngine.clamp(currentArticle.wordIndex, min: 0, max: max(currentTokens.count - 1, 0))
    }

    public var currentToken: String {
        guard !currentTokens.isEmpty else { return "" }
        return currentTokens[currentIndex]
    }

    public var readerProgress: Double {
        guard !currentTokens.isEmpty else { return 0 }
        return Double(currentIndex + 1) / Double(currentTokens.count)
    }

    public var minutesRemaining: Double {
        RSVPEngine.estimateMinutes(wordCount: max(currentTokens.count - currentIndex, 0), wpm: wpm)
    }

    public var selectedArticleIndex: Int? {
        guard let selectedArticleID else { return articles.isEmpty ? nil : 0 }
        return articles.firstIndex { $0.id == selectedArticleID } ?? (articles.isEmpty ? nil : 0)
    }

    /// Whether the current article reads as CJK, sampled cheaply from the
    /// short lede (falling back to title) so it can be read on every slider
    /// tick without flattening the whole document.
    private var currentArticleIsCJK: Bool {
        guard let currentArticle else { return false }
        let sample = currentArticle.lede.isEmpty ? currentArticle.title : currentArticle.lede
        return RSVPEngine.containsCJK(sample)
    }

    /// Lowest WPM the slider allows for the current article. CJK is denser per
    /// glyph and carries a duration multiplier, so it reads comfortably slower
    /// (see RSVPSpec.WPM.minimumUser).
    public var currentMinimumWPM: Double {
        RSVPEngine.minimumUserWPM(forCJK: currentArticleIsCJK)
    }

    /// Clamp + snap a WPM value to the current article's script-aware range.
    public func snapWPM(_ value: Double) -> Double {
        RSVPEngine.snapWPM(value, forCJK: currentArticleIsCJK)
    }

    public var recentSources: [RecentSource] {
        var seen = Set<String>()
        return articles
            .compactMap { article -> RecentSource? in
                let label = article.source.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !label.isEmpty, label != "Clipboard" else { return nil }
                let key = (article.sourceURL ?? label).lowercased()
                guard !seen.contains(key) else { return nil }
                seen.insert(key)
                return RecentSource(
                    label: label,
                    date: Self.relativeDateLabel(for: article.createdAt ?? article.lastOpenedAt ?? Date()),
                    url: article.sourceURL
                )
            }
            .prefix(5)
            .map { $0 }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let settings = Self.loadSettings(from: defaults)

        let loadedArticles = Self.loadArticles(from: defaults)
        self.articles = loadedArticles
        self.selectedArticleID = defaults.string(forKey: StorageKey.selectedArticle)
        self.stats = StatsEngine.load(from: defaults.data(forKey: StorageKey.stats))
        // Provisional; re-snapped below once the selected article (and so its
        // script-aware floor) is resolved.
        self.wpm = settings.wpm
        self.punctuationPause = settings.punctuationPause
        self.focusIndicator = settings.focusIndicator
        self.userDictionary = Self.loadUserDictionary(from: defaults)

        ensureSelectedArticle()
        self.wpm = snapWPM(settings.wpm)
        StatsEngine.rollStatsIfNeeded(into: &stats, wpm: wpm)
    }

    deinit {
        playbackTask?.cancel()
    }

    public func openArticle(_ id: ReadingArticle.ID, resume: Bool) {
        pause()
        guard articles.contains(where: { $0.id == id }) else { return }
        selectedArticleID = id
        persistSelectedArticleID()

        updateSelectedArticle { article in
            article.timesOpened += 1
            article.lastOpenedAt = Date()
            if !resume {
                article.wordIndex = 0
                if !article.isFinished {
                    article.progress = 0
                }
            }
        }

        // The new article's script may raise the floor (e.g. switching from a
        // CJK article read at 150 to a Latin one). Re-snap so the stored wpm
        // never sits below the slider's minimum; snapping only ever raises it.
        updateWPM(wpm, persist: true)
    }

    public func setWPM(_ value: Double) {
        updateWPM(value, persist: true)
    }

    public func addToUserDictionary(_ entry: String) {
        let trimmed = entry.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !userDictionary.contains(trimmed) else { return }
        userDictionary.append(trimmed)
        invalidateTokenizationCaches()
        persistUserDictionary()
    }

    public func removeFromUserDictionary(_ entry: String) {
        guard let index = userDictionary.firstIndex(of: entry) else { return }
        userDictionary.remove(at: index)
        invalidateTokenizationCaches()
        persistUserDictionary()
    }

    public func clearUserDictionary() {
        guard !userDictionary.isEmpty else { return }
        userDictionary = []
        invalidateTokenizationCaches()
        persistUserDictionary()
    }

    private func invalidateTokenizationCaches() {
        // Token boundaries depend on the dictionary, so any cached tokens
        // and section offsets must be recomputed on next access. Strip
        // the persisted per-article tokens too so the version-gated fast
        // path falls through to a fresh tokenize on next access.
        contentCache.invalidateAll()
        var changed = false
        for index in articles.indices {
            if articles[index].tokens != nil || articles[index].tokenizerVersion != nil {
                articles[index].tokens = nil
                articles[index].tokenizerVersion = nil
                changed = true
            }
        }
        if changed {
            persistArticles()
        }
    }

    public func previewWPM(_ value: Double) {
        updateWPM(value, persist: false)
    }

    public func wordCount(for article: ReadingArticle) -> Int {
        tokens(for: article).count
    }

    public func togglePlay() {
        isPlaying ? pause() : play()
    }

    public func play() {
        guard currentTokens.count > 1 else { return }
        if currentIndex >= currentTokens.count - 1 {
            setIndex(0)
        }
        isPlaying = true
        scheduleNext()
    }

    public func pause() {
        isPlaying = false
        playbackTask?.cancel()
        playbackTask = nil
    }

    public func move(by delta: Int) {
        pause()
        setIndex(currentIndex + delta)
    }

    public func scrub(to progress: Double) {
        let wasPlaying = isPlaying
        pause()
        let target = Int((progress * Double(max(currentTokens.count - 1, 0))).rounded())
        setIndex(target)
        if wasPlaying {
            play()
        }
    }

    public func jumpToToken(_ tokenIndex: Int) {
        pause()
        setIndex(tokenIndex)
    }

    public func currentSectionBoundaries() -> [Document.SectionBoundary] {
        guard let currentArticle else { return [] }
        return documentMetadata(for: currentArticle).boundaries
    }

    public func currentFrontMatterDetection() -> Document.FrontMatterDetection? {
        guard let currentArticle else { return nil }
        return documentMetadata(for: currentArticle).frontMatter
    }

    public func setIndex(_ index: Int) {
        updateSelectedArticle { article in
            let count = tokens(for: article).count
            article.wordIndex = RSVPEngine.clamp(index, min: 0, max: max(count - 1, 0))
            article.isFinished = false
            article.finishedAt = nil
            article.tag = article.progress > 0 ? "Reading now" : "Saved"
        }
    }

    public func markRead() {
        guard let currentArticle else { return }
        let wasFinished = currentArticle.isFinished
        pause()
        updateSelectedArticle { article in
            article.wordIndex = max(tokens(for: article).count - 1, 0)
            article.progress = 1
            article.isFinished = true
            article.finishedAt = Date()
            article.tag = "Finished"
        }

        if !wasFinished {
            recordFinishedArticle()
        }
    }

    public func addDraftArticle(text: String, title: String = "Pasted text", source: String = "Clipboard", sourceURL: String? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        guard let document = try? ImporterRegistry.shared.importDocument(
            kind: .text,
            input: trimmed,
            options: ImportOptions(sourceUrl: sourceURL ?? "", title: title, author: "You")
        ) else {
            return
        }

        addArticle(document: document, source: source, sourceURL: sourceURL)
    }

    public func addFetchedArticle(title: String, source: String, text: String, url: String? = nil) {
        addDraftArticle(text: text, title: title, source: source, sourceURL: url)
    }

    @discardableResult
    public func addEpubArticle(data: Data, filename: String? = nil) throws -> ReadingArticle? {
        let document = try ImporterRegistry.shared.importEpub(
            data: data,
            options: ImportOptions(sourceUrl: "", title: "", author: "")
        )
        let flattened = Document.flattenText(document)
        let trimmed = flattened.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let source: String
        if let filename, !filename.isEmpty {
            source = filename
        } else if !document.title.isEmpty {
            source = document.title
        } else {
            source = "EPUB"
        }
        addArticle(document: document, source: source, sourceURL: nil)
        return articles.first
    }

    public func addArticle(document: Document, source: String, sourceURL: String? = nil) {
        let flattened = Document.flattenText(document)
        let trimmed = flattened.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        pause()
        let tokens = RSVPEngine.tokenize(flattened, userDictionary: userDictionary)
        let now = Date()
        let title = document.title.isEmpty ? "Pasted text" : document.title
        let author = document.author.isEmpty ? "You" : document.author
        let article = ReadingArticle(
            id: "draft-\(UUID().uuidString)",
            title: title,
            source: source,
            sourceURL: sourceURL,
            author: author,
            date: Self.displayDate(for: now),
            createdAt: now,
            lastOpenedAt: now,
            finishedAt: nil,
            readTime: "\(max(1, Int(ceil(RSVPEngine.estimateMinutes(wordCount: tokens.count, wpm: wpm))))) min",
            lede: Self.makeLede(from: flattened, tokens: tokens),
            tag: "Reading now",
            document: document,
            progress: 0,
            wordIndex: 0,
            timesOpened: 1,
            isFinished: false,
            tokens: tokens,
            tokenizerVersion: RSVPEngine.version
        )
        contentCache.store(tokens: tokens, for: article.id)
        articles.insert(article, at: 0)
        selectedArticleID = article.id
        persistSelectedArticleID()
        persistArticles()
    }

    public func deleteArticle(_ id: ReadingArticle.ID) {
        guard let deletedIndex = articles.firstIndex(where: { $0.id == id }) else { return }
        let deletedSelectedArticle = articles[deletedIndex].id == selectedArticleID

        if deletedSelectedArticle {
            pause()
        }

        articles.remove(at: deletedIndex)
        contentCache.remove(id)

        if deletedSelectedArticle {
            selectedArticleID = articles.indices.contains(deletedIndex)
                ? articles[deletedIndex].id
                : articles.last?.id
        }

        ensureSelectedArticle()
        persistSelectedArticleID()
        persistArticles()
    }

    private func scheduleNext() {
        playbackTask?.cancel()
        guard isPlaying, !currentTokens.isEmpty else { return }

        let timing = PlaybackTiming(wpm: wpm, punctuationPause: punctuationPause)
        let delay = timing.durationMilliseconds(for: currentToken)

        playbackTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.advanceFromTimer()
        }
    }

    private func updateWPM(_ value: Double, persist: Bool) {
        let next = snapWPM(value)
        guard next != wpm else {
            if persist { persistSettings() }
            return
        }
        let wasPlaying = isPlaying
        wpm = next
        if persist {
            persistSettings()
        }
        if wasPlaying {
            scheduleNext()
        }
    }

    private func advanceFromTimer() {
        guard isPlaying else { return }

        guard let nextIndex = PlaybackTiming.nextIndex(after: currentIndex, tokenCount: currentTokens.count) else {
            pause()
            return
        }

        updateSelectedArticle { article in
            article.wordIndex = nextIndex
        }
        recordReadWords(1)
        scheduleNext()
    }

    private func updateSelectedArticle(_ mutate: (inout ReadingArticle) -> Void) {
        guard let selectedArticleIndex, articles.indices.contains(selectedArticleIndex) else { return }
        var article = articles[selectedArticleIndex]
        mutate(&article)

        // ensureTokens populates article.tokens + tokenizerVersion when
        // the persisted slot is empty/stale, so the next launch can take
        // the fast path without re-tokenizing.
        let count = ensureTokens(for: &article).count
        article.wordIndex = RSVPEngine.clamp(article.wordIndex, min: 0, max: max(count - 1, 0))
        if count > 0 {
            article.progress = article.isFinished ? 1 : Double(article.wordIndex + 1) / Double(count)
        }
        article.tag = article.isFinished ? "Finished" : article.progress > 0 ? "Reading now" : "Saved"
        articles[selectedArticleIndex] = article
        persistArticles()
    }

    private func ensureSelectedArticle() {
        if let selectedArticleID, articles.contains(where: { $0.id == selectedArticleID }) {
            return
        }

        selectedArticleID = articles.first?.id
        persistSelectedArticleID()
    }

    private func persistSelectedArticleID() {
        if let selectedArticleID {
            defaults.set(selectedArticleID, forKey: StorageKey.selectedArticle)
        } else {
            defaults.removeObject(forKey: StorageKey.selectedArticle)
        }
    }

    private func recordReadWords(_ count: Int) {
        guard count > 0 else { return }
        StatsEngine.recordReadWords(count, into: &stats, wpm: wpm)
        persistStats()
    }

    private func recordFinishedArticle() {
        StatsEngine.recordFinishedArticle(into: &stats, wpm: wpm)
        persistStats()
    }

    private func persistSettings() {
        let payload = SettingsPayload(
            wpm: wpm,
            punctuationPause: punctuationPause,
            focusIndicator: focusIndicator
        )
        encode(payload, forKey: StorageKey.settings)
    }

    private func persistArticles() {
        encode(articles, forKey: StorageKey.articles)
    }

    private func persistStats() {
        encode(stats, forKey: StorageKey.stats)
    }

    private func persistUserDictionary() {
        encode(userDictionary, forKey: StorageKey.userDictionary)
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
                wpm: 550,
                punctuationPause: true,
                focusIndicator: .dot
            )
        }
        return payload
    }

    private static func loadUserDictionary(from defaults: UserDefaults) -> [String] {
        guard
            let data = defaults.data(forKey: StorageKey.userDictionary),
            let entries = try? JSONDecoder().decode([String].self, from: data)
        else {
            return []
        }
        // Drop blanks and de-dup while preserving original order.
        var seen = Set<String>()
        return entries.compactMap { raw in
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { return nil }
            return trimmed
        }
    }

    private static func loadArticles(from defaults: UserDefaults) -> [ReadingArticle] {
        guard
            let data = defaults.data(forKey: StorageKey.articles),
            let articles = try? JSONDecoder().decode([ReadingArticle].self, from: data)
        else {
            return []
        }
        return articles
    }

    private static func displayDate(for date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().year())
    }

    private static func relativeDateLabel(for date: Date) -> String {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: Date())
        let days = calendar.dateComponents([.day], from: start, to: today).day ?? 0
        switch days {
        case ...0: return "Today"
        case 1: return "Yesterday"
        case 2...6: return "\(days)d ago"
        default: return date.formatted(.dateTime.month(.abbreviated).day())
        }
    }

    private static func estimatedMinutes(for words: Int, wpm: Double) -> Int {
        guard words > 0 else { return 0 }
        return max(1, Int(ceil(RSVPEngine.estimateMinutes(wordCount: words, wpm: wpm))))
    }

    private func tokens(for article: ReadingArticle) -> [String] {
        contentCache.tokens(for: article, userDictionary: userDictionary)
    }

    @discardableResult
    private func ensureTokens(for article: inout ReadingArticle) -> [String] {
        contentCache.ensureTokens(for: &article, userDictionary: userDictionary)
    }

    private func documentMetadata(for article: ReadingArticle) -> ArticleContentCache.DocumentMetadataEntry {
        contentCache.documentMetadata(for: article, userDictionary: userDictionary)
    }

    private static func makeLede(from text: String, tokens: [String]) -> String {
        let useJoin = RSVPEngine.containsCJK(text)
        let selected = tokens.prefix(useJoin ? 42 : 18)
        return useJoin ? selected.joined() : selected.joined(separator: " ")
    }
}

public struct RecentSource: Identifiable, Equatable, Sendable {
    public var label: String
    public var date: String
    public var url: String?

    public init(label: String, date: String, url: String? = nil) {
        self.label = label
        self.date = date
        self.url = url
    }

    public var id: String { (url ?? label).lowercased() }
}

private struct SettingsPayload: Codable {
    public var wpm: Double
    public var punctuationPause: Bool
    public var focusIndicator: FocusIndicatorStyle
}

private enum StorageKey {
    static let settings = "justread.settings.v1"
    static let articles = "justread.articles.v1"
    static let stats = "justread.stats.v1"
    static let selectedArticle = "justread.selectedArticle.v1"
    static let userDictionary = "justread.userDictionary.v1"
}

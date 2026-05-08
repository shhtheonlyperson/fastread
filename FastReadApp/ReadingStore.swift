import Combine
import Foundation
import OSLog

@MainActor
final class ReadingStore: ObservableObject {
    @Published var articles: [ReadingArticle]
    @Published var selectedArticleID: String?
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
    private var tokenCache: [String: TokenCacheEntry] = [:]
    private let defaults: UserDefaults

    var currentArticle: ReadingArticle? {
        guard let selectedArticleIndex else { return articles.first }
        return articles[selectedArticleIndex]
    }

    var currentTokens: [String] {
        guard let currentArticle else { return [] }
        return tokens(for: currentArticle)
    }

    var currentIndex: Int {
        guard let currentArticle else { return 0 }
        return RSVPEngine.clamp(currentArticle.wordIndex, min: 0, max: max(currentTokens.count - 1, 0))
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

    var selectedArticleIndex: Int? {
        guard let selectedArticleID else { return articles.isEmpty ? nil : 0 }
        return articles.firstIndex { $0.id == selectedArticleID } ?? (articles.isEmpty ? nil : 0)
    }

    var recentSources: [RecentSource] {
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

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let settings = Self.loadSettings(from: defaults)

        let loadedArticles = Self.loadArticles(from: defaults)
        self.articles = loadedArticles
        self.selectedArticleID = defaults.string(forKey: StorageKey.selectedArticle)
        self.stats = Self.loadStats(from: defaults)
        self.wpm = settings.wpm
        self.punctuationPause = settings.punctuationPause
        self.focusIndicator = settings.focusIndicator
        self.wordTypeface = settings.wordTypeface

        ensureSelectedArticle()
        rollStatsIfNeeded()
    }

    deinit {
        playbackTask?.cancel()
    }

    func openArticle(_ id: ReadingArticle.ID, resume: Bool) {
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
    }

    func setWPM(_ value: Double) {
        wpm = RSVPEngine.clamp(value, min: 150, max: 1_000)
    }

    func wordCount(for article: ReadingArticle) -> Int {
        tokens(for: article).count
    }

    func togglePlay() {
        isPlaying ? pause() : play()
    }

    func play() {
        guard currentTokens.count > 1 else { return }
        if currentIndex >= currentTokens.count - 1 {
            setIndex(0)
        }
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
            let count = tokens(for: article).count
            article.wordIndex = RSVPEngine.clamp(index, min: 0, max: max(count - 1, 0))
            article.isFinished = false
            article.finishedAt = nil
            article.tag = article.progress > 0 ? "Reading now" : "Saved"
        }
    }

    func markRead() {
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

    func addDraftArticle(text: String, title: String = "Pasted text", source: String = "Clipboard", sourceURL: String? = nil) {
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

    func addFetchedArticle(title: String, source: String, text: String, url: String? = nil) {
        addDraftArticle(text: text, title: title, source: source, sourceURL: url)
    }

    @discardableResult
    func addEpubArticle(data: Data, filename: String? = nil) throws -> ReadingArticle? {
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

    func addArticle(document: Document, source: String, sourceURL: String? = nil) {
        let flattened = Document.flattenText(document)
        let trimmed = flattened.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        pause()
        let tokens = RSVPEngine.tokenize(flattened)
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
            isFinished: false
        )
        tokenCache[article.id] = TokenCacheEntry(text: flattened, tokens: tokens)
        articles.insert(article, at: 0)
        selectedArticleID = article.id
        persistSelectedArticleID()
        persistArticles()
    }

    func deleteArticle(_ id: ReadingArticle.ID) {
        guard let deletedIndex = articles.firstIndex(where: { $0.id == id }) else { return }
        let deletedSelectedArticle = articles[deletedIndex].id == selectedArticleID

        if deletedSelectedArticle {
            pause()
        }

        articles.remove(at: deletedIndex)
        tokenCache.removeValue(forKey: id)

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

        let delay = RSVPEngine.duration(
            for: currentToken,
            wpm: wpm,
            punctuationPause: punctuationPause
        )

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

    private func advanceFromTimer() {
        guard isPlaying else { return }

        if currentIndex >= currentTokens.count - 1 {
            pause()
            return
        }

        updateSelectedArticle { article in
            article.wordIndex += 1
        }
        recordReadWords(1)
        scheduleNext()
    }

    private func updateSelectedArticle(_ mutate: (inout ReadingArticle) -> Void) {
        guard let selectedArticleIndex, articles.indices.contains(selectedArticleIndex) else { return }
        var article = articles[selectedArticleIndex]
        mutate(&article)

        let count = tokens(for: article).count
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
        startActivityIfNeeded()
        stats.today.words += count
        stats.today.minutes = Self.estimatedMinutes(for: stats.today.words, wpm: wpm)
        if let todayIndex = stats.week.firstIndex(where: { $0.date == Self.dayKey(for: Date()) }) {
            stats.week[todayIndex].words += count
        }
        stats.avgWPM = Int(wpm.rounded())
        stats.bestWPM = max(stats.bestWPM, Int(wpm.rounded()))
        persistStats()
    }

    private func recordFinishedArticle() {
        startActivityIfNeeded()
        stats.today.articles += 1
        stats.today.minutes = Self.estimatedMinutes(for: stats.today.words, wpm: wpm)
        stats.totalArticles += 1
        stats.avgWPM = Int(wpm.rounded())
        stats.bestWPM = max(stats.bestWPM, Int(wpm.rounded()))
        persistStats()
    }

    private func startActivityIfNeeded(now: Date = Date()) {
        rollStatsIfNeeded(now: now)
        let todayKey = Self.dayKey(for: now)
        let alreadyActiveToday = stats.lastActiveDay == todayKey && (stats.today.words > 0 || stats.today.articles > 0)
        guard !alreadyActiveToday else { return }

        if let lastActiveDay = stats.lastActiveDay,
           let lastActiveDate = Self.date(fromDayKey: lastActiveDay),
           Calendar.current.isDate(lastActiveDate, inSameDayAs: Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now) {
            stats.streak += 1
        } else {
            stats.streak = 1
        }
        stats.lastActiveDay = todayKey
    }

    private func rollStatsIfNeeded(now: Date = Date()) {
        let todayKey = Self.dayKey(for: now)
        let datedWeek = stats.week.filter { $0.date != nil }
        let wordsByDay = Dictionary(uniqueKeysWithValues: datedWeek.map { ($0.date ?? $0.day, $0.words) })
        stats.week = Self.weekTemplate(endingAt: now).map { day in
            DayWords(date: day.date, day: day.day, words: wordsByDay[day.date ?? day.day] ?? 0)
        }

        if stats.lastActiveDay != todayKey {
            stats.today = TodayStats(words: wordsByDay[todayKey] ?? 0, minutes: 0, articles: 0)
        } else if let todayWords = stats.week.first(where: { $0.date == todayKey })?.words {
            stats.today.words = todayWords
        }
        stats.today.minutes = Self.estimatedMinutes(for: stats.today.words, wpm: wpm)
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
            let articles = try? JSONDecoder().decode([ReadingArticle].self, from: data)
        else {
            return []
        }
        return articles
    }

    private static func loadStats(from defaults: UserDefaults) -> ReadingStats {
        guard
            let data = defaults.data(forKey: StorageKey.stats),
            let stats = try? JSONDecoder().decode(ReadingStats.self, from: data)
        else {
            return emptyStats()
        }

        guard stats.week.allSatisfy({ $0.date != nil }) else {
            return emptyStats()
        }
        return stats
    }

    private static func emptyStats(for date: Date = Date()) -> ReadingStats {
        ReadingStats(
            today: TodayStats(words: 0, minutes: 0, articles: 0),
            week: weekTemplate(endingAt: date),
            streak: 0,
            avgWPM: 0,
            bestWPM: 0,
            totalArticles: 0,
            lastActiveDay: nil
        )
    }

    private static func weekTemplate(endingAt date: Date) -> [DayWords] {
        let calendar = Calendar.current
        return (0..<7).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset - 6, to: date) else { return nil }
            return DayWords(date: dayKey(for: day), day: weekdayLabel(for: day), words: 0)
        }
    }

    private static func dayKey(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    private static func date(fromDayKey key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    private static func weekdayLabel(for date: Date) -> String {
        let weekday = Calendar.current.component(.weekday, from: date)
        let symbols = Calendar.current.shortWeekdaySymbols
        return symbols.indices.contains(weekday - 1) ? symbols[weekday - 1] : ""
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
        if let cached = tokenCache[article.id], cached.text == article.text {
            return cached.tokens
        }

        let tokens = PerformanceTrace.measure("Tokenize Article") {
            RSVPEngine.tokenize(article.text)
        }
        tokenCache[article.id] = TokenCacheEntry(text: article.text, tokens: tokens)
        return tokens
    }

    private static func makeLede(from text: String, tokens: [String]) -> String {
        let limit = containsCJK(text) ? 42 : 18
        let selected = tokens.prefix(limit)
        return containsCJK(text) ? selected.joined() : selected.joined(separator: " ")
    }

    private static func containsCJK(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            (0x3040...0x30ff).contains(scalar.value) ||
            (0x3400...0x4dbf).contains(scalar.value) ||
            (0x4e00...0x9fff).contains(scalar.value) ||
            (0xf900...0xfaff).contains(scalar.value) ||
            (0xac00...0xd7af).contains(scalar.value)
        }
    }
}

struct RecentSource: Identifiable, Equatable {
    var label: String
    var date: String
    var url: String?

    var id: String { (url ?? label).lowercased() }
}

private enum PerformanceTrace {
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

private struct SettingsPayload: Codable {
    var wpm: Double
    var punctuationPause: Bool
    var focusIndicator: FocusIndicatorStyle
    var wordTypeface: WordTypeface
}

private struct TokenCacheEntry {
    var text: String
    var tokens: [String]
}

private enum StorageKey {
    static let settings = "justread.settings.v1"
    static let articles = "justread.articles.v1"
    static let stats = "justread.stats.v1"
    static let selectedArticle = "justread.selectedArticle.v1"
}


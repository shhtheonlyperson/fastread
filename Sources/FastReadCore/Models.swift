import Foundation

public enum AppTab: String, CaseIterable, Identifiable, Codable, Sendable {
    case home
    case source
    case reader
    case stats
    case settings

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .home: "Library"
        case .source: "Add"
        case .reader: "Read"
        case .stats: "Stats"
        case .settings: "Settings"
        }
    }
}

public enum FocusIndicatorStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    case dot
    case line
    case crosshair

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .dot: "Dots"
        case .line: "Line"
        case .crosshair: "Crosshair"
        }
    }
}

public struct DayWords: Identifiable, Codable, Equatable, Sendable {
    public var date: String?
    public var day: String
    public var words: Int

    public init(date: String? = nil, day: String, words: Int) {
        self.date = date
        self.day = day
        self.words = words
    }

    public var id: String { date ?? day }
}

public struct TodayStats: Codable, Equatable, Sendable {
    public var words: Int
    public var minutes: Int
    public var articles: Int

    public init(words: Int = 0, minutes: Int = 0, articles: Int = 0) {
        self.words = words
        self.minutes = minutes
        self.articles = articles
    }
}

public struct ReadingStats: Codable, Equatable, Sendable {
    public var today: TodayStats
    public var week: [DayWords]
    public var streak: Int
    public var avgWPM: Int
    public var bestWPM: Int
    public var totalArticles: Int
    public var lastActiveDay: String?

    public init(
        today: TodayStats = TodayStats(),
        week: [DayWords] = [],
        streak: Int = 0,
        avgWPM: Int = 0,
        bestWPM: Int = 0,
        totalArticles: Int = 0,
        lastActiveDay: String? = nil
    ) {
        self.today = today
        self.week = week
        self.streak = streak
        self.avgWPM = avgWPM
        self.bestWPM = bestWPM
        self.totalArticles = totalArticles
        self.lastActiveDay = lastActiveDay
    }

    public var weekTotal: Int {
        week.reduce(0) { $0 + $1.words }
    }
}

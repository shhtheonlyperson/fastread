import Foundation

enum AppTab: String, CaseIterable, Identifiable, Codable {
    case home
    case source
    case reader
    case stats
    case settings

    var id: String { rawValue }

    var label: String {
        switch self {
        case .home: "Library"
        case .source: "Add"
        case .reader: "Read"
        case .stats: "Stats"
        case .settings: "Settings"
        }
    }
}

enum FocusIndicatorStyle: String, CaseIterable, Identifiable, Codable {
    case dot
    case line
    case crosshair

    var id: String { rawValue }

    var label: String {
        switch self {
        case .dot: "Dots"
        case .line: "Line"
        case .crosshair: "Crosshair"
        }
    }
}

enum WordTypeface: String, CaseIterable, Identifiable, Codable {
    case serif
    case sans
    case mono

    var id: String { rawValue }

    var label: String {
        switch self {
        case .serif: "Serif"
        case .sans: "Sans"
        case .mono: "Mono"
        }
    }
}

struct DayWords: Identifiable, Codable, Equatable {
    var date: String?
    var day: String
    var words: Int

    var id: String { date ?? day }
}

struct TodayStats: Codable, Equatable {
    var words: Int
    var minutes: Int
    var articles: Int
}

struct ReadingStats: Codable, Equatable {
    var today: TodayStats
    var week: [DayWords]
    var streak: Int
    var avgWPM: Int
    var bestWPM: Int
    var totalArticles: Int
    var lastActiveDay: String?

    var weekTotal: Int {
        week.reduce(0) { $0 + $1.words }
    }
}

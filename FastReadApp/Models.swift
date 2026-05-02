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

struct ReadingArticle: Identifiable, Codable, Equatable {
    let id: String
    var title: String
    var source: String
    var author: String
    var date: String
    var readTime: String
    var lede: String
    var tag: String
    var text: String
    var progress: Double
    var wordIndex: Int
    var timesOpened: Int
    var isFinished: Bool

    var tokens: [String] {
        RSVPEngine.tokenize(text)
    }

    var wordCount: Int {
        tokens.count
    }
}

struct DayWords: Identifiable, Codable, Equatable {
    var day: String
    var words: Int

    var id: String { day }
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

    var weekTotal: Int {
        week.reduce(0) { $0 + $1.words }
    }
}

enum SampleData {
    static let currentText = """
    Researchers say a quiet shift in how we read is reshaping attention. For most of the past decade, the conversation around digital reading focused on what was being lost: depth, patience, the long arc of a paragraph. But a new wave of cognitive scientists, working with eye-tracking data and tools that present text one word at a time, argue that something else is happening too. Readers are not simply skimming more. They are renegotiating the basic contract between eye and page, learning to absorb prose in shorter visual jumps and longer mental ones. The implications, these researchers say, are still emerging, but the early evidence suggests that the brain is more elastic about how it takes in language than the long history of the printed book might lead us to believe.
    """

    static let currentArticle = ReadingArticle(
        id: "attention",
        title: "Researchers say a quiet shift in how we read is reshaping attention",
        source: "The Atlantic",
        author: "Maya Lindgren",
        date: "May 2, 2026",
        readTime: "6 min",
        lede: "For most of the past decade, the conversation around digital reading focused on what was being lost.",
        tag: "Reading now",
        text: currentText,
        progress: 0.34,
        wordIndex: Int(Double(RSVPEngine.tokenize(currentText).count) * 0.34),
        timesOpened: 1,
        isFinished: false
    )

    static let articles: [ReadingArticle] = [
        currentArticle,
        article(
            id: "memo",
            title: "The Long-Memo Renaissance",
            source: "Stratechery",
            readTime: "11 min",
            progress: 0,
            lede: "Inside the quiet revival of the 3,000-word strategy memo at large technology companies.",
            tag: "Saved"
        ),
        article(
            id: "fed",
            title: "Fed signals patience as inflation cools to 2.3%",
            source: "Reuters",
            readTime: "3 min",
            progress: 1,
            lede: "Policymakers indicated they are in no hurry to cut rates further despite the latest figures.",
            tag: "Finished",
            isFinished: true
        ),
        article(
            id: "mars",
            title: "A surprisingly habitable patch of Mars, and what it means",
            source: "Quanta",
            readTime: "8 min",
            progress: 0.62,
            lede: "New radar data hints at briny aquifers within a kilometer of the surface.",
            tag: "Reading now"
        ),
        article(
            id: "kitchen",
            title: "How restaurants quietly redesigned the home kitchen",
            source: "Eater",
            readTime: "5 min",
            progress: 0,
            lede: "The professional sheet-pan, the under-counter ice maker, the rise of the second sink.",
            tag: "Saved"
        ),
    ]

    static let stats = ReadingStats(
        today: TodayStats(words: 4_280, minutes: 11, articles: 2),
        week: [
            DayWords(day: "Mon", words: 3_200),
            DayWords(day: "Tue", words: 5_100),
            DayWords(day: "Wed", words: 2_400),
            DayWords(day: "Thu", words: 6_800),
            DayWords(day: "Fri", words: 3_900),
            DayWords(day: "Sat", words: 1_100),
            DayWords(day: "Sun", words: 4_280),
        ],
        streak: 12,
        avgWPM: 540,
        bestWPM: 720,
        totalArticles: 47
    )

    private static func article(
        id: String,
        title: String,
        source: String,
        readTime: String,
        progress: Double,
        lede: String,
        tag: String,
        isFinished: Bool = false
    ) -> ReadingArticle {
        let text = "\(title). \(lede) This saved piece is included as sample library material for the speed reader prototype. Open it to rehearse the one-word reading flow with the same RSVP engine and focus-letter anchor."
        let wordCount = RSVPEngine.tokenize(text).count
        return ReadingArticle(
            id: id,
            title: title,
            source: source,
            author: "JustRead Desk",
            date: "May 2, 2026",
            readTime: readTime,
            lede: lede,
            tag: tag,
            text: text,
            progress: progress,
            wordIndex: max(0, min(wordCount - 1, Int(Double(wordCount) * progress))),
            timesOpened: 0,
            isFinished: isFinished
        )
    }
}

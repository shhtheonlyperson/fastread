import Foundation

/// Reading-stats math extracted from ReadingStore: daily/weekly word totals,
/// streaks, and the day-key helpers they depend on.
///
/// Every mutation operates on an `inout ReadingStats` so ReadingStore can keep
/// `stats` as an `@Published` property and persist after each call. Pure given
/// (stats, wpm, now) — which is what makes the streak / week-rollover logic
/// straightforward to test in isolation.
enum StatsEngine {
    static func empty(for date: Date = Date()) -> ReadingStats {
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

    /// Decode persisted stats, falling back to `empty()` when missing or when
    /// the week template predates the dated-day migration.
    static func load(from data: Data?, for date: Date = Date()) -> ReadingStats {
        guard
            let data,
            let stats = try? JSONDecoder().decode(ReadingStats.self, from: data),
            stats.week.allSatisfy({ $0.date != nil })
        else {
            return empty(for: date)
        }
        return stats
    }

    static func recordReadWords(_ count: Int, into stats: inout ReadingStats, wpm: Double, now: Date = Date()) {
        guard count > 0 else { return }
        startActivityIfNeeded(into: &stats, now: now)
        stats.today.words += count
        stats.today.minutes = estimatedMinutes(for: stats.today.words, wpm: wpm)
        if let todayIndex = stats.week.firstIndex(where: { $0.date == dayKey(for: now) }) {
            stats.week[todayIndex].words += count
        }
        stats.avgWPM = Int(wpm.rounded())
        stats.bestWPM = max(stats.bestWPM, Int(wpm.rounded()))
    }

    static func recordFinishedArticle(into stats: inout ReadingStats, wpm: Double, now: Date = Date()) {
        startActivityIfNeeded(into: &stats, now: now)
        stats.today.articles += 1
        stats.today.minutes = estimatedMinutes(for: stats.today.words, wpm: wpm)
        stats.totalArticles += 1
        stats.avgWPM = Int(wpm.rounded())
        stats.bestWPM = max(stats.bestWPM, Int(wpm.rounded()))
    }

    static func startActivityIfNeeded(into stats: inout ReadingStats, now: Date = Date()) {
        rollStatsIfNeeded(into: &stats, now: now)
        let todayKey = dayKey(for: now)
        let alreadyActiveToday = stats.lastActiveDay == todayKey && (stats.today.words > 0 || stats.today.articles > 0)
        guard !alreadyActiveToday else { return }

        if let lastActiveDay = stats.lastActiveDay,
           let lastActiveDate = date(fromDayKey: lastActiveDay),
           Calendar.current.isDate(lastActiveDate, inSameDayAs: Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now) {
            stats.streak += 1
        } else {
            stats.streak = 1
        }
        stats.lastActiveDay = todayKey
    }

    static func rollStatsIfNeeded(into stats: inout ReadingStats, wpm: Double = 0, now: Date = Date()) {
        let todayKey = dayKey(for: now)
        let datedWeek = stats.week.filter { $0.date != nil }
        let wordsByDay = Dictionary(uniqueKeysWithValues: datedWeek.map { ($0.date ?? $0.day, $0.words) })
        stats.week = weekTemplate(endingAt: now).map { day in
            DayWords(date: day.date, day: day.day, words: wordsByDay[day.date ?? day.day] ?? 0)
        }

        if stats.lastActiveDay != todayKey {
            stats.today = TodayStats(words: wordsByDay[todayKey] ?? 0, minutes: 0, articles: 0)
        } else if let todayWords = stats.week.first(where: { $0.date == todayKey })?.words {
            stats.today.words = todayWords
        }
        stats.today.minutes = estimatedMinutes(for: stats.today.words, wpm: wpm)
    }

    // MARK: - Day-key helpers

    static func estimatedMinutes(for words: Int, wpm: Double) -> Int {
        guard words > 0 else { return 0 }
        return max(1, Int(ceil(RSVPEngine.estimateMinutes(wordCount: words, wpm: wpm))))
    }

    static func weekTemplate(endingAt date: Date) -> [DayWords] {
        let calendar = Calendar.current
        return (0..<7).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset - 6, to: date) else { return nil }
            return DayWords(date: dayKey(for: day), day: weekdayLabel(for: day), words: 0)
        }
    }

    static func dayKey(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    static func date(fromDayKey key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    static func weekdayLabel(for date: Date) -> String {
        let weekday = Calendar.current.component(.weekday, from: date)
        let symbols = Calendar.current.shortWeekdaySymbols
        return symbols.indices.contains(weekday - 1) ? symbols[weekday - 1] : ""
    }
}

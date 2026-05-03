import SwiftUI

struct StatsView: View {
    @EnvironmentObject private var store: ReadingStore

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                masthead
                VStack(spacing: 8) {
                    todayCard
                    weeklyChart
                    statGrid
                    weeklyNote
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 112)
        }
        .background(JRColor.paper)
    }

    private var masthead: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "This week")
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(store.stats.weekTotal.formatted())
                    .font(JRFont.serif(36, weight: .medium))
                    .tracking(-0.9)
                    .foregroundStyle(JRColor.ink)
                Text("words")
                    .font(JRFont.serif(36, weight: .regular))
                    .tracking(-0.9)
                    .foregroundStyle(JRColor.inkQuiet)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.75)

            Text(summaryLine)
                .font(JRFont.sans(14))
                .lineSpacing(4)
                .foregroundStyle(JRColor.inkMid)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 60)
        .padding(.horizontal, 24)
        .padding(.bottom, 18)
    }

    private var todayCard: some View {
        JRCard {
            HStack(spacing: 0) {
                TodayMetric(value: store.stats.today.words.formatted(), label: "words")
                Divider().frame(height: 42).overlay(JRColor.rule)
                TodayMetric(value: "\(store.stats.today.minutes)", label: "minutes")
                Divider().frame(height: 42).overlay(JRColor.rule)
                TodayMetric(value: "\(store.stats.today.articles)", label: "articles")
            }
        }
    }

    private var weeklyChart: some View {
        JRCard {
            let maxWords = max(store.stats.week.map(\.words).max() ?? 1, 1)
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(Array(store.stats.week.enumerated()), id: \.element.day) { index, day in
                    let isToday = index == store.stats.week.count - 1
                    VStack(spacing: 8) {
                        Rectangle()
                            .fill(isToday ? JRColor.terracotta : JRColor.ink.opacity(0.78))
                            .frame(height: max(4, CGFloat(day.words) / CGFloat(maxWords) * 112))
                            .clipShape(RoundedRectangle(cornerRadius: 1, style: .continuous))
                            .frame(maxHeight: 112, alignment: .bottom)

                        Text(day.day)
                            .font(JRFont.mono(10, weight: isToday ? .semibold : .regular))
                            .tracking(0.6)
                            .foregroundStyle(isToday ? JRColor.terracotta : JRColor.inkQuiet)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 130, alignment: .bottom)
        }
    }

    private var statGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            StatCard(label: "Streak", value: "\(store.stats.streak)", unit: "days")
            StatCard(label: "Avg pace", value: store.stats.avgWPM > 0 ? "\(store.stats.avgWPM)" : "—", unit: "wpm")
            StatCard(label: "Best pace", value: store.stats.bestWPM > 0 ? "\(store.stats.bestWPM)" : "—", unit: "wpm")
            StatCard(label: "Articles read", value: "\(store.stats.totalArticles)", unit: "total")
        }
    }

    private var weeklyNote: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "This week's note")
            Text(weeklyNoteText)
                .font(JRFont.serif(16))
                .lineSpacing(5)
                .foregroundStyle(JRColor.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.vertical, 20)
        .background(JRColor.paperStrong)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .stroke(JRColor.rule, lineWidth: 0.5)
        )
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(JRColor.terracotta)
                .frame(width: 3)
        }
        .padding(.top, 16)
    }

    private var summaryLine: String {
        guard store.stats.weekTotal > 0 else {
            return "Start reading to build a real weekly trend."
        }
        let pace = store.stats.avgWPM > 0 ? store.stats.avgWPM : Int(store.wpm)
        return "That's roughly \(String(format: "%.2f", Double(store.stats.weekTotal) / 60_000)) novellas at \(pace) wpm."
    }

    private var weeklyNoteText: String {
        guard store.stats.weekTotal > 0 else {
            return "No reading activity yet this week. Paste an article or fetch a URL and your real pace, streak, and article counts will appear here."
        }

        let activeDays = store.stats.week.filter { $0.words > 0 }.count
        let bestDay = store.stats.week.max { $0.words < $1.words }
        if let bestDay, bestDay.words > 0 {
            return "You read on \(activeDays) day\(activeDays == 1 ? "" : "s") this week. Your strongest day was \(bestDay.day) with \(bestDay.words.formatted()) words."
        }
        return "Your weekly trend is based only on words you actually read in JustRead."
    }
}

private struct TodayMetric: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 6) {
            Text(value)
                .font(JRFont.serif(26, weight: .medium))
                .tracking(-0.4)
                .foregroundStyle(JRColor.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(label)
                .font(JRFont.mono(10))
                .tracking(1.4)
                .foregroundStyle(JRColor.inkQuiet)
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct StatCard: View {
    let label: String
    let value: String
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(text: label)
            Text(value)
                .font(JRFont.serif(30, weight: .medium))
                .tracking(-0.5)
                .foregroundStyle(JRColor.ink)
                .padding(.top, 10)
            Text(unit)
                .font(JRFont.mono(10))
                .tracking(1.4)
                .foregroundStyle(JRColor.inkQuiet)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 16)
        .background(JRColor.paperStrong)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .stroke(JRColor.rule, lineWidth: 0.5)
        )
    }
}

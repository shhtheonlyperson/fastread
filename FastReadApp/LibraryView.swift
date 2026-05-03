import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var store: ReadingStore
    let onResume: () -> Void
    let onOpenArticle: (ReadingArticle) -> Void

    private var current: ReadingArticle? {
        store.currentArticle ?? store.articles.first { !$0.isFinished } ?? store.articles.first
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                masthead
                if let current {
                    continueCard(current)
                        .padding(.horizontal, 16)
                } else {
                    emptyContinueCard
                        .padding(.horizontal, 16)
                }
                libraryList
                    .padding(.top, 28)
                    .padding(.horizontal, 16)
            }
            .padding(.bottom, 112)
        }
        .background(JRColor.paper)
    }

    private var masthead: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(spacing: 10) {
                    BrandMark(size: 28)
                    Text("JustRead")
                        .font(JRFont.serif(19, weight: .semibold))
                        .tracking(-0.3)
                        .foregroundStyle(JRColor.ink)
                }

                Spacer()

                SectionLabel(text: Date().formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
            }
            .padding(.bottom, 18)

            Text("Today you've read")
                .font(JRFont.serif(38, weight: .medium))
                .tracking(-1)
                .lineSpacing(-1)
                .foregroundStyle(JRColor.ink)

            (
                Text(store.stats.today.words.formatted())
                    .foregroundStyle(JRColor.terracotta)
                + Text(" words.")
                    .foregroundStyle(JRColor.ink)
            )
            .font(JRFont.serif(38, weight: .medium))
            .tracking(-1)
            .lineSpacing(-1)

            Text("\(store.stats.today.minutes) minutes across \(store.stats.today.articles) articles. Streak: \(store.stats.streak) days.")
                .font(JRFont.sans(14))
                .foregroundStyle(JRColor.inkQuiet)
                .lineSpacing(4)
                .padding(.top, 10)
        }
        .padding(.top, 60)
        .padding(.horizontal, 24)
        .padding(.bottom, 18)
    }

    private func continueCard(_ current: ReadingArticle) -> some View {
        Button(action: onResume) {
            JRCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        SectionLabel(text: "Continue reading")
                        Spacer()
                        SectionLabel(
                            text: "\(Int(Double(max(current.wordCount, 1)) * current.progress)) of \(current.wordCount)",
                            color: JRColor.terracotta
                        )
                    }

                    Text(current.title)
                        .font(JRFont.serif(22, weight: .medium))
                        .tracking(-0.3)
                        .lineSpacing(1)
                        .foregroundStyle(JRColor.ink)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: 8) {
                        JRProgressBar(progress: current.progress)
                        Text("\(Int((current.progress * 100).rounded()))%")
                            .font(JRFont.mono(11))
                            .tracking(0.66)
                            .foregroundStyle(JRColor.inkQuiet)
                    }

                    HStack {
                        Text("\(current.source) · \(current.readTime)")
                            .font(JRFont.sans(13))
                            .foregroundStyle(JRColor.inkMid)

                        Spacer()

                        HStack(spacing: 6) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 10, weight: .semibold))
                            Text("Resume")
                                .font(JRFont.sans(13, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(JRColor.terracotta))
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var emptyContinueCard: some View {
        JRCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel(text: "Start reading")
                Text("Add your first article.")
                    .font(JRFont.serif(22, weight: .medium))
                    .tracking(-0.3)
                    .foregroundStyle(JRColor.ink)
                Text("Paste text or fetch a web page to build a real reading library.")
                    .font(JRFont.sans(13))
                    .lineSpacing(3)
                    .foregroundStyle(JRColor.inkMid)
            }
        }
    }

    private var libraryList: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                SectionLabel(text: "Library")
                Spacer()
                SectionLabel(text: "\(store.articles.count) items", color: JRColor.inkQuiet.opacity(0.5))
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 12)

            if store.articles.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No saved articles yet.")
                        .font(JRFont.serif(17, weight: .medium))
                        .foregroundStyle(JRColor.ink)
                    Text("Use the Add tab to paste text or fetch a URL. The library only shows your saved reading material.")
                        .font(JRFont.sans(13))
                        .lineSpacing(3)
                        .foregroundStyle(JRColor.inkQuiet)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 18)
                .background(JRColor.paperStrong)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(JRColor.rule, lineWidth: 0.5)
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(store.articles.enumerated()), id: \.element.id) { index, article in
                        Button {
                            onOpenArticle(article)
                        } label: {
                            ArticleRow(article: article)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .overlay(alignment: .top) {
                                    if index != 0 {
                                        Rectangle()
                                            .fill(JRColor.rule)
                                            .frame(height: 0.5)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(JRColor.paperStrong)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(JRColor.rule, lineWidth: 0.5)
                )
            }
        }
    }
}

private struct ArticleRow: View {
    let article: ReadingArticle

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                progressDot
                SectionLabel(text: article.tag)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(article.readTime)
                    .font(JRFont.mono(11))
                    .tracking(0.66)
                    .foregroundStyle(JRColor.inkQuiet)
            }

            Text(article.title)
                .font(JRFont.serif(16, weight: .medium))
                .tracking(-0.2)
                .lineSpacing(2)
                .foregroundStyle(JRColor.ink)
                .multilineTextAlignment(.leading)

            Text(article.lede)
                .font(JRFont.sans(13))
                .lineSpacing(3)
                .foregroundStyle(JRColor.inkMid)
                .multilineTextAlignment(.leading)
        }
    }

    private var progressDot: some View {
        Circle()
            .fill(dotFill)
            .frame(width: 8, height: 8)
            .overlay(
                Circle()
                    .stroke(article.progress == 0 ? JRColor.inkQuiet : Color.clear, lineWidth: 1)
            )
    }

    private var dotFill: Color {
        if article.progress >= 1 { return JRColor.inkQuiet }
        if article.progress > 0 { return JRColor.terracotta }
        return .clear
    }
}

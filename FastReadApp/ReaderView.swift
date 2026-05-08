import SwiftUI

struct ReaderView: View {
    @EnvironmentObject private var store: ReadingStore
    @State private var isTocOpen = false
    let onBack: () -> Void
    let onFocus: () -> Void

    private var frontMatter: Document.FrontMatterDetection? {
        store.currentFrontMatterDetection()
    }

    private var inFrontMatter: Bool {
        guard let fm = frontMatter, fm.hasSkippableFrontMatter else { return false }
        return store.currentIndex < fm.firstChapterTokenIndex
    }

    var body: some View {
        Group {
            if store.currentArticle == nil {
                emptyReader
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        header
                        if inFrontMatter, let fm = frontMatter {
                            skipIntroBanner(fm: fm)
                                .padding(.horizontal, 24)
                                .padding(.bottom, 12)
                        }
                        stageCard
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                        paceControl
                            .padding(.top, 22)
                    }
                    .padding(.bottom, 112)
                }
            }
        }
        .background(JRColor.paper)
        .sheet(isPresented: $isTocOpen) {
            TocDrawerView(
                isOpen: $isTocOpen,
                sections: store.currentArticle?.document.sections ?? [],
                boundaries: store.currentSectionBoundaries(),
                frontMatter: frontMatter,
                wordIndex: store.currentIndex,
                onSelect: { tokenIndex in
                    store.jumpToToken(tokenIndex)
                    isTocOpen = false
                },
                onSkipFrontMatter: {
                    if let fm = frontMatter, fm.hasSkippableFrontMatter {
                        store.jumpToToken(fm.firstChapterTokenIndex)
                    }
                    isTocOpen = false
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .onDisappear {
            if store.currentTokens.isEmpty {
                store.pause()
            }
        }
    }

    private func skipIntroBanner(fm: Document.FrontMatterDetection) -> some View {
        let count = fm.frontMatterSectionIds.count
        return HStack(spacing: 12) {
            Circle()
                .fill(JRColor.terracotta)
                .frame(width: 8, height: 8)
            Text("You're in front matter · \(count) section\(count == 1 ? "" : "s") look like cover, copyright, foreword.")
                .font(JRFont.sans(13))
                .foregroundStyle(JRColor.inkMid)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: {
                store.jumpToToken(fm.firstChapterTokenIndex)
            }) {
                Text("SKIP →")
                    .font(JRFont.mono(11, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(JRColor.terracotta)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(JRColor.terracotta.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(JRColor.terracotta.opacity(0.22), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var emptyReader: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel(text: "Reader")
            Text("Nothing queued.")
                .font(JRFont.serif(36, weight: .medium))
                .tracking(-0.9)
                .foregroundStyle(JRColor.ink)
            Text("Add text or fetch a URL first. The reader will open with your saved article and preserve progress locally.")
                .font(JRFont.sans(14))
                .lineSpacing(4)
                .foregroundStyle(JRColor.inkMid)
            Button(action: onBack) {
                Text("Back to library")
                    .font(JRFont.sans(14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(JRColor.ink)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.top, 60)
        .padding(.horizontal, 24)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button(action: onBack) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 9, weight: .bold))
                        SectionLabel(text: "Library")
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                if let document = store.currentArticle?.document, document.sections.count > 1 {
                    Button(action: { isTocOpen = true }) {
                        HStack(spacing: 6) {
                            SectionLabel(text: "Contents")
                            Image(systemName: "list.bullet")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(JRColor.inkMid)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open contents")
                }
            }

            Text(store.currentArticle?.title ?? "Untitled")
                .font(JRFont.serif(22, weight: .medium))
                .tracking(-0.4)
                .lineSpacing(1)
                .foregroundStyle(JRColor.ink)
                .padding(.top, 12)

            Text(articleMeta)
                .font(JRFont.sans(12))
                .foregroundStyle(JRColor.inkQuiet)
                .lineLimit(1)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 60)
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
    }

    private var stageCard: some View {
        JRCard(padding: 0) {
            VStack(spacing: 0) {
                ZStack {
                    RSVPStage(
                        token: store.currentToken,
                        focusStyle: store.focusIndicator
                    )
                    .frame(minHeight: 180)

                    EnterFocusPlayButton(action: onFocus)
                }
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 8)

                progressScrubber
                    .padding(.horizontal, 16)
                    .padding(.bottom, store.currentIndex >= store.currentTokens.count - 1 ? 12 : 20)

                if store.currentIndex >= store.currentTokens.count - 1, !store.currentTokens.isEmpty {
                    doneStrip
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                }
            }
        }
    }

    private var progressScrubber: some View {
        VStack(spacing: 8) {
            Slider(
                value: Binding(
                    get: { store.readerProgress },
                    set: { store.scrub(to: $0) }
                ),
                in: 0...1
            )
            .tint(JRColor.terracotta)
            .frame(height: 18)

            HStack {
                Text("\(store.currentIndex + 1) / \(max(store.currentTokens.count, 1))")
                Spacer()
                Text(minutesLeftLabel)
            }
            .font(JRFont.mono(11))
            .tracking(0.66)
            .foregroundStyle(JRColor.inkQuiet)
        }
    }

    private var doneStrip: some View {
        HStack(spacing: 10) {
            Text("Done · \(store.currentTokens.count) words in \(Int(ceil(RSVPEngine.estimateMinutes(wordCount: store.currentTokens.count, wpm: store.wpm)))) minutes")
                .font(JRFont.mono(11, weight: .medium))
                .tracking(0.66)
                .foregroundStyle(JRColor.inkQuiet)
                .lineLimit(2)

            Spacer()

            Button("Mark read") {
                store.markRead()
            }
            .font(JRFont.sans(13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule().fill(JRColor.terracotta))
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(JRColor.paperDeep.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }

    private var paceControl: some View {
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                SectionLabel(text: "Pace")
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(Int(store.wpm.rounded()))")
                        .font(JRFont.serif(22, weight: .semibold))
                        .foregroundStyle(JRColor.ink)
                    Text("wpm")
                        .font(JRFont.mono(11))
                        .tracking(1.54)
                        .foregroundStyle(JRColor.inkQuiet)
                }
            }

            Slider(
                value: Binding(
                    get: { store.wpm },
                    set: { store.setWPM($0) }
                ),
                in: 150...1_000
            )
            .tint(JRColor.terracotta)

            HStack {
                Text("150")
                Spacer()
                Text("500")
                Spacer()
                Text("1000")
            }
            .font(JRFont.mono(10))
            .tracking(0.6)
            .foregroundStyle(JRColor.inkQuiet)
        }
        .padding(.horizontal, 24)
    }

    private var minutesLeftLabel: String {
        let minutes = store.minutesRemaining
        return minutes < 1 ? "\(Int(ceil(minutes * 60)))s left" : "\(String(format: "%.1f", minutes))m left"
    }

    private var articleMeta: String {
        guard let article = store.currentArticle else { return "" }
        return "\(article.source) · \(article.author) · \(article.date)"
    }
}

struct FocusModeView: View {
    @EnvironmentObject private var store: ReadingStore
    @Binding var isPresented: Bool

    var body: some View {
        ZStack {
            JRColor.focusDark.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("FOCUS · \(Int(store.wpm.rounded())) WPM")
                            .font(JRFont.mono(10, weight: .medium))
                            .tracking(1.4)
                            .foregroundStyle(JRColor.paper.opacity(0.5))
                        Text(store.currentArticle?.title ?? "No article")
                            .font(JRFont.serif(14))
                            .foregroundStyle(JRColor.paper.opacity(0.85))
                            .lineLimit(1)
                    }

                    Spacer()

                    Button {
                        isPresented = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(JRColor.paper)
                            .frame(width: 40, height: 40)
                            .background(JRColor.paper.opacity(0.10))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
                .padding(.top, 56)

                RSVPStage(
                    token: store.currentToken,
                    focusStyle: store.focusIndicator,
                    isBig: true,
                    isDark: true
                )
                .frame(maxHeight: .infinity)
                .padding(.horizontal, 12)

                focusTransport
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            store.pause()
        }
        .focusStatusBarHidden()
    }

    private var focusTransport: some View {
        VStack(spacing: 18) {
            VStack(spacing: 6) {
                JRProgressBar(progress: store.readerProgress, track: JRColor.paper.opacity(0.15))
                HStack {
                    Text("\(store.currentIndex + 1) / \(max(store.currentTokens.count, 1))")
                    Spacer()
                    Text("\(Int((store.readerProgress * 100).rounded()))%")
                }
                .font(JRFont.mono(10))
                .tracking(0.6)
                .foregroundStyle(JRColor.paper.opacity(0.5))
            }

            HStack(spacing: 14) {
                DarkTransportButton {
                    store.move(by: -10)
                } content: {
                    Image(systemName: "backward.end.fill")
                }

                DarkTransportButton(size: 40) {
                    store.move(by: -1)
                } content: {
                    Image(systemName: "backward.fill")
                }

                Button {
                    store.togglePlay()
                } label: {
                    Image(systemName: store.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 72, height: 72)
                        .background(JRColor.terracotta)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                DarkTransportButton(size: 40) {
                    store.move(by: 1)
                } content: {
                    Image(systemName: "forward.fill")
                }

                DarkTransportButton {
                    store.move(by: 10)
                } content: {
                    Image(systemName: "forward.end.fill")
                }
            }
        }
    }
}

private extension View {
    @ViewBuilder
    func focusStatusBarHidden() -> some View {
#if os(iOS)
        statusBarHidden(true)
#else
        self
#endif
    }
}

struct RSVPStage: View {
    let token: String
    let focusStyle: FocusIndicatorStyle
    var isBig = false
    var isDark = false

    private var split: RSVPEngine.FocusSplit {
        RSVPEngine.splitForFocus(token)
    }

    var body: some View {
        ZStack {
            FocusIndicator(style: focusStyle, isDark: isDark)

            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(split.before)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .foregroundStyle(wordColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(split.focus)
                    .foregroundStyle(JRColor.terracotta)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                Text(split.after)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(wordColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            .font(stageFont)
            .tracking(-0.5)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: isBig ? 220 : 180)
    }

    private var wordColor: Color {
        isDark ? JRColor.paper : JRColor.ink
    }

    private var stageFont: Font {
        let size: CGFloat = isBig ? 76 : 54
        return JRFont.serif(size, weight: .medium)
    }
}

private struct FocusIndicator: View {
    let style: FocusIndicatorStyle
    let isDark: Bool

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                switch style {
                case .dot:
                    Circle()
                        .fill(JRColor.terracotta)
                        .frame(width: 4, height: 4)
                        .position(x: proxy.size.width / 2, y: 22)
                    Circle()
                        .fill(JRColor.terracotta)
                        .frame(width: 4, height: 4)
                        .position(x: proxy.size.width / 2, y: proxy.size.height - 22)
                case .line:
                    Rectangle()
                        .fill(JRColor.terracotta.opacity(isDark ? 0.55 : 0.4))
                        .frame(width: 0.5)
                        .padding(.vertical, 12)
                        .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                case .crosshair:
                    Rectangle()
                        .fill((isDark ? JRColor.paper : JRColor.ink).opacity(isDark ? 0.18 : 0.15))
                        .frame(width: 0.5)
                        .padding(.vertical, 12)
                        .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                    Rectangle()
                        .fill((isDark ? JRColor.paper : JRColor.ink).opacity(0.08))
                        .frame(height: 0.5)
                        .padding(.horizontal, 24)
                        .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                }
            }
        }
    }
}

private struct EnterFocusPlayButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "play.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(JRColor.ink.opacity(0.34))
                .padding(.leading, 2)
                .frame(width: 52, height: 52)
                .background(JRColor.ink.opacity(0.035))
                .clipShape(Circle())
                .overlay(Circle().stroke(JRColor.ink.opacity(0.10), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Play in focus mode")
    }
}

private struct DarkTransportButton<Content: View>: View {
    var size: CGFloat = 48
    let action: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        Button(action: action) {
            content
                .font(.system(size: size == 40 ? 10 : 14, weight: .semibold))
                .foregroundStyle(JRColor.paper)
                .frame(width: size, height: size)
                .background(JRColor.paper.opacity(0.08))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

private struct TocDrawerView: View {
    @Binding var isOpen: Bool
    let sections: [Section]
    let boundaries: [Document.SectionBoundary]
    let frontMatter: Document.FrontMatterDetection?
    let wordIndex: Int
    let onSelect: (Int) -> Void
    let onSkipFrontMatter: () -> Void

    private var totalTokens: Int {
        boundaries.last?.tokenEnd ?? 0
    }

    private var progressPct: Int {
        guard totalTokens > 0 else { return 0 }
        return Int((Double(wordIndex) / Double(totalTokens)) * 100.0)
    }

    private var skipCount: Int {
        frontMatter?.frontMatterSectionIds.count ?? 0
    }

    private var currentIndex: Int {
        for (i, b) in boundaries.enumerated() {
            if wordIndex >= b.tokenStart && wordIndex < b.tokenEnd {
                return i
            }
        }
        return max(boundaries.count - 1, 0)
    }

    private var canSkipFrontMatter: Bool {
        guard let fm = frontMatter, fm.hasSkippableFrontMatter else { return false }
        return wordIndex < fm.firstChapterTokenIndex
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom) {
                Text("Contents")
                    .font(JRFont.serif(22, weight: .bold))
                    .foregroundStyle(JRColor.ink)
                Spacer()
                Button("Close") { isOpen = false }
                    .font(JRFont.mono(11))
                    .tracking(1.4)
                    .foregroundStyle(JRColor.inkMid)
                    .textCase(.uppercase)
            }
            .padding(.top, 18)
            .padding(.horizontal, 22)
            .padding(.bottom, 14)
            .overlay(
                Rectangle()
                    .fill(JRColor.rule)
                    .frame(height: 1)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            )

            Text("\(progressPct)% · \(wordIndex.formatted()) of \(totalTokens.formatted()) words")
                .font(JRFont.mono(11))
                .tracking(1.4)
                .textCase(.uppercase)
                .foregroundStyle(JRColor.inkQuiet)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 22)
                .padding(.top, 12)
                .padding(.bottom, 4)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(sections.enumerated()), id: \.element.id) { i, section in
                        let b = i < boundaries.count ? boundaries[i] : Document.SectionBoundary(sectionId: section.id, tokenStart: 0, tokenEnd: 0)
                        let units = b.tokenEnd - b.tokenStart
                        let isFront = (frontMatter?.frontMatterSectionIds ?? []).contains(section.id)
                        let isCurrent = i == currentIndex
                        let isRead = !isCurrent && wordIndex >= b.tokenEnd && b.tokenEnd > 0
                        let display = labelForSection(
                            index: i,
                            isFront: isFront,
                            isCurrent: isCurrent,
                            isRead: isRead,
                            units: units,
                            boundary: b
                        )

                        Button(action: { onSelect(b.tokenStart) }) {
                            HStack(spacing: 10) {
                                Text(display.number)
                                    .font(JRFont.mono(11))
                                    .foregroundStyle(isCurrent ? JRColor.terracotta : JRColor.inkQuiet)
                                    .frame(width: 30, alignment: .leading)
                                Text(section.title.isEmpty ? "Untitled section" : section.title)
                                    .font(JRFont.serif(15, weight: isCurrent ? .semibold : .regular))
                                    .foregroundStyle(isCurrent ? JRColor.terracotta : (isFront ? JRColor.inkQuiet : JRColor.ink))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .lineLimit(2)
                                Text(display.pct)
                                    .font(JRFont.mono(10.5, weight: isCurrent ? .bold : .regular))
                                    .foregroundStyle(isCurrent ? JRColor.terracotta : JRColor.inkQuiet)
                            }
                            .padding(.horizontal, 22)
                            .padding(.vertical, 12)
                            .background(isCurrent ? JRColor.terracotta.opacity(0.08) : .clear)
                            .overlay(
                                Rectangle()
                                    .fill(JRColor.rule)
                                    .frame(height: 1)
                                    .frame(maxHeight: .infinity, alignment: .bottom)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 24)
            }

            if canSkipFrontMatter {
                Button(action: onSkipFrontMatter) {
                    Text("SKIP FRONT MATTER →")
                        .font(JRFont.mono(11, weight: .bold))
                        .tracking(2)
                        .textCase(.uppercase)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(JRColor.terracotta)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 28)
                .background(JRColor.paper)
                .overlay(
                    Rectangle()
                        .fill(JRColor.rule)
                        .frame(height: 1)
                        .frame(maxHeight: .infinity, alignment: .top)
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(JRColor.paper)
    }

    private func labelForSection(
        index: Int,
        isFront: Bool,
        isCurrent: Bool,
        isRead: Bool,
        units: Int,
        boundary: Document.SectionBoundary
    ) -> (number: String, pct: String) {
        let number: String
        if isFront {
            number = "—"
        } else {
            let chapterOrdinal = max(index - skipCount + 1, 1)
            number = String(format: "%02d", chapterOrdinal)
        }
        let pct: String
        if units == 0 {
            pct = "—"
        } else if isFront && wordIndex >= boundary.tokenEnd {
            pct = "✓"
        } else if isCurrent {
            let local = max(wordIndex - boundary.tokenStart, 0)
            let pctValue = Int((Double(local) / Double(max(units, 1))) * 100.0)
            pct = "\(pctValue)%"
        } else if isRead {
            pct = "100%"
        } else {
            pct = "—"
        }
        return (number, pct)
    }
}

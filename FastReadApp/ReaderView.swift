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
        GeometryReader { proxy in
            let isLandscape = proxy.size.width > proxy.size.height
            Group {
                if store.currentArticle == nil {
                    emptyReader
                } else if isLandscape {
                    landscapeReader
                } else {
                    portraitReader
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .background(JRColor.paper)
        .overlay(alignment: .bottom) {
            if isTocOpen {
                tocOverlay
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .zIndex(20)
            }
        }
        .onDisappear {
            if store.currentTokens.isEmpty {
                store.pause()
            }
        }
    }

    private var portraitReader: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                header()
                if inFrontMatter, let fm = frontMatter {
                    skipIntroBanner(fm: fm)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 12)
                }
                stageCard()
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                ReaderPaceControl()
                    .padding(.top, 22)
            }
            .padding(.bottom, 112)
        }
    }

    private var landscapeReader: some View {
        VStack(spacing: 8) {
            header(compact: true)
            if inFrontMatter, let fm = frontMatter {
                skipIntroBanner(fm: fm)
                    .padding(.bottom, 2)
            }
            stageCard(compact: true)
            ReaderPaceControl(compact: true)
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .clipped()
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

    private var tocOverlay: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                JRColor.ink.opacity(0.18)
                    .ignoresSafeArea()
                    .onTapGesture {
                        closeToc()
                    }

                TocDrawerView(
                    isOpen: $isTocOpen,
                    sections: store.currentArticle?.document.sections ?? [],
                    boundaries: store.currentSectionBoundaries(),
                    frontMatter: frontMatter,
                    wordIndex: store.currentIndex,
                    onSelect: { tokenIndex in
                        store.jumpToToken(tokenIndex)
                        closeToc()
                    },
                    onSkipFrontMatter: {
                        if let fm = frontMatter, fm.hasSkippableFrontMatter {
                            store.jumpToToken(fm.firstChapterTokenIndex)
                        }
                        closeToc()
                    }
                )
                .frame(maxHeight: min(proxy.size.height - 16, max(proxy.size.height * 0.82, 420)))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(JRColor.rule, lineWidth: 1)
                )
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
        }
        .ignoresSafeArea()
    }

    private func closeToc() {
        withAnimation(.easeOut(duration: 0.12)) {
            isTocOpen = false
        }
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
                    .foregroundStyle(JRColor.onPrimary)
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

    private func header(compact: Bool = false) -> some View {
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
                    Button(action: {
                        withAnimation(.easeOut(duration: 0.14)) {
                            isTocOpen = true
                        }
                    }) {
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
                .font(JRFont.serif(compact ? 18 : 22, weight: .medium))
                .tracking(-0.4)
                .lineSpacing(1)
                .foregroundStyle(JRColor.ink)
                .lineLimit(compact ? 1 : 2)
                .padding(.top, compact ? 6 : 12)

            Text(articleMeta)
                .font(JRFont.sans(12))
                .foregroundStyle(JRColor.inkQuiet)
                .lineLimit(1)
                .padding(.top, compact ? 3 : 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, compact ? 0 : 60)
        .padding(.horizontal, compact ? 0 : 24)
        .padding(.bottom, compact ? 4 : 16)
    }

    private func stageCard(compact: Bool = false) -> some View {
        JRCard(padding: 0) {
            VStack(spacing: 0) {
                ZStack {
                    RSVPStage(
                        token: store.currentToken,
                        focusStyle: store.focusIndicator
                    )
                    .frame(minHeight: compact ? 112 : 180)

                    EnterFocusPlayButton(action: onFocus, compact: compact)
                }
                .padding(.horizontal, compact ? 12 : 16)
                .padding(.top, compact ? 8 : 20)
                .padding(.bottom, compact ? 4 : 8)

                progressScrubber
                    .padding(.horizontal, compact ? 12 : 16)
                    .padding(.bottom, compact ? 10 : (store.currentIndex >= store.currentTokens.count - 1 ? 12 : 20))

                if !compact, store.currentIndex >= store.currentTokens.count - 1, !store.currentTokens.isEmpty {
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
            .foregroundStyle(JRColor.onPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule().fill(JRColor.terracotta))
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(JRColor.paperDeep.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
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

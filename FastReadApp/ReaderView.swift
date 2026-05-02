import SwiftUI

struct ReaderView: View {
    @EnvironmentObject private var store: ReadingStore
    let onBack: () -> Void
    let onFocus: () -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                header
                stageCard
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                transport
                    .padding(.top, 18)
                paceControl
                    .padding(.top, 22)
                fullText
                    .padding(.top, 24)
            }
            .padding(.bottom, 112)
        }
        .background(JRColor.paper)
        .onDisappear {
            if store.currentTokens.isEmpty {
                store.pause()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onBack) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 9, weight: .bold))
                    SectionLabel(text: "Library")
                }
            }
            .buttonStyle(.plain)

            Text(store.currentArticle.title)
                .font(JRFont.serif(22, weight: .medium))
                .tracking(-0.4)
                .lineSpacing(1)
                .foregroundStyle(JRColor.ink)
                .padding(.top, 12)

            Text("\(store.currentArticle.source) · \(store.currentArticle.author) · \(store.currentArticle.date)")
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
                RSVPStage(
                    token: store.currentToken,
                    focusStyle: store.focusIndicator,
                    wordTypeface: store.wordTypeface
                )
                .frame(minHeight: 180)
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

    private var transport: some View {
        HStack(spacing: 14) {
            TransportButton(label: "Back 10") {
                store.move(by: -10)
            } content: {
                Image(systemName: "gobackward.10")
                    .font(.system(size: 18, weight: .semibold))
            }

            TransportButton(label: "Previous word") {
                store.move(by: -1)
            } content: {
                Image(systemName: "backward.end.fill")
                    .font(.system(size: 14, weight: .semibold))
            }

            Button {
                store.togglePlay()
            } label: {
                Image(systemName: store.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .background(JRColor.terracotta)
                    .clipShape(Circle())
                    .shadow(color: JRColor.terracotta.opacity(0.32), radius: 14, y: 4)
            }
            .buttonStyle(.plain)

            TransportButton(label: "Next word") {
                store.move(by: 1)
            } content: {
                Image(systemName: "forward.end.fill")
                    .font(.system(size: 14, weight: .semibold))
            }

            TransportButton(label: "Focus mode", action: onFocus) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 16, weight: .semibold))
            }
        }
        .padding(.horizontal, 24)
    }

    private var paceControl: some View {
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                SectionLabel(text: "Pace")
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(Int(store.wpm))")
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
                in: 150...1_000,
                step: 25
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

    private var fullText: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "The full text")
            FullTextPreview(tokens: store.currentTokens, currentIndex: store.currentIndex)
                .font(JRFont.serif(15.5))
                .lineSpacing(5)
                .foregroundStyle(JRColor.inkMid)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
    }

    private var minutesLeftLabel: String {
        let minutes = store.minutesRemaining
        return minutes < 1 ? "\(Int(ceil(minutes * 60)))s left" : "\(String(format: "%.1f", minutes))m left"
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
                        Text("FOCUS · \(Int(store.wpm)) WPM")
                            .font(JRFont.mono(10, weight: .medium))
                            .tracking(1.4)
                            .foregroundStyle(JRColor.paper.opacity(0.5))
                        Text(store.currentArticle.title)
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
                    wordTypeface: store.wordTypeface,
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
    let wordTypeface: WordTypeface
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
        switch wordTypeface {
        case .serif:
            return JRFont.serif(size, weight: .medium)
        case .sans:
            return JRFont.sans(size, weight: .medium)
        case .mono:
            return JRFont.mono(size, weight: .medium)
        }
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

private struct TransportButton<Content: View>: View {
    let label: String
    let action: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        Button(action: action) {
            content
                .foregroundStyle(JRColor.ink)
                .frame(width: 44, height: 44)
                .background(Color.clear)
                .clipShape(Circle())
                .overlay(Circle().stroke(JRColor.ruleStrong, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
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

private struct FullTextPreview: View {
    let tokens: [String]
    let currentIndex: Int

    var body: some View {
        previewText
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var previewText: Text {
        tokens.enumerated().reduce(Text("")) { partial, item in
            let index = item.offset
            let split = RSVPEngine.splitForFocus(item.element)
            let isCurrent = index == currentIndex
            let isRead = index < currentIndex
            let baseColor = isRead ? JRColor.inkQuiet : isCurrent ? JRColor.ink : JRColor.inkMid
            return partial
                + Text(split.before).foregroundColor(baseColor).fontWeight(isCurrent ? .semibold : .regular)
                + Text(split.focus).foregroundColor(JRColor.terracotta).fontWeight(.semibold)
                + Text(split.after + " ").foregroundColor(baseColor).fontWeight(isCurrent ? .semibold : .regular)
        }
    }
}

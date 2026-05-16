import SwiftUI

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
        .accessibilityElement(children: .combine)
        .accessibilityLabel(token)
        .accessibilityIdentifier("rsvp-current-token")
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

struct EnterFocusPlayButton: View {
    let action: () -> Void
    var compact = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(.regularMaterial)
                    .frame(width: compact ? 72 : 88, height: compact ? 72 : 88)
                    .shadow(color: JRColor.ink.opacity(0.16), radius: 16, x: 0, y: 8)

                Circle()
                    .fill(JRColor.terracotta.opacity(0.94))
                    .frame(width: compact ? 56 : 66, height: compact ? 56 : 66)

                Image(systemName: "play.fill")
                    .font(.system(size: compact ? 22 : 26, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.leading, 3)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Play in focus mode")
    }
}

struct DarkTransportButton<Content: View>: View {
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

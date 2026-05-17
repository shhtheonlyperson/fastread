import SwiftUI

enum JRColor {
    static let primary = Color(hex: 0xCC785C)
    static let primaryActive = Color(hex: 0xA9583E)
    static let primaryDisabled = Color(hex: 0xE6DFD8)
    static let ink = Color(hex: 0x141413)
    static let body = Color(hex: 0x3D3D3A)
    static let bodyStrong = Color(hex: 0x252523)
    static let muted = Color(hex: 0x6C6A64)
    static let mutedSoft = Color(hex: 0x8E8B82)
    static let hairline = Color(hex: 0xE6DFD8)
    static let hairlineSoft = Color(hex: 0xEBE6DF)
    static let canvas = Color(hex: 0xFAF9F5)
    static let surfaceSoft = Color(hex: 0xF5F0E8)
    static let surfaceCard = Color(hex: 0xEFE9DE)
    static let surfaceCreamStrong = Color(hex: 0xE8E0D2)
    static let surfaceDark = Color(hex: 0x181715)
    static let surfaceDarkElevated = Color(hex: 0x252320)
    static let surfaceDarkSoft = Color(hex: 0x1F1E1B)
    static let onPrimary = Color(hex: 0xFFFFFF)
    static let onDark = Color(hex: 0xFAF9F5)
    static let onDarkSoft = Color(hex: 0xA09D96)
    static let accentTeal = Color(hex: 0x5DB8A6)
    static let accentAmber = Color(hex: 0xE8A55A)
    static let success = Color(hex: 0x5DB872)
    static let warning = Color(hex: 0xD4A017)
    static let error = Color(hex: 0xC64545)

    static let paper = canvas
    static let paperStrong = surfaceSoft
    static let paperDeep = surfaceCard
    static let inkMid = body
    static let inkQuiet = muted
    static let rule = hairline
    static let ruleStrong = surfaceCreamStrong
    static let terracotta = primary
    static let focusDark = surfaceDark
}

enum JRFont {
    static func serif(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("Fraunces", size: size).weight(weight)
    }

    static func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("Inter", size: size).weight(weight)
    }

    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("JetBrains Mono", size: size).weight(weight)
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255,
            opacity: opacity
        )
    }
}

struct SectionLabel: View {
    let text: String
    var color: Color = JRColor.inkQuiet

    var body: some View {
        Text(text.uppercased())
            .font(JRFont.mono(11, weight: .medium))
            .tracking(1.54)
            .foregroundStyle(color)
            .lineLimit(1)
    }
}

struct JRCard<Content: View>: View {
    var padding: CGFloat = 18
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(padding)
            .background(JRColor.paperStrong)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(JRColor.rule, lineWidth: 0.5)
            )
    }
}

struct JRProgressBar: View {
    let progress: Double
    var height: CGFloat = 2
    var track: Color = JRColor.rule

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule()
                    .fill(JRColor.terracotta)
                    .frame(width: max(0, min(1, progress)) * proxy.size.width)
            }
        }
        .frame(height: height)
    }
}

struct BrandMark: View {
    var size: CGFloat = 56

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [JRColor.canvas, JRColor.surfaceCard, JRColor.surfaceCreamStrong],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 7) {
                ForEach(0..<Int(size / 8 + 2), id: \.self) { _ in
                    Rectangle()
                        .fill(JRColor.ink.opacity(0.025))
                        .frame(height: 1)
                    Spacer(minLength: 0)
                }
            }
            .opacity(0.7)

            HStack(alignment: .lastTextBaseline, spacing: -size * 0.10) {
                Text("J")
                    .font(JRFont.sans(size * 0.46, weight: .medium))
                    .foregroundStyle(JRColor.ink.opacity(0.55))
                Text("R")
                    .font(JRFont.serif(size * 0.50, weight: .bold))
                    .foregroundStyle(JRColor.terracotta)
            }
            .tracking(-size * 0.01)
            .offset(x: size * 0.02, y: size * 0.02)

            Circle()
                .fill(JRColor.terracotta)
                .frame(width: size * 0.11, height: size * 0.11)
                .offset(x: size * 0.28, y: -size * 0.21)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                .stroke(JRColor.ink.opacity(0.08), lineWidth: 0.5)
        )
    }
}

struct TabGlyph: View {
    let tab: AppTab
    let color: Color

    var body: some View {
        ZStack {
            switch tab {
            case .home:
                HStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 1)
                        .stroke(color, lineWidth: 1.4)
                        .frame(width: 7, height: 14)
                    RoundedRectangle(cornerRadius: 1)
                        .stroke(color, lineWidth: 1.4)
                        .frame(width: 7, height: 14)
                }
            case .source:
                Circle()
                    .stroke(color, lineWidth: 1.4)
                    .frame(width: 16, height: 16)
                Rectangle()
                    .fill(color)
                    .frame(width: 8, height: 1.4)
                Rectangle()
                    .fill(color)
                    .frame(width: 1.4, height: 8)
            case .reader:
                Rectangle()
                    .stroke(color, lineWidth: 1.4)
                    .frame(width: 12, height: 12)
                Circle()
                    .fill(color)
                    .frame(width: 4, height: 4)
            case .stats:
                HStack(alignment: .bottom, spacing: 4) {
                    Capsule().fill(color).frame(width: 1.4, height: 8)
                    Capsule().fill(color).frame(width: 1.4, height: 13)
                    Capsule().fill(color).frame(width: 1.4, height: 7)
                    Capsule().fill(color).frame(width: 1.4, height: 10)
                }
            case .settings:
                SettingsGlyph(color: color)
            }
        }
        .frame(width: 22, height: 22)
    }
}

private struct SettingsGlyph: View {
    let color: Color

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            var path = Path()
            path.addEllipse(in: CGRect(x: center.x - 3, y: center.y - 3, width: 6, height: 6))
            context.stroke(path, with: .color(color), lineWidth: 1.4)

            let lines: [(CGPoint, CGPoint)] = [
                (CGPoint(x: 11, y: 2), CGPoint(x: 11, y: 5)),
                (CGPoint(x: 11, y: 17), CGPoint(x: 11, y: 20)),
                (CGPoint(x: 2, y: 11), CGPoint(x: 5, y: 11)),
                (CGPoint(x: 17, y: 11), CGPoint(x: 20, y: 11)),
                (CGPoint(x: 4.5, y: 4.5), CGPoint(x: 6.6, y: 6.6)),
                (CGPoint(x: 15.4, y: 15.4), CGPoint(x: 17.5, y: 17.5)),
                (CGPoint(x: 4.5, y: 17.5), CGPoint(x: 6.6, y: 15.4)),
                (CGPoint(x: 15.4, y: 6.6), CGPoint(x: 17.5, y: 4.5)),
            ]

            for line in lines {
                var linePath = Path()
                linePath.move(to: line.0)
                linePath.addLine(to: line.1)
                context.stroke(linePath, with: .color(color), lineWidth: 1.4)
            }
        }
    }
}

struct Chevron: View {
    var color: Color = JRColor.inkQuiet

    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(color)
    }
}

extension View {
    func paperBackground() -> some View {
        background(JRColor.paper.ignoresSafeArea())
    }

    @ViewBuilder
    func borderBeam(
        border: Color = .primary,
        hideFadeBorder: Bool = false,
        beam: [Color] = [JRColor.primary, JRColor.accentAmber],
        beamBlur: CGFloat = 10,
        cornerRadius: CGFloat = 20,
        isEnabled: Bool = true
    ) -> some View {
        modifier(
            BorderBeamEffect(
                border: border,
                hideFadeBorder: hideFadeBorder,
                beam: beam,
                beamBlur: beamBlur,
                cornerRadius: cornerRadius,
                isEnabled: isEnabled
            )
        )
    }
}

private struct BorderBeamEffect: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var border: Color
    var hideFadeBorder: Bool
    var beam: [Color]
    var beamBlur: CGFloat
    var cornerRadius: CGFloat
    var isEnabled: Bool

    func body(content: Content) -> some View {
        content
            .overlay {
                ZStack {
                    if !hideFadeBorder {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(border.opacity(0.22), lineWidth: 0.6)
                    }

                    if isEnabled && !reduceMotion {
                        KeyframeAnimator(initialValue: 0.0, repeating: true) { value in
                            let rotation = value * 360
                            let borderGradient = AngularGradient(
                                colors: [.clear, border, .clear],
                                center: .center,
                                startAngle: .degrees(140 + rotation),
                                endAngle: .degrees(270 + rotation)
                            )
                            let beamGradient = LinearGradient(
                                colors: beam,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )

                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .fill(beamGradient)
                                .mask {
                                    ZStack {
                                        Rectangle()
                                            .fill(JRColor.onPrimary)
                                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                            .inset(by: max(1, beamBlur / 3))
                                            .fill(JRColor.onPrimary)
                                            .blur(radius: beamBlur)
                                            .blendMode(.destinationOut)
                                    }
                                    .compositingGroup()
                                }
                                .mask {
                                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                        .stroke(borderGradient, lineWidth: 2.4)
                                }
                        } keyframes: { _ in
                            LinearKeyframe(1, duration: 2.5)
                        }
                    }
                }
                .allowsHitTesting(false)
            }
    }
}

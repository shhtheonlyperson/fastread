import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: ReadingStore
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                masthead

                VStack(spacing: 22) {
                    paceGroup
                    SettingsGroup(label: "Focus indicator") {
                        SegmentedControl(selection: $store.focusIndicator, options: FocusIndicatorStyle.allCases)
                    }
                    SettingsGroup(label: "Word typeface") {
                        SegmentedControl(selection: $store.wordTypeface, options: WordTypeface.allCases)
                    }
                    aboutGroup
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 112)
        }
        .background(JRColor.paper)
    }

    private var masthead: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Settings")
            Text("The shape\nof your read.")
                .font(JRFont.serif(36, weight: .medium))
                .tracking(-0.9)
                .lineSpacing(-1)
                .foregroundStyle(JRColor.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 60)
        .padding(.horizontal, 24)
        .padding(.bottom, 18)
    }

    private var paceGroup: some View {
        SettingsGroup(label: "Pace") {
            SettingsRow {
                Text("Words per minute")
                Spacer()
                Text("\(Int(store.wpm.rounded()))")
                    .font(JRFont.serif(18, weight: .semibold))
            }

            VStack(spacing: 2) {
                Slider(
                    value: Binding(
                        get: { store.wpm },
                        set: { store.setWPM($0) }
                    ),
                    in: 150...1_000
                )
                .tint(JRColor.terracotta)

                HStack {
                    Text("Slow · 150")
                    Spacer()
                    Text("Comfortable · 500")
                    Spacer()
                    Text("Sprint · 1000")
                }
                .font(JRFont.mono(10))
                .tracking(0.6)
                .foregroundStyle(JRColor.inkQuiet)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)

            SettingsRow(isLast: true) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pause on punctuation")
                    Text("Slows down at periods, commas, and semicolons.")
                        .font(JRFont.sans(12))
                        .foregroundStyle(JRColor.inkQuiet)
                }
                Spacer()

                Toggle("", isOn: $store.punctuationPause)
                    .labelsHidden()
                    .tint(JRColor.terracotta)
            }
        }
    }

    private var aboutGroup: some View {
        SettingsGroup(label: "About") {
            SettingsRow {
                Text("Version")
                Spacer()
                Text(appVersion)
                    .font(JRFont.mono(13))
                    .foregroundStyle(JRColor.inkQuiet)
            }
            SettingsRow {
                Text("Privacy policy")
                Spacer()
                Text("Local data only")
                    .font(JRFont.mono(13))
                    .foregroundStyle(JRColor.inkQuiet)
            }
            SettingsRow(isLast: true) {
                Text("Send feedback")
                Spacer()
                Button {
                    if let url = URL(string: "mailto:huge.huang@gmail.com?subject=JustRead%20feedback") {
                        openURL(url)
                    }
                } label: {
                    Chevron()
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.2.0"
    }
}

private struct SettingsGroup<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: label)
                .padding(.horizontal, 8)

            VStack(spacing: 0) {
                content
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

private struct SettingsRow<Content: View>: View {
    var isLast = false
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 14) {
            content
        }
        .font(JRFont.sans(15))
        .foregroundStyle(JRColor.ink)
        .frame(minHeight: 52)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle()
                    .fill(JRColor.rule)
                    .frame(height: 0.5)
            }
        }
    }
}

private protocol SegmentedOption: Identifiable, Hashable {
    var label: String { get }
}

extension FocusIndicatorStyle: SegmentedOption {}
extension WordTypeface: SegmentedOption {}

private struct SegmentedControl<Option: SegmentedOption>: View {
    @Binding var selection: Option
    let options: [Option]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options) { option in
                let isSelected = option == selection
                Button {
                    selection = option
                } label: {
                    Text(option.label)
                        .font(JRFont.sans(13, weight: isSelected ? .semibold : .medium))
                        .tracking(-0.1)
                        .foregroundStyle(isSelected ? JRColor.paper : JRColor.inkMid)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(isSelected ? JRColor.ink : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
    }
}

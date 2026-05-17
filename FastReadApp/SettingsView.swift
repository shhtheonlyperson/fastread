import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: ReadingStore
    @Environment(\.openURL) private var openURL
    @State private var paceDraft: Double?
    @State private var showAddDictionaryEntry = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                masthead

                VStack(spacing: 22) {
                    paceGroup
                    SettingsGroup(label: "Focus indicator") {
                        SegmentedControl(selection: $store.focusIndicator, options: FocusIndicatorStyle.allCases)
                    }
                    customWordsGroup
                    aboutGroup
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 112)
        }
        .background(JRColor.paper)
        .sheet(isPresented: $showAddDictionaryEntry) {
            AddDictionaryEntrySheet { entry in
                store.addToUserDictionary(entry)
            }
        }
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
                        get: { paceDraft ?? store.wpm },
                        set: { value in
                            let next = snappedWPM(value)
                            paceDraft = next
                            store.previewWPM(next)
                        }
                    ),
                    in: RSVPEngine.minimumUserWPM...RSVPEngine.maximumWPM,
                    onEditingChanged: { isEditing in
                        if !isEditing {
                            store.setWPM(paceDraft ?? store.wpm)
                            paceDraft = nil
                        }
                    }
                )
                .tint(JRColor.terracotta)

                HStack {
                    Text("Slow · 300")
                    Spacer()
                    Text("Fast · 900")
                    Spacer()
                    Text("Sprint · 1500")
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

    private var customWordsGroup: some View {
        SettingsGroup(label: "Custom words") {
            SettingsRow {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Keep names together")
                    Text("Add proper nouns and terms so they aren't split across chunks. Especially helpful for Chinese names.")
                        .font(JRFont.sans(12))
                        .foregroundStyle(JRColor.inkQuiet)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            ForEach(Array(store.userDictionary.enumerated()), id: \.element) { _, entry in
                SettingsRow {
                    Text(entry)
                        .font(JRFont.serif(16))
                        .foregroundStyle(JRColor.ink)
                        .accessibilityIdentifier("dict-entry-\(entry)")
                    Spacer()
                    Button {
                        store.removeFromUserDictionary(entry)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(JRColor.terracotta.opacity(0.85))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove \(entry)")
                    .accessibilityIdentifier("dict-remove-\(entry)")
                }
            }

            SettingsRow(isLast: true) {
                Button {
                    showAddDictionaryEntry = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(JRColor.terracotta)
                        Text(store.userDictionary.isEmpty ? "Add your first word" : "Add word")
                            .font(JRFont.serif(16, weight: .semibold))
                            .foregroundStyle(JRColor.ink)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("dict-add-button")
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
                    if let url = URL(string: "mailto:shh@theonlyperson.com?subject=JustRead%20feedback") {
                        openURL(url)
                    }
                } label: {
                    Chevron()
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func snappedWPM(_ value: Double) -> Double {
        let clamped = RSVPEngine.clamp(value, min: RSVPEngine.minimumUserWPM, max: RSVPEngine.maximumWPM)
        return (Double(((clamped - RSVPEngine.minimumUserWPM) / RSVPEngine.wpmStep).rounded()) * RSVPEngine.wpmStep) + RSVPEngine.minimumUserWPM
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.2.3"
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

private struct AddDictionaryEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: String = ""
    let onSubmit: (String) -> Void

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Add a word")
                        .font(JRFont.serif(28, weight: .medium))
                        .foregroundStyle(JRColor.ink)
                        .padding(.top, 8)

                    Text("Names, brands, or compound terms that the reader is splitting incorrectly. Examples: 黃士旗, 蔡英文, 星巴克.")
                        .font(JRFont.sans(14))
                        .foregroundStyle(JRColor.inkQuiet)
                        .fixedSize(horizontal: false, vertical: true)

                    TextField("Enter a name or term", text: $draft)
                        .font(JRFont.serif(20))
                        .foregroundStyle(JRColor.ink)
                        .padding(14)
                        .background(JRColor.paperStrong)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(JRColor.rule, lineWidth: 0.5)
                        )
                        .submitLabel(.done)
                        .onSubmit(commit)
                        .accessibilityIdentifier("dict-add-text-field")
                        #if canImport(UIKit)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        #endif
                }
                .padding(.horizontal, 24)
            }
            .background(JRColor.paper)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .tint(JRColor.inkMid)
                        .accessibilityIdentifier("dict-add-cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add", action: commit)
                        .tint(JRColor.terracotta)
                        .disabled(trimmed.isEmpty)
                        .accessibilityIdentifier("dict-add-confirm")
                }
            }
        }
    }

    private var trimmed: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func commit() {
        let value = trimmed
        guard !value.isEmpty else { return }
        onSubmit(value)
        dismiss()
    }
}

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

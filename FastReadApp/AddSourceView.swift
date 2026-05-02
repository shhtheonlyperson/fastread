import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct AddSourceView: View {
    @EnvironmentObject private var store: ReadingStore
    let onLoaded: () -> Void

    @State private var url = ""
    @State private var draftText = ""
    @State private var status = ""
    @State private var isLoading = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                masthead

                VStack(alignment: .leading, spacing: 28) {
                    sourceTargets
                    webForm
                    pasteBox
                    startButton
                    recentSources
                }
                .padding(.horizontal, 24)
            }
            .padding(.bottom, 112)
        }
        .background(JRColor.paper)
    }

    private var masthead: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "New reading")
            Text("Add something\nto read.")
                .font(JRFont.serif(36, weight: .medium))
                .tracking(-0.9)
                .lineSpacing(-1)
                .foregroundStyle(JRColor.ink)
        }
        .padding(.top, 60)
        .padding(.horizontal, 24)
        .padding(.bottom, 18)
    }

    private var sourceTargets: some View {
        HStack(spacing: 8) {
            quickSourceButton(
                title: "Paste",
                subtitle: "Clipboard",
                icon: "doc.on.clipboard"
            ) {
#if canImport(UIKit)
                draftText = UIPasteboard.general.string ?? draftText
                status = draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Clipboard is empty." : "Clipboard text ready."
#else
                status = "Clipboard is unavailable."
#endif
            }

            quickSourceButton(
                title: "URL",
                subtitle: "Fetch web",
                icon: "link"
            ) {
                status = "Paste a URL below."
            }
        }
    }

    private func quickSourceButton(title: String, subtitle: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(JRColor.terracotta)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(JRFont.serif(19, weight: .semibold))
                        .tracking(-0.2)
                        .foregroundStyle(JRColor.ink)
                    Text(subtitle)
                        .font(JRFont.mono(10, weight: .medium))
                        .tracking(0.6)
                        .foregroundStyle(JRColor.inkQuiet)
                        .textCase(.uppercase)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(JRColor.paperStrong)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(JRColor.rule, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    private var webForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "From the web")
            HStack(spacing: 8) {
                TextField("https://", text: $url)
                    .urlInputBehavior()
                    .font(JRFont.mono(13))
                    .foregroundStyle(JRColor.ink)
                    .padding(.horizontal, 14)
                    .frame(height: 44)
                    .background(JRColor.paperStrong)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(JRColor.ruleStrong, lineWidth: 0.5)
                    )

                Button {
                    Task { await fetchURL() }
                } label: {
                    Text(isLoading ? "..." : "Fetch")
                        .font(JRFont.sans(14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 78, height: 44)
                        .background(JRColor.terracotta)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isLoading)
                .opacity(isLoading ? 0.65 : 1)
            }

            if !status.isEmpty {
                Text(status.uppercased())
                    .font(JRFont.mono(11))
                    .tracking(0.66)
                    .foregroundStyle(status.hasPrefix("Loaded") || status.hasPrefix("Clipboard") ? JRColor.terracotta : JRColor.inkQuiet)
                    .padding(.top, 2)
            }
        }
    }

    private var pasteBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Or paste text")
            TextEditor(text: $draftText)
                .font(JRFont.serif(15, weight: .regular))
                .foregroundStyle(JRColor.ink)
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(minHeight: 180)
                .background(JRColor.paperStrong)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(JRColor.ruleStrong, lineWidth: 0.5)
                )
                .overlay(alignment: .topLeading) {
                    if draftText.isEmpty {
                        Text("Paste an article, memo, or transcript here...")
                            .font(JRFont.serif(15))
                            .foregroundStyle(JRColor.inkQuiet.opacity(0.62))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 18)
                            .allowsHitTesting(false)
                    }
                }
        }
    }

    @ViewBuilder
    private var startButton: some View {
        if !draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Button {
                store.addDraftArticle(text: draftText)
                onLoaded()
            } label: {
                Text("Open in reader →")
                    .font(JRFont.sans(15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(JRColor.ink)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.top, -8)
        }
    }

    private var recentSources: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(text: "Recent sources")
                .padding(.bottom, 12)

            ForEach(Array(recent.enumerated()), id: \.offset) { index, item in
                HStack {
                    Text(item.label)
                        .font(JRFont.mono(13))
                        .foregroundStyle(JRColor.ink)
                    Spacer()
                    Text(item.date)
                        .font(JRFont.sans(12))
                        .foregroundStyle(JRColor.inkQuiet)
                }
                .padding(.vertical, 12)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(JRColor.rule)
                        .frame(height: index == 0 ? 0.5 : 0.5)
                }
            }
        }
    }

    private var recent: [(label: String, date: String)] {
        [
            ("stratechery.com", "2h ago"),
            ("theatlantic.com", "yesterday"),
            ("reuters.com", "3 days ago"),
        ]
    }

    private func fetchURL() async {
        guard !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            status = "Enter a URL first."
            return
        }

        isLoading = true
        status = ""

        do {
            let result = try await ArticleLoader.fetch(urlString: url)
            store.addFetchedArticle(title: result.title, source: result.source, text: result.text)
            status = "Loaded · \(result.wordCount) words"
            onLoaded()
        } catch {
            status = error.localizedDescription
        }

        isLoading = false
    }
}

private extension View {
    @ViewBuilder
    func urlInputBehavior() -> some View {
#if os(iOS)
        self
            .textInputAutocapitalization(.never)
            .keyboardType(.URL)
            .autocorrectionDisabled()
#else
        self
#endif
    }
}

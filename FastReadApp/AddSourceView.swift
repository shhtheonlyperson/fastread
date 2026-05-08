import SwiftUI
#if canImport(UIKit)
import UniformTypeIdentifiers
import UIKit
#endif

struct AddSourceView: View {
    @EnvironmentObject private var store: ReadingStore
    let onLoaded: () -> Void

    @State private var status = ""
    @State private var isLoading = false
    @State private var showEpubPicker = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                masthead

                VStack(alignment: .leading, spacing: 28) {
                    clipboardHero
                    epubPicker
                    recentSources
                }
                .padding(.horizontal, 24)
            }
            .padding(.bottom, 112)
        }
        .background(JRColor.paper)
        .fileImporter(
            isPresented: $showEpubPicker,
            allowedContentTypes: epubContentTypes,
            allowsMultipleSelection: false
        ) { result in
            handleEpubPick(result)
        }
    }

    private var epubContentTypes: [UTType] {
        var types: [UTType] = []
        if let epub = UTType("org.idpf.epub-container") {
            types.append(epub)
        }
        if #available(iOS 14.0, *) {
            types.append(UTType.epub)
        }
        return types
    }

    private var epubPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "EPUB book")
            Button {
                showEpubPicker = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "book.closed")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(JRColor.terracotta)
                    Text("Pick EPUB")
                        .font(JRFont.serif(18, weight: .semibold))
                        .foregroundStyle(JRColor.ink)
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(JRColor.inkQuiet)
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(JRColor.paperStrong)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isLoading)
            .opacity(isLoading ? 0.55 : 1)
        }
    }

    @MainActor
    private func handleEpubPick(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            status = error.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            let needsScope = url.startAccessingSecurityScopedResource()
            defer { if needsScope { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                let filename = url.lastPathComponent
                if let article = try store.addEpubArticle(data: data, filename: filename) {
                    let words = store.wordCount(for: article)
                    status = "Loaded · \(words) words"
                    onLoaded()
                } else {
                    status = "Could not read that EPUB."
                }
            } catch {
                status = "Could not read that EPUB."
            }
        }
    }

    private var masthead: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "New reading")
            Text("Capture\nyour next read.")
                .font(JRFont.serif(36, weight: .medium))
                .tracking(-0.9)
                .lineSpacing(-1)
                .foregroundStyle(JRColor.ink)
        }
        .padding(.top, 60)
        .padding(.horizontal, 24)
        .padding(.bottom, 18)
    }

    private var clipboardHero: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Clipboard")

            ClipboardPasteButton(isLoading: isLoading) { value in
                Task { await openClipboardValue(value) }
            }

            if !status.isEmpty {
                Text(status.uppercased())
                    .font(JRFont.mono(11))
                    .tracking(0.66)
                    .foregroundStyle(statusTone)
                    .padding(.top, 2)
            }
        }
    }

    private var statusTone: Color {
        status.hasPrefix("Loaded") || status.hasPrefix("Clipboard")
            ? JRColor.terracotta
            : JRColor.inkQuiet
    }

    private var recentSources: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(text: "Recent web sources")
                .padding(.bottom, 12)

            if store.recentSources.isEmpty {
                Text("Fetched links appear here.")
                    .font(JRFont.sans(13))
                    .lineSpacing(3)
                    .foregroundStyle(JRColor.inkQuiet)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(JRColor.rule)
                            .frame(height: 0.5)
                    }
            } else {
                ForEach(Array(store.recentSources.enumerated()), id: \.element.id) { index, item in
                    Button {
                        guard let itemURL = item.url else { return }
                        Task { await fetchURL(itemURL) }
                    } label: {
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
                    .buttonStyle(.plain)
                    .disabled(item.url == nil || isLoading)
                    .opacity(isLoading ? 0.55 : 1)
                }
            }
        }
    }

    @MainActor
    private func openClipboardValue(_ value: String) async {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            status = "Clipboard is empty."
            return
        }

        if SourceInputClassifier.isLikelySingleURL(trimmed) {
            await fetchURL(trimmed)
            return
        }

        store.addDraftArticle(text: trimmed)
        status = "Clipboard text loaded."
        onLoaded()
    }

    @MainActor
    private func fetchURL(_ urlString: String) async {
        guard !urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            status = "Clipboard URL is empty."
            return
        }

        isLoading = true
        status = "Fetching URL."
        defer { isLoading = false }

        do {
            let result = try await ArticleLoader.fetch(urlString: urlString)
            guard result.wordCount >= 20 else {
                status = "Could not find enough readable text on that page."
                return
            }
            store.addFetchedArticle(title: result.title, source: result.source, text: result.text, url: result.url)
            status = "Loaded · \(result.wordCount) words"
            onLoaded()
        } catch {
            status = error.localizedDescription
        }
    }
}

private struct ClipboardPasteButton: View {
    let isLoading: Bool
    let action: (String) -> Void

    var body: some View {
        ZStack {
            card
                .accessibilityHidden(true)

            SystemPasteControl(isEnabled: !isLoading, action: action)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 92)
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .accessibilityLabel(isLoading ? "Fetching clipboard content" : "Paste from clipboard")
        }
        .disabled(isLoading)
        .opacity(isLoading ? 0.72 : 1)
    }

    private var card: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(JRColor.terracotta.opacity(0.11))
                Image(systemName: isLoading ? "arrow.triangle.2.circlepath" : "doc.on.clipboard")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(JRColor.terracotta)
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 4) {
                Text(isLoading ? "Fetching" : "Paste from clipboard")
                    .font(JRFont.serif(22, weight: .semibold))
                    .tracking(-0.3)
                    .foregroundStyle(JRColor.ink)
                Text(isLoading ? "Preparing readable text" : "URL or text")
                    .font(JRFont.mono(11, weight: .medium))
                    .tracking(0.66)
                    .foregroundStyle(JRColor.inkQuiet)
                    .textCase(.uppercase)
            }

            Spacer(minLength: 8)

            Image(systemName: "arrow.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(JRColor.inkQuiet)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
        .background(JRColor.paperStrong)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .borderBeam(
            border: JRColor.terracotta,
            beam: [JRColor.terracotta, Color(hex: 0xDFA15D)],
            beamBlur: 12,
            cornerRadius: 6,
            isEnabled: !isLoading
        )
        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

#if canImport(UIKit)
private struct SystemPasteControl: UIViewRepresentable {
    let isEnabled: Bool
    let action: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeUIView(context: Context) -> UIPasteControl {
        let configuration = UIPasteControl.Configuration()
        configuration.displayMode = .labelOnly
        configuration.baseBackgroundColor = .clear
        configuration.baseForegroundColor = .clear
        configuration.cornerRadius = 6

        let control = UIPasteControl(configuration: configuration)
        control.target = context.coordinator.target
        control.isEnabled = isEnabled
        control.alpha = 0.011
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        control.setContentHuggingPriority(.defaultLow, for: .vertical)
        return control
    }

    func updateUIView(_ control: UIPasteControl, context: Context) {
        context.coordinator.target.action = action
        control.target = context.coordinator.target
        control.isEnabled = isEnabled
    }

    @MainActor
    final class Coordinator {
        let target: PasteTarget

        init(action: @escaping (String) -> Void) {
            target = PasteTarget(action: action)
        }
    }

    @MainActor
    final class PasteTarget: UIResponder {
        var action: (String) -> Void

        init(action: @escaping (String) -> Void) {
            self.action = action
            super.init()
            pasteConfiguration = UIPasteConfiguration(acceptableTypeIdentifiers: Self.acceptedTypeIdentifiers)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        func canPasteItemProviders(_ itemProviders: [NSItemProvider]) -> Bool {
            itemProviders.contains { provider in
                Self.acceptedTypeIdentifiers.contains { provider.hasItemConformingToTypeIdentifier($0) }
            }
        }

        override func paste(itemProviders: [NSItemProvider]) {
            guard let (provider, typeIdentifier) = firstAcceptedProvider(in: itemProviders) else {
                action("")
                return
            }

            provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, _ in
                let value: String
                if let string = item as? String {
                    value = string
                } else if let url = item as? URL {
                    if typeIdentifier == UTType.url.identifier {
                        value = url.absoluteString
                    } else {
                        value = (try? String(contentsOf: url, encoding: .utf8)) ?? url.absoluteString
                    }
                } else if let data = item as? Data {
                    value = String(data: data, encoding: .utf8) ?? ""
                } else if let nsString = item as? NSString {
                    value = nsString as String
                } else {
                    value = ""
                }

                DispatchQueue.main.async {
                    self.action(value)
                }
            }
        }

        private static let acceptedTypeIdentifiers = [
            UTType.plainText.identifier,
            UTType.text.identifier,
            UTType.url.identifier
        ]

        private func firstAcceptedProvider(in providers: [NSItemProvider]) -> (NSItemProvider, String)? {
            for provider in providers {
                for typeIdentifier in Self.acceptedTypeIdentifiers where provider.hasItemConformingToTypeIdentifier(typeIdentifier) {
                    return (provider, typeIdentifier)
                }
            }
            return nil
        }
    }
}
#else
private struct SystemPasteControl: View {
    let isEnabled: Bool
    let action: (String) -> Void

    var body: some View {
        Button {
            action("")
        } label: {
            Color.clear
        }
        .disabled(!isEnabled)
    }
}
#endif

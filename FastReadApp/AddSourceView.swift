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
    @State private var localEpubs: [LocalEpubFile] = []

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                masthead

                VStack(alignment: .leading, spacing: 28) {
                    clipboardHero
                    EpubSourcePickerView(
                        localEpubs: localEpubs,
                        isLoading: isLoading,
                        onPick: {
                            refreshLocalEpubs()
                            showEpubPicker = true
                        },
                        onImport: importLocalEpub
                    )
                    RecentSourcesView(
                        sources: store.recentSources,
                        isLoading: isLoading,
                        onSelect: { url in
                            Task { await fetchURL(url) }
                        }
                    )
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
        .onAppear(perform: refreshLocalEpubs)
    }

    private var epubContentTypes: [UTType] {
        var types: [UTType] = []
        if let epub = UTType("org.idpf.epub-container") {
            types.append(epub)
        }
        if let epubExtension = UTType(filenameExtension: "epub") {
            types.append(epubExtension)
        }
        if #available(iOS 14.0, *) {
            types.append(UTType.epub)
        }
        types.append(.data)
        return types
    }

    @MainActor
    private func handleEpubPick(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            status = error.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            guard url.pathExtension.caseInsensitiveCompare("epub") == .orderedSame else {
                status = "Choose an EPUB file."
                return
            }
            let needsScope = url.startAccessingSecurityScopedResource()
            defer { if needsScope { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                let filename = url.lastPathComponent
                if let article = try store.addEpubArticle(data: data, filename: filename) {
                    let words = store.wordCount(for: article)
                    status = "Loaded · \(words) words"
                    refreshLocalEpubs()
                    onLoaded()
                } else {
                    status = "Could not read that EPUB."
                }
            } catch {
                status = "Could not read that EPUB."
            }
        }
    }

    @MainActor
    private func importLocalEpub(_ file: LocalEpubFile) {
        isLoading = true
        defer { isLoading = false }

        do {
            let data = try Data(contentsOf: file.url)
            if let article = try store.addEpubArticle(data: data, filename: file.url.lastPathComponent) {
                let words = store.wordCount(for: article)
                status = "Loaded · \(words) words"
                refreshLocalEpubs()
                onLoaded()
            } else {
                status = "Could not read that EPUB."
            }
        } catch {
            status = "Could not read that EPUB."
        }
    }

    private func refreshLocalEpubs() {
        localEpubs = LocalEpubFile.discoverInAppDocuments()
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

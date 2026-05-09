import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

@main
struct FastReadApp: App {
    @StateObject private var store: ReadingStore

    init() {
        UITestSupport.applyLaunchOverrides()
        let store = ReadingStore()
        UITestSupport.applyPostStoreOverrides(store: store)
        _store = StateObject(wrappedValue: store)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
    }
}

private enum UITestSupport {
    static func applyLaunchOverrides() {
#if DEBUG
        let args = CommandLine.arguments

        if args.contains("-FASTREAD_RESET_LIBRARY") {
            if let bundleID = Bundle.main.bundleIdentifier {
                UserDefaults.standard.removePersistentDomain(forName: bundleID)
                UserDefaults.standard.synchronize()
            }
        }

        if let idx = args.firstIndex(of: "-FASTREAD_SEED_EPUB"),
           idx + 1 < args.count {
            seedEpub(from: URL(fileURLWithPath: args[idx + 1]))
        }
#endif
    }

    @MainActor
    static func applyPostStoreOverrides(store: ReadingStore) {
#if DEBUG
        let args = CommandLine.arguments
        if let idx = args.firstIndex(of: "-FASTREAD_SEED_DRAFT_TEXT"),
           idx + 1 < args.count {
            let text = args[idx + 1]
            let title = (args.firstIndex(of: "-FASTREAD_SEED_DRAFT_TITLE")
                .flatMap { i in i + 1 < args.count ? args[i + 1] : nil }) ?? "Test note"
            store.addDraftArticle(text: text, title: title, source: "Maestro")
        }
#endif
    }

#if DEBUG
    private static func seedEpub(from src: URL) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: src.path),
              let documents = try? fm.url(
                for: .documentDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
              ) else { return }
        let dst = documents.appendingPathComponent(src.lastPathComponent)
        if fm.fileExists(atPath: dst.path) {
            try? fm.removeItem(at: dst)
        }
        try? fm.copyItem(at: src, to: dst)
    }
#endif
}

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

@main
struct FastReadApp: App {
    @StateObject private var store: ReadingStore

    init() {
        UITestSupport.applyLaunchOverrides()
        _store = StateObject(wrappedValue: ReadingStore())
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

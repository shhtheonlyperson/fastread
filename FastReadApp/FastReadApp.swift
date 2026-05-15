import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

@main
struct FastReadApp: App {
#if canImport(UIKit)
    @UIApplicationDelegateAdaptor(FastReadOrientationDelegate.self) private var orientationDelegate
#endif
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

#if canImport(UIKit)
@MainActor
private final class FastReadOrientationDelegate: NSObject, UIApplicationDelegate {
    static var supportedOrientations: UIInterfaceOrientationMask = .portrait

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        Self.supportedOrientations
    }
}

@MainActor
enum OrientationSupport {
    static func allowReaderLandscape(_ isAllowed: Bool) {
        let mask: UIInterfaceOrientationMask = isAllowed
            ? [.portrait, .landscapeLeft, .landscapeRight]
            : .portrait
        FastReadOrientationDelegate.supportedOrientations = mask

        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask))
        }
    }
}

private extension UIWindowScene {
    var keyWindow: UIWindow? {
        windows.first { $0.isKeyWindow }
    }
}
#endif

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
        // -FASTREAD_SEED_USER_DICT entries are NUL-or-comma-separated
        // user-dictionary entries to apply at boot. Lets Maestro flows
        // verify dictionary-driven tokenization without driving the
        // Settings sheet, which is iOS-26-flaky for some sheet bindings.
        if let idx = args.firstIndex(of: "-FASTREAD_SEED_USER_DICT"),
           idx + 1 < args.count {
            for raw in args[idx + 1].split(separator: ",") {
                store.addToUserDictionary(String(raw))
            }
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

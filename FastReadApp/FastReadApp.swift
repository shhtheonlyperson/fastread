import SwiftUI

@main
struct FastReadApp: App {
    @StateObject private var store = ReadingStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
    }
}

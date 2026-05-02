import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: ReadingStore
    @State private var selectedTab: AppTab = .home
    @State private var showingFocusMode = false

    var body: some View {
        ZStack(alignment: .bottom) {
            JRColor.paper.ignoresSafeArea()

            Group {
                switch selectedTab {
                case .home:
                    LibraryView(
                        onResume: {
                            store.openArticle(SampleData.currentArticle.id, resume: true)
                            selectedTab = .reader
                        },
                        onOpenArticle: { article in
                            store.openArticle(article.id, resume: article.progress > 0)
                            selectedTab = .reader
                        }
                    )
                case .source:
                    AddSourceView {
                        selectedTab = .reader
                    }
                case .reader:
                    ReaderView(
                        onBack: { selectedTab = .home },
                        onFocus: { showingFocusMode = true }
                    )
                case .stats:
                    StatsView()
                case .settings:
                    SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            JustReadTabBar(selection: $selectedTab)
        }
        .preferredColorScheme(.light)
        .focusModeCover(isPresented: $showingFocusMode, store: store)
    }
}

private struct JustReadTabBar: View {
    @Binding var selection: AppTab

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                Button {
                    selection = tab
                } label: {
                    VStack(spacing: 3) {
                        TabGlyph(tab: tab, color: selection == tab ? JRColor.terracotta : JRColor.inkQuiet)
                        Text(tab.label.uppercased())
                            .font(JRFont.mono(10, weight: .medium))
                            .tracking(0.6)
                            .foregroundStyle(selection == tab ? JRColor.terracotta : JRColor.inkQuiet)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 28)
        .background(
            LinearGradient(
                colors: [JRColor.paper, JRColor.paper.opacity(0)],
                startPoint: .bottom,
                endPoint: .top
            )
            .ignoresSafeArea(edges: .bottom)
        )
    }
}

private extension View {
    @ViewBuilder
    func focusModeCover(isPresented: Binding<Bool>, store: ReadingStore) -> some View {
#if os(iOS)
        fullScreenCover(isPresented: isPresented) {
            FocusModeView(isPresented: isPresented)
                .environmentObject(store)
        }
#else
        sheet(isPresented: isPresented) {
            FocusModeView(isPresented: isPresented)
                .environmentObject(store)
        }
#endif
    }
}

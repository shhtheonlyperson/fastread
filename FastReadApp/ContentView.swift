import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: ReadingStore
    @State private var selectedTab: AppTab = .home
    @State private var showingFocusMode = false
    @State private var showingSplash = true

    var body: some View {
        ZStack(alignment: .bottom) {
            JRColor.paper.ignoresSafeArea()

            Group {
                switch selectedTab {
                case .home:
                    LibraryView(
                        onResume: {
                            if let article = store.currentArticle {
                                store.openArticle(article.id, resume: true)
                                selectedTab = .reader
                            } else {
                                selectedTab = .source
                            }
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
                        onFocus: {
                            store.play()
                            showingFocusMode = true
                        }
                    )
                case .stats:
                    StatsView()
                case .settings:
                    SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if selectedTab != .reader && !showingSplash {
                JustReadTabBar(selection: $selectedTab)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if showingSplash {
                SplashView { showingSplash = false }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .preferredColorScheme(.light)
        .animation(.easeOut(duration: 0.18), value: selectedTab)
        .animation(.easeInOut(duration: 0.3), value: showingSplash)
        .focusModeCover(isPresented: $showingFocusMode, store: store)
        .onAppear {
            updateOrientation(for: selectedTab)
        }
        .onChange(of: selectedTab) { _, tab in
            updateOrientation(for: tab)
        }
        .onDisappear {
            updateOrientation(for: .home)
        }
    }

    private func updateOrientation(for tab: AppTab) {
#if os(iOS)
        OrientationSupport.allowReaderLandscape(tab == .reader)
#endif
    }
}

private struct JustReadTabBar: View {
    @Binding var selection: AppTab

    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [JRColor.paper.opacity(0), JRColor.paper],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 18)
            .allowsHitTesting(false)

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
            .background(JRColor.paper)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(JRColor.rule.opacity(0.75))
                    .frame(height: 0.5)
            }
        }
        .background(JRColor.paper.ignoresSafeArea(edges: .bottom))
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

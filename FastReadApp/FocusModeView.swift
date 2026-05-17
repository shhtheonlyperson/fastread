import SwiftUI

struct FocusModeView: View {
    @EnvironmentObject private var store: ReadingStore
    @Binding var isPresented: Bool

    var body: some View {
        ZStack {
            JRColor.focusDark.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("FOCUS · \(Int(store.wpm.rounded())) WPM")
                            .font(JRFont.mono(10, weight: .medium))
                            .tracking(1.4)
                            .foregroundStyle(JRColor.paper.opacity(0.5))
                        Text(store.currentArticle?.title ?? "No article")
                            .font(JRFont.serif(14))
                            .foregroundStyle(JRColor.paper.opacity(0.85))
                            .lineLimit(1)
                    }

                    Spacer()

                    Button {
                        closeFocusMode()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(JRColor.paper)
                            .frame(width: 40, height: 40)
                            .background(JRColor.paper.opacity(0.10))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
                .padding(.top, 56)

                RSVPStage(
                    token: store.currentToken,
                    focusStyle: store.focusIndicator,
                    isBig: true,
                    isDark: true
                )
                .frame(maxHeight: .infinity)
                .padding(.horizontal, 12)

                focusTransport
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            store.pause()
        }
        .onDisappear {
            store.pause()
        }
        .focusStatusBarHidden()
    }

    private func closeFocusMode() {
        store.pause()
        isPresented = false
    }

    private var focusTransport: some View {
        VStack(spacing: 18) {
            VStack(spacing: 6) {
                JRProgressBar(progress: store.readerProgress, track: JRColor.paper.opacity(0.15))
                HStack {
                    Text("\(store.currentIndex + 1) / \(max(store.currentTokens.count, 1))")
                    Spacer()
                    Text("\(Int((store.readerProgress * 100).rounded()))%")
                }
                .font(JRFont.mono(10))
                .tracking(0.6)
                .foregroundStyle(JRColor.paper.opacity(0.5))
            }

            HStack(spacing: 14) {
                DarkTransportButton {
                    store.move(by: -10)
                } content: {
                    Image(systemName: "backward.end.fill")
                }

                DarkTransportButton(size: 40) {
                    store.move(by: -1)
                } content: {
                    Image(systemName: "backward.fill")
                }

                Button {
                    store.togglePlay()
                } label: {
                    Image(systemName: store.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(JRColor.onPrimary)
                        .frame(width: 72, height: 72)
                        .background(JRColor.terracotta)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                DarkTransportButton(size: 40) {
                    store.move(by: 1)
                } content: {
                    Image(systemName: "forward.fill")
                }

                DarkTransportButton {
                    store.move(by: 10)
                } content: {
                    Image(systemName: "forward.end.fill")
                }
            }
        }
    }
}

private extension View {
    @ViewBuilder
    func focusStatusBarHidden() -> some View {
#if os(iOS)
        statusBarHidden(true)
#else
        self
#endif
    }
}

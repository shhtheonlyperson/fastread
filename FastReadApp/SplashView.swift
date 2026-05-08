import SwiftUI

struct SplashView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let onDismiss: () -> Void

    @State private var phase: Phase = .enter
    @State private var pulse = false

    private enum Phase {
        case enter, hold, exit
    }

    var body: some View {
        ZStack {
            JRColor.paper
                .ignoresSafeArea()

            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .stroke(JRColor.rule, lineWidth: 0.5)
                .padding(32)
                .allowsHitTesting(false)

            VStack {
                Text("Vol. 47 · The careful reader")
                    .font(JRFont.mono(10))
                    .tracking(2.4)
                    .textCase(.uppercase)
                    .foregroundStyle(JRColor.inkQuiet)
                    .opacity(phase == .hold ? 1 : 0)
                    .offset(y: phase == .enter ? -4 : 0)
                    .animation(.easeOut(duration: 0.5).delay(0.2), value: phase)
                    .padding(.top, 88)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            VStack(spacing: 22) {
                BrandMark(size: 104)
                Text("JustRead")
                    .font(JRFont.serif(42, weight: .medium))
                    .tracking(-1.2)
                    .foregroundStyle(JRColor.ink)
                Text("Read fast. Enjoy it.")
                    .font(JRFont.serif(15))
                    .italic()
                    .tracking(-0.1)
                    .foregroundStyle(JRColor.inkMid)
            }
            .scaleEffect(phase == .enter ? 0.92 : 1)
            .opacity(phase == .enter ? 0 : 1)
            .animation(.easeOut(duration: 0.45), value: phase)

            VStack {
                Spacer(minLength: 0)
                Circle()
                    .fill(JRColor.terracotta)
                    .frame(width: 6, height: 6)
                    .scaleEffect(pulse ? 1.4 : 1)
                    .opacity(phase == .exit ? 0 : (pulse ? 1 : 0.35))
                    .padding(.bottom, 96)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .allowsHitTesting(false)

            VStack {
                Spacer(minLength: 0)
                Text("An app for the careful reader")
                    .font(JRFont.mono(10))
                    .tracking(1.8)
                    .textCase(.uppercase)
                    .foregroundStyle(JRColor.inkQuiet)
                    .opacity(phase == .hold ? 0.7 : 0)
                    .animation(.easeOut(duration: 0.5).delay(0.3), value: phase)
                    .padding(.bottom, 56)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .opacity(phase == .exit ? 0 : 1)
        .animation(.easeInOut(duration: 0.38), value: phase == .exit)
        .contentShape(Rectangle())
        .onTapGesture(perform: dismiss)
        .task(id: "splash-lifecycle") {
            try? await Task.sleep(nanoseconds: 80_000_000)
            phase = .hold
            if !reduceMotion {
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            dismiss()
        }
    }

    private func dismiss() {
        guard phase != .exit else { return }
        phase = .exit
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            onDismiss()
        }
    }
}

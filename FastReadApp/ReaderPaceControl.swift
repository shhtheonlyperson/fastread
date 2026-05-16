import SwiftUI

struct ReaderPaceControl: View {
    @EnvironmentObject private var store: ReadingStore
    @State private var paceDraft: Double?
    var compact = false

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                SectionLabel(text: "Pace")
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(Int(store.wpm.rounded()))")
                        .font(JRFont.serif(compact ? 18 : 22, weight: .semibold))
                        .foregroundStyle(JRColor.ink)
                    Text("wpm")
                        .font(JRFont.mono(11))
                        .tracking(1.54)
                        .foregroundStyle(JRColor.inkQuiet)
                }
            }

            Slider(
                value: Binding(
                    get: { paceDraft ?? store.wpm },
                    set: { value in
                        let next = snappedWPM(value)
                        paceDraft = next
                        store.previewWPM(next)
                    }
                ),
                in: 300...1_000,
                onEditingChanged: { isEditing in
                    if !isEditing {
                        store.setWPM(paceDraft ?? store.wpm)
                        paceDraft = nil
                    }
                }
            )
            .tint(JRColor.terracotta)

            HStack {
                Text("300")
                Spacer()
                Text("650")
                Spacer()
                Text("1000")
            }
            .font(JRFont.mono(10))
            .tracking(0.6)
            .foregroundStyle(JRColor.inkQuiet)
        }
        .padding(.horizontal, compact ? 8 : 24)
    }

    private func snappedWPM(_ value: Double) -> Double {
        let clamped = RSVPEngine.clamp(value, min: 300, max: 1_000)
        return (Double(((clamped - 300) / 25).rounded()) * 25) + 300
    }
}

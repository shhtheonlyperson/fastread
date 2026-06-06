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
                in: store.currentMinimumWPM...RSVPEngine.maximumWPM,
                onEditingChanged: { isEditing in
                    if !isEditing {
                        store.setWPM(paceDraft ?? store.wpm)
                        paceDraft = nil
                    }
                }
            )
            .tint(JRColor.terracotta)

            HStack {
                Text("\(Int(store.currentMinimumWPM))")
                Spacer()
                Text("900")
                Spacer()
                Text("1500")
            }
            .font(JRFont.mono(10))
            .tracking(0.6)
            .foregroundStyle(JRColor.inkQuiet)
        }
        .padding(.horizontal, compact ? 8 : 24)
    }

    private func snappedWPM(_ value: Double) -> Double {
        store.snapWPM(value)
    }
}

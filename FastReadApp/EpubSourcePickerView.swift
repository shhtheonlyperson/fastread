import SwiftUI

struct EpubSourcePickerView: View {
    let localEpubs: [LocalEpubFile]
    let isLoading: Bool
    let onPick: () -> Void
    let onImport: (LocalEpubFile) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            pickerButton
            if !localEpubs.isEmpty {
                localPicker
            }
        }
    }

    private var pickerButton: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "EPUB book")
            Button(action: onPick) {
                HStack(spacing: 12) {
                    Image(systemName: "book.closed")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(JRColor.terracotta)
                    Text("Pick EPUB")
                        .font(JRFont.serif(18, weight: .semibold))
                        .foregroundStyle(JRColor.ink)
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(JRColor.inkQuiet)
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(JRColor.paperStrong)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isLoading)
            .opacity(isLoading ? 0.55 : 1)
        }
    }

    private var localPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Files folder")
            ForEach(localEpubs) { file in
                Button {
                    onImport(file)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "doc.richtext")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(JRColor.terracotta)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(file.displayName)
                                .font(JRFont.serif(17, weight: .semibold))
                                .foregroundStyle(JRColor.ink)
                                .lineLimit(2)
                            Text(file.locationName)
                                .font(JRFont.mono(10))
                                .tracking(0.6)
                                .foregroundStyle(JRColor.inkQuiet)
                        }
                        Spacer()
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(JRColor.inkQuiet)
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(JRColor.paperStrong)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isLoading)
                .opacity(isLoading ? 0.55 : 1)
            }
        }
    }
}

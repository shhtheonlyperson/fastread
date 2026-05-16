import SwiftUI

struct RecentSourcesView: View {
    let sources: [RecentSource]
    let isLoading: Bool
    let onSelect: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(text: "Recent web sources")
                .padding(.bottom, 12)

            if sources.isEmpty {
                emptyState
            } else {
                ForEach(Array(sources.enumerated()), id: \.element.id) { index, item in
                    recentSourceButton(item: item, index: index)
                }
            }
        }
    }

    private var emptyState: some View {
        Text("Fetched links appear here.")
            .font(JRFont.sans(13))
            .lineSpacing(3)
            .foregroundStyle(JRColor.inkQuiet)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(JRColor.rule)
                    .frame(height: 0.5)
            }
    }

    private func recentSourceButton(item: RecentSource, index: Int) -> some View {
        Button {
            guard let itemURL = item.url else { return }
            onSelect(itemURL)
        } label: {
            HStack {
                Text(item.label)
                    .font(JRFont.mono(13))
                    .foregroundStyle(JRColor.ink)
                Spacer()
                Text(item.date)
                    .font(JRFont.sans(12))
                    .foregroundStyle(JRColor.inkQuiet)
            }
            .padding(.vertical, 12)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(JRColor.rule)
                    .frame(height: index == 0 ? 0.5 : 0.5)
            }
        }
        .buttonStyle(.plain)
        .disabled(item.url == nil || isLoading)
        .opacity(isLoading ? 0.55 : 1)
    }
}

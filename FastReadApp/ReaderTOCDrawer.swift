import SwiftUI

struct TocDrawerView: View {
    @Binding var isOpen: Bool
    let sections: [Section]
    let boundaries: [Document.SectionBoundary]
    let frontMatter: Document.FrontMatterDetection?
    let wordIndex: Int
    let onSelect: (Int) -> Void
    let onSkipFrontMatter: () -> Void

    private var totalTokens: Int {
        boundaries.last?.tokenEnd ?? 0
    }

    private var progressPct: Int {
        guard totalTokens > 0 else { return 0 }
        return Int((Double(wordIndex) / Double(totalTokens)) * 100.0)
    }

    private var skipCount: Int {
        frontMatter?.frontMatterSectionIds.count ?? 0
    }

    private var currentIndex: Int {
        for (i, b) in boundaries.enumerated() {
            if wordIndex >= b.tokenStart && wordIndex < b.tokenEnd {
                return i
            }
        }
        return max(boundaries.count - 1, 0)
    }

    private var canSkipFrontMatter: Bool {
        guard let fm = frontMatter, fm.hasSkippableFrontMatter else { return false }
        return wordIndex < fm.firstChapterTokenIndex
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom) {
                Text("Contents")
                    .font(JRFont.serif(22, weight: .bold))
                    .foregroundStyle(JRColor.ink)
                Spacer()
                Button("Close") { isOpen = false }
                    .font(JRFont.mono(11))
                    .tracking(1.4)
                    .foregroundStyle(JRColor.inkMid)
                    .textCase(.uppercase)
            }
            .padding(.top, 18)
            .padding(.horizontal, 22)
            .padding(.bottom, 14)
            .overlay(
                Rectangle()
                    .fill(JRColor.rule)
                    .frame(height: 1)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            )

            Text("\(progressPct)% · \(wordIndex.formatted()) of \(totalTokens.formatted()) words")
                .font(JRFont.mono(11))
                .tracking(1.4)
                .textCase(.uppercase)
                .foregroundStyle(JRColor.inkQuiet)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 22)
                .padding(.top, 12)
                .padding(.bottom, 4)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(sections.enumerated()), id: \.element.id) { i, section in
                        let b = i < boundaries.count ? boundaries[i] : Document.SectionBoundary(sectionId: section.id, tokenStart: 0, tokenEnd: 0)
                        let units = b.tokenEnd - b.tokenStart
                        let isFront = (frontMatter?.frontMatterSectionIds ?? []).contains(section.id)
                        let isCurrent = i == currentIndex
                        let isRead = !isCurrent && wordIndex >= b.tokenEnd && b.tokenEnd > 0
                        let display = labelForSection(
                            index: i,
                            isFront: isFront,
                            isCurrent: isCurrent,
                            isRead: isRead,
                            units: units,
                            boundary: b
                        )

                        Button(action: { onSelect(b.tokenStart) }) {
                            HStack(spacing: 10) {
                                Text(display.number)
                                    .font(JRFont.mono(11))
                                    .foregroundStyle(isCurrent ? JRColor.terracotta : JRColor.inkQuiet)
                                    .frame(width: 30, alignment: .leading)
                                Text(section.title.isEmpty ? "Untitled section" : section.title)
                                    .font(JRFont.serif(15, weight: isCurrent ? .semibold : .regular))
                                    .foregroundStyle(isCurrent ? JRColor.terracotta : (isFront ? JRColor.inkQuiet : JRColor.ink))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .lineLimit(2)
                                Text(display.pct)
                                    .font(JRFont.mono(10.5, weight: isCurrent ? .bold : .regular))
                                    .foregroundStyle(isCurrent ? JRColor.terracotta : JRColor.inkQuiet)
                            }
                            .padding(.horizontal, 22)
                            .padding(.vertical, 12)
                            .background(isCurrent ? JRColor.terracotta.opacity(0.08) : .clear)
                            .overlay(
                                Rectangle()
                                    .fill(JRColor.rule)
                                    .frame(height: 1)
                                    .frame(maxHeight: .infinity, alignment: .bottom)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 24)
            }

            if canSkipFrontMatter {
                Button(action: onSkipFrontMatter) {
                    Text("SKIP FRONT MATTER →")
                        .font(JRFont.mono(11, weight: .bold))
                        .tracking(2)
                        .textCase(.uppercase)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(JRColor.terracotta)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 28)
                .background(JRColor.paper)
                .overlay(
                    Rectangle()
                        .fill(JRColor.rule)
                        .frame(height: 1)
                        .frame(maxHeight: .infinity, alignment: .top)
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(JRColor.paper)
    }

    private func labelForSection(
        index: Int,
        isFront: Bool,
        isCurrent: Bool,
        isRead: Bool,
        units: Int,
        boundary: Document.SectionBoundary
    ) -> (number: String, pct: String) {
        let number: String
        if isFront {
            number = "—"
        } else {
            let chapterOrdinal = max(index - skipCount + 1, 1)
            number = String(format: "%02d", chapterOrdinal)
        }
        let pct: String
        if units == 0 {
            pct = "—"
        } else if isFront && wordIndex >= boundary.tokenEnd {
            pct = "✓"
        } else if isCurrent {
            let local = max(wordIndex - boundary.tokenStart, 0)
            let pctValue = Int((Double(local) / Double(max(units, 1))) * 100.0)
            pct = "\(pctValue)%"
        } else if isRead {
            pct = "100%"
        } else {
            pct = "—"
        }
        return (number, pct)
    }
}

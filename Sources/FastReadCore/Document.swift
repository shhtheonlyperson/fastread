import Foundation

public enum SectionKind: String, Codable, Equatable, Sendable {
    case body
    case chapter
    case page
}

public struct Section: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public var title: String
    public var kind: SectionKind
    public var text: String

    public init(id: String, title: String = "", kind: SectionKind = .body, text: String = "") {
        self.id = id
        self.title = title
        self.kind = kind
        self.text = text
    }
}

public struct Document: Codable, Equatable, Sendable {
    public var title: String
    public var author: String
    public var sourceUrl: String
    public var sourceKind: String
    public var sections: [Section]

    public init(
        title: String = "",
        author: String = "",
        sourceUrl: String = "",
        sourceKind: String = "text",
        sections: [Section] = []
    ) {
        self.title = title
        self.author = author
        self.sourceUrl = sourceUrl
        self.sourceKind = sourceKind
        self.sections = sections
    }

    public struct SectionBoundary: Equatable, Sendable {
        public let sectionId: String
        public let tokenStart: Int
        public let tokenEnd: Int

        public init(sectionId: String, tokenStart: Int, tokenEnd: Int) {
            self.sectionId = sectionId
            self.tokenStart = tokenStart
            self.tokenEnd = tokenEnd
        }
    }

    public static func flattenText(_ document: Document) -> String {
        document.sections.map { $0.text }.joined(separator: "\n\n")
    }

    public static func sectionBoundaries(
        _ document: Document,
        userDictionary: [String] = []
    ) -> [SectionBoundary] {
        var boundaries: [SectionBoundary] = []
        var cursor = 0
        boundaries.reserveCapacity(document.sections.count)
        for section in document.sections {
            let tokenCount = RSVPEngine.tokenize(section.text, userDictionary: userDictionary).count
            let tokenEnd = cursor + tokenCount
            boundaries.append(
                SectionBoundary(sectionId: section.id, tokenStart: cursor, tokenEnd: tokenEnd)
            )
            cursor = tokenEnd
        }
        return boundaries
    }

    public struct FrontMatterDetection: Equatable, Sendable {
        public let firstChapterSectionIndex: Int?
        public let firstChapterTokenIndex: Int
        public let frontMatterSectionIds: [String]
        public let totalTokens: Int

        public init(
            firstChapterSectionIndex: Int?,
            firstChapterTokenIndex: Int,
            frontMatterSectionIds: [String],
            totalTokens: Int
        ) {
            self.firstChapterSectionIndex = firstChapterSectionIndex
            self.firstChapterTokenIndex = firstChapterTokenIndex
            self.frontMatterSectionIds = frontMatterSectionIds
            self.totalTokens = totalTokens
        }

        public var hasSkippableFrontMatter: Bool {
            guard let idx = firstChapterSectionIndex else { return false }
            return idx > 0 && firstChapterTokenIndex > 0
        }
    }

    // Mirrors src/document.js detectFrontMatter. Keep the patterns and
    // thresholds in lockstep with the JS regex / constants — there is a
    // parity test in DocumentTests.
    private static let frontMatterTitlePatterns: [String] = [
        "封面", "扉頁", "扉页", "版權", "版权", "獻詞", "献词",
        "推薦序", "推薦語", "推薦文", "推薦$", "推荐序", "推荐语",
        "名人推薦", "各界推薦", "自序", "序言", "序$", "代序",
        "前言", "引言", "試讀本", "试读本", "目錄", "目录",
        "致謝", "致谢", "譯者序", "译者序", "作者簡介", "作者简介",
        "Foreword", "Preface", "Copyright", "Acknowledg", "Dedication",
        "Title\\s*Page", "Cover\\s*Page", "^Cover$", "Contents$",
        "Table\\s*of\\s*Contents", "Imprint", "Colophon",
        "Frontispiece", "Half\\s*Title", "About\\s*the\\s*Author",
        "Praise\\s*for", "Epigraph", "Note\\s*to\\s*the\\s*Reader",
    ]

    private static let frontMatterTitleRegex: NSRegularExpression = {
        let pattern = "^(" + frontMatterTitlePatterns.joined(separator: "|") + ")"
        return (try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])) ?? NSRegularExpression()
    }()

    private static let frontMatterHeadFraction: Double = 0.15
    private static let frontMatterShortUnits: Int = 500

    public static func detectFrontMatter(_ document: Document) -> FrontMatterDetection {
        detectFrontMatter(document, boundaries: sectionBoundaries(document))
    }

    public static func detectFrontMatter(_ document: Document, boundaries: [SectionBoundary]) -> FrontMatterDetection {
        let empty = FrontMatterDetection(
            firstChapterSectionIndex: nil,
            firstChapterTokenIndex: 0,
            frontMatterSectionIds: [],
            totalTokens: 0
        )
        guard !document.sections.isEmpty else { return empty }
        let totalTokens = boundaries.last?.tokenEnd ?? 0
        if totalTokens == 0 { return empty }

        let headLimit = Double(totalTokens) * frontMatterHeadFraction
        var firstChapterSectionIndex: Int? = nil

        for (i, section) in document.sections.enumerated() {
            let b = boundaries[i]
            let units = b.tokenEnd - b.tokenStart
            let inHead = Double(b.tokenStart) < headLimit
            let trimmed = section.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let titleHit = matchesFrontMatterTitle(trimmed)
            let looksShort = units < frontMatterShortUnits && inHead
            if titleHit || looksShort { continue }
            firstChapterSectionIndex = i
            break
        }

        guard let idx = firstChapterSectionIndex else {
            return FrontMatterDetection(
                firstChapterSectionIndex: nil,
                firstChapterTokenIndex: 0,
                frontMatterSectionIds: [],
                totalTokens: totalTokens
            )
        }
        if idx == 0 {
            return FrontMatterDetection(
                firstChapterSectionIndex: 0,
                firstChapterTokenIndex: 0,
                frontMatterSectionIds: [],
                totalTokens: totalTokens
            )
        }

        let frontIds = boundaries.prefix(idx).map { $0.sectionId }
        return FrontMatterDetection(
            firstChapterSectionIndex: idx,
            firstChapterTokenIndex: boundaries[idx].tokenStart,
            frontMatterSectionIds: Array(frontIds),
            totalTokens: totalTokens
        )
    }

    private static func matchesFrontMatterTitle(_ title: String) -> Bool {
        guard !title.isEmpty else { return false }
        let range = NSRange(title.startIndex..<title.endIndex, in: title)
        return frontMatterTitleRegex.firstMatch(in: title, options: [], range: range) != nil
    }
}

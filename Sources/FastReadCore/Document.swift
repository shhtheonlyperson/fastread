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

    public static func sectionBoundaries(_ document: Document) -> [SectionBoundary] {
        var boundaries: [SectionBoundary] = []
        var cursor = 0
        var runningText = ""
        for (i, section) in document.sections.enumerated() {
            let prefix = i == 0 ? "" : "\n\n"
            let candidate = runningText + prefix + section.text
            let tokensSoFar = RSVPEngine.tokenize(candidate).count
            boundaries.append(
                SectionBoundary(sectionId: section.id, tokenStart: cursor, tokenEnd: tokensSoFar)
            )
            cursor = tokensSoFar
            runningText = candidate
        }
        return boundaries
    }
}

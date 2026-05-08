import Foundation

public struct ReadingArticle: Identifiable, Codable, Equatable {
    public let id: String
    public var title: String
    public var source: String
    public var sourceURL: String?
    public var author: String
    public var date: String
    public var createdAt: Date?
    public var lastOpenedAt: Date?
    public var finishedAt: Date?
    public var readTime: String
    public var lede: String
    public var tag: String
    public var document: Document
    public var progress: Double
    public var wordIndex: Int
    public var timesOpened: Int
    public var isFinished: Bool

    public var text: String { Document.flattenText(document) }

    public init(
        id: String,
        title: String,
        source: String,
        sourceURL: String? = nil,
        author: String,
        date: String,
        createdAt: Date? = nil,
        lastOpenedAt: Date? = nil,
        finishedAt: Date? = nil,
        readTime: String,
        lede: String,
        tag: String,
        document: Document,
        progress: Double,
        wordIndex: Int,
        timesOpened: Int,
        isFinished: Bool
    ) {
        self.id = id
        self.title = title
        self.source = source
        self.sourceURL = sourceURL
        self.author = author
        self.date = date
        self.createdAt = createdAt
        self.lastOpenedAt = lastOpenedAt
        self.finishedAt = finishedAt
        self.readTime = readTime
        self.lede = lede
        self.tag = tag
        self.document = document
        self.progress = progress
        self.wordIndex = wordIndex
        self.timesOpened = timesOpened
        self.isFinished = isFinished
    }

    public init(
        id: String,
        title: String,
        source: String,
        sourceURL: String? = nil,
        author: String,
        date: String,
        createdAt: Date? = nil,
        lastOpenedAt: Date? = nil,
        finishedAt: Date? = nil,
        readTime: String,
        lede: String,
        tag: String,
        text: String,
        progress: Double,
        wordIndex: Int,
        timesOpened: Int,
        isFinished: Bool
    ) {
        let document = Document(
            title: title,
            author: author,
            sourceUrl: sourceURL ?? "",
            sourceKind: "text",
            sections: [Section(id: "body", title: "", kind: .body, text: text)]
        )
        self.init(
            id: id,
            title: title,
            source: source,
            sourceURL: sourceURL,
            author: author,
            date: date,
            createdAt: createdAt,
            lastOpenedAt: lastOpenedAt,
            finishedAt: finishedAt,
            readTime: readTime,
            lede: lede,
            tag: tag,
            document: document,
            progress: progress,
            wordIndex: wordIndex,
            timesOpened: timesOpened,
            isFinished: isFinished
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, source, sourceURL, author, date
        case createdAt, lastOpenedAt, finishedAt
        case readTime, lede, tag
        case document, text
        case progress, wordIndex, timesOpened, isFinished
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let id = try c.decode(String.self, forKey: .id)
        let title = try c.decode(String.self, forKey: .title)
        let source = try c.decode(String.self, forKey: .source)
        let sourceURL = try c.decodeIfPresent(String.self, forKey: .sourceURL)
        let author = try c.decode(String.self, forKey: .author)
        let date = try c.decode(String.self, forKey: .date)
        let createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
        let lastOpenedAt = try c.decodeIfPresent(Date.self, forKey: .lastOpenedAt)
        let finishedAt = try c.decodeIfPresent(Date.self, forKey: .finishedAt)
        let readTime = try c.decode(String.self, forKey: .readTime)
        let lede = try c.decode(String.self, forKey: .lede)
        let tag = try c.decode(String.self, forKey: .tag)
        let progress = try c.decode(Double.self, forKey: .progress)
        let wordIndex = try c.decode(Int.self, forKey: .wordIndex)
        let timesOpened = try c.decode(Int.self, forKey: .timesOpened)
        let isFinished = try c.decode(Bool.self, forKey: .isFinished)

        let document: Document
        if let doc = try c.decodeIfPresent(Document.self, forKey: .document) {
            document = doc
        } else {
            let text = try c.decode(String.self, forKey: .text)
            document = Document(
                title: title,
                author: author,
                sourceUrl: sourceURL ?? "",
                sourceKind: "text",
                sections: [Section(id: "body", title: "", kind: .body, text: text)]
            )
        }

        self.init(
            id: id,
            title: title,
            source: source,
            sourceURL: sourceURL,
            author: author,
            date: date,
            createdAt: createdAt,
            lastOpenedAt: lastOpenedAt,
            finishedAt: finishedAt,
            readTime: readTime,
            lede: lede,
            tag: tag,
            document: document,
            progress: progress,
            wordIndex: wordIndex,
            timesOpened: timesOpened,
            isFinished: isFinished
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(source, forKey: .source)
        try c.encodeIfPresent(sourceURL, forKey: .sourceURL)
        try c.encode(author, forKey: .author)
        try c.encode(date, forKey: .date)
        try c.encodeIfPresent(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(lastOpenedAt, forKey: .lastOpenedAt)
        try c.encodeIfPresent(finishedAt, forKey: .finishedAt)
        try c.encode(readTime, forKey: .readTime)
        try c.encode(lede, forKey: .lede)
        try c.encode(tag, forKey: .tag)
        try c.encode(document, forKey: .document)
        try c.encode(text, forKey: .text)
        try c.encode(progress, forKey: .progress)
        try c.encode(wordIndex, forKey: .wordIndex)
        try c.encode(timesOpened, forKey: .timesOpened)
        try c.encode(isFinished, forKey: .isFinished)
    }

    public static func == (lhs: ReadingArticle, rhs: ReadingArticle) -> Bool {
        lhs.id == rhs.id
            && lhs.title == rhs.title
            && lhs.source == rhs.source
            && lhs.sourceURL == rhs.sourceURL
            && lhs.author == rhs.author
            && lhs.date == rhs.date
            && lhs.createdAt == rhs.createdAt
            && lhs.lastOpenedAt == rhs.lastOpenedAt
            && lhs.finishedAt == rhs.finishedAt
            && lhs.readTime == rhs.readTime
            && lhs.lede == rhs.lede
            && lhs.tag == rhs.tag
            && lhs.document == rhs.document
            && lhs.progress == rhs.progress
            && lhs.wordIndex == rhs.wordIndex
            && lhs.timesOpened == rhs.timesOpened
            && lhs.isFinished == rhs.isFinished
    }
}

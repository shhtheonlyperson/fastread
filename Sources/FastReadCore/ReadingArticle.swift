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
    public var text: String
    public var progress: Double
    public var wordIndex: Int
    public var timesOpened: Int
    public var isFinished: Bool

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
        self.text = text
        self.progress = progress
        self.wordIndex = wordIndex
        self.timesOpened = timesOpened
        self.isFinished = isFinished
    }
}

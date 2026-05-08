import Foundation

public enum SourceKind: String, Codable, Equatable, Sendable {
    case text
    case html
    case epub
}

public struct ImportOptions: Sendable {
    public var sourceUrl: String
    public var title: String
    public var author: String

    public init(sourceUrl: String = "", title: String = "", author: String = "") {
        self.sourceUrl = sourceUrl
        self.title = title
        self.author = author
    }
}

public enum ImporterError: Error, Equatable {
    case unknownKind(String)
    case invalidInput(String)
}

public protocol SourceAdapter {
    var kind: SourceKind { get }
    func canHandle(_ input: String) -> Bool
    func `import`(_ input: String, options: ImportOptions) throws -> Document
}

public struct PlainTextAdapter: SourceAdapter {
    public let kind: SourceKind = .text

    public init() {}

    public func canHandle(_ input: String) -> Bool { true }

    public func `import`(_ input: String, options: ImportOptions = ImportOptions()) throws -> Document {
        let text = ArticleTextExtractor.normalize(input)
        let section = Section(id: "body", title: "", kind: .body, text: text)
        return Document(
            title: options.title,
            author: options.author,
            sourceUrl: options.sourceUrl,
            sourceKind: SourceKind.text.rawValue,
            sections: [section]
        )
    }
}

public struct HtmlAdapter: SourceAdapter {
    public let kind: SourceKind = .html

    public init() {}

    public func canHandle(_ input: String) -> Bool {
        input.range(of: #"<[a-zA-Z!/]"#, options: .regularExpression) != nil
    }

    public func `import`(_ input: String, options: ImportOptions = ImportOptions()) throws -> Document {
        let text = ArticleTextExtractor.readableText(from: input)
        let title = options.title.isEmpty
            ? (ArticleTextExtractor.extractTitle(from: input) ?? "")
            : options.title
        let section = Section(id: "body", title: "", kind: .body, text: text)
        return Document(
            title: title,
            author: options.author,
            sourceUrl: options.sourceUrl,
            sourceKind: SourceKind.html.rawValue,
            sections: [section]
        )
    }
}

public final class ImporterRegistry: @unchecked Sendable {
    private var adapters: [SourceKind: any SourceAdapter] = [:]
    private let lock = NSLock()

    public init() {}

    public func register(_ adapter: any SourceAdapter) {
        lock.lock(); defer { lock.unlock() }
        adapters[adapter.kind] = adapter
    }

    public func adapter(for kind: SourceKind) -> (any SourceAdapter)? {
        lock.lock(); defer { lock.unlock() }
        return adapters[kind]
    }

    public func list() -> [any SourceAdapter] {
        lock.lock(); defer { lock.unlock() }
        return Array(adapters.values)
    }

    public func importDocument(
        kind: SourceKind,
        input: String,
        options: ImportOptions = ImportOptions()
    ) throws -> Document {
        guard let adapter = adapter(for: kind) else {
            throw ImporterError.unknownKind(kind.rawValue)
        }
        return try adapter.import(input, options: options)
    }

    public static let shared: ImporterRegistry = {
        let registry = ImporterRegistry()
        registry.register(PlainTextAdapter())
        registry.register(HtmlAdapter())
        return registry
    }()
}

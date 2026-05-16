import Foundation
import ZIPFoundation

public struct EpubMetadata: Equatable, Sendable {
    public var title: String?
    public var author: String?
    public var language: String?
}

public struct EpubSpineItem: Equatable, Sendable {
    public var id: String
    public var href: String
    public var mediaType: String?
    public var navTitle: String?
}

public enum EpubError: Error, Equatable {
    case invalidArchive
    case missingContainer
    case missingRootfile
    case missingOpf(String)
    case missingManifest
    case missingSpine
}

public enum EpubParser {
    public static func readEntries(from data: Data) throws -> [String: Data] {
        let archive: Archive
        do {
            archive = try Archive(data: data, accessMode: .read)
        } catch {
            throw EpubError.invalidArchive
        }
        var out: [String: Data] = [:]
        for entry in archive {
            guard entry.type == .file else { continue }
            var bytes = Data()
            _ = try archive.extract(entry, skipCRC32: true) { chunk in
                bytes.append(chunk)
            }
            out[entry.path] = bytes
        }
        return out
    }

    public static func parse(data: Data) throws -> (metadata: EpubMetadata, spine: [EpubSpineItem], opfPath: String, entries: [String: Data]) {
        let entries = try readEntries(from: data)
        guard let containerBytes = entries["META-INF/container.xml"] else {
            throw EpubError.missingContainer
        }
        let containerXml = decodeUtf8(containerBytes)
        guard let opfPath = findOpfPath(in: containerXml) else {
            throw EpubError.missingRootfile
        }
        guard let opfBytes = entries[opfPath] else {
            throw EpubError.missingOpf(opfPath)
        }
        let opfXml = decodeUtf8(opfBytes)
        let parsed = try parseOpf(opfXml)

        let navByOpfRel = resolveNavTitles(
            opfPath: opfPath,
            manifest: parsed.manifest,
            tocId: parsed.tocId,
            entries: entries
        )

        var spine: [EpubSpineItem] = []
        for idref in parsed.spineRefs {
            guard let item = parsed.manifest[idref] else { continue }
            let hrefNoFrag = stripFragment(item.href)
            let navTitle = navByOpfRel[hrefNoFrag]
            spine.append(EpubSpineItem(
                id: item.id,
                href: item.href,
                mediaType: item.mediaType,
                navTitle: navTitle
            ))
        }

        return (parsed.metadata, spine, opfPath, entries)
    }

    private struct ManifestItem {
        let id: String
        let href: String
        let mediaType: String?
        let properties: String?
    }

    private struct OpfParseResult {
        let metadata: EpubMetadata
        let manifest: [String: ManifestItem]
        let spineRefs: [String]
        let tocId: String?
    }

    private static func parseOpf(_ xml: String) throws -> OpfParseResult {
        let metadataBlock = firstBlock(xml, tag: "metadata") ?? ""
        let metadata = EpubMetadata(
            title: findFirstTagText(metadataBlock, localName: "title"),
            author: findFirstTagText(metadataBlock, localName: "creator"),
            language: findFirstTagText(metadataBlock, localName: "language")
        )

        guard let manifestBlock = firstBlock(xml, tag: "manifest") else {
            throw EpubError.missingManifest
        }
        var manifest: [String: ManifestItem] = [:]
        for tag in matchTags(manifestBlock, name: "item") {
            guard let id = attr(tag, name: "id"),
                  let href = attr(tag, name: "href")
            else { continue }
            manifest[id] = ManifestItem(
                id: id,
                href: href,
                mediaType: attr(tag, name: "media-type"),
                properties: attr(tag, name: "properties")
            )
        }

        guard let spineBlock = firstBlock(xml, tag: "spine") else {
            throw EpubError.missingSpine
        }
        let spineOpenTag = firstOpenTag(xml, name: "spine") ?? "<spine>"
        let tocId = attr(spineOpenTag, name: "toc")

        var spineRefs: [String] = []
        for tag in matchTags(spineBlock, name: "itemref") {
            if let idref = attr(tag, name: "idref") {
                spineRefs.append(idref)
            }
        }

        return OpfParseResult(metadata: metadata, manifest: manifest, spineRefs: spineRefs, tocId: tocId)
    }

    private static func resolveNavTitles(
        opfPath: String,
        manifest: [String: ManifestItem],
        tocId: String?,
        entries: [String: Data]
    ) -> [String: String] {
        var result: [String: String] = [:]

        let navItem = manifest.values.first { item in
            guard let p = item.properties else { return false }
            return p.range(of: #"\bnav\b"#, options: .regularExpression) != nil
        }
        let opfDir = directory(of: opfPath)

        if let nav = navItem {
            let navPath = joinPath(base: opfPath, rel: nav.href)
            if let navBytes = entries[navPath] {
                let navXml = decodeUtf8(navBytes)
                let rel = parseNavXhtml(navXml)
                for (href, title) in rel {
                    let abs = joinPath(base: navPath, rel: href)
                    let opfRel = abs.hasPrefix(opfDir) ? String(abs.dropFirst(opfDir.count)) : abs
                    result[opfRel] = title
                }
            }
        } else if let tocId, let ncxItem = manifest[tocId] {
            let ncxPath = joinPath(base: opfPath, rel: ncxItem.href)
            if let ncxBytes = entries[ncxPath] {
                let ncxXml = decodeUtf8(ncxBytes)
                let rel = parseTocNcx(ncxXml)
                for (href, title) in rel {
                    let abs = joinPath(base: ncxPath, rel: href)
                    let opfRel = abs.hasPrefix(opfDir) ? String(abs.dropFirst(opfDir.count)) : abs
                    result[opfRel] = title
                }
            }
        }
        return result
    }

    private static func parseNavXhtml(_ xml: String) -> [(String, String)] {
        var out: [(String, String)] = []
        let block: String = {
            if let r = xml.range(of: #"<nav\b[^>]*epub:type\s*=\s*("toc"|'toc')[^>]*>([\s\S]*?)</nav>"#, options: [.regularExpression, .caseInsensitive]),
               let inner = innerBetween(xml[r], openTagName: "nav", closeTag: "</nav>") {
                return inner
            }
            return xml
        }()
        let regex = try! NSRegularExpression(pattern: #"<a\b([^>]*)>([\s\S]*?)</a>"#, options: [.caseInsensitive])
        let ns = block as NSString
        let matches = regex.matches(in: block, range: NSRange(location: 0, length: ns.length))
        for m in matches {
            let attrPart = ns.substring(with: m.range(at: 1))
            let inner = ns.substring(with: m.range(at: 2))
            guard let href = attr("<a " + attrPart + ">", name: "href") else { continue }
            let stripped = inner.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            let text = decodeXmlEntities(stripped.trimmingCharacters(in: .whitespacesAndNewlines))
            if !text.isEmpty {
                out.append((href, text))
            }
        }
        return out
    }

    private static func parseTocNcx(_ xml: String) -> [(String, String)] {
        var out: [(String, String)] = []
        let regex = try! NSRegularExpression(pattern: #"<navPoint\b[^>]*>([\s\S]*?)</navPoint>"#, options: [.caseInsensitive])
        let ns = xml as NSString
        let matches = regex.matches(in: xml, range: NSRange(location: 0, length: ns.length))
        for m in matches {
            let inner = ns.substring(with: m.range(at: 1))
            guard let labelRange = inner.range(of: #"<navLabel\b[^>]*>([\s\S]*?)</navLabel>"#, options: [.regularExpression, .caseInsensitive]) else { continue }
            let labelBlock = String(inner[labelRange])
            guard let textRange = labelBlock.range(of: #"<text\b[^>]*>([\s\S]*?)</text>"#, options: [.regularExpression, .caseInsensitive]) else { continue }
            let textBlock = String(labelBlock[textRange])
            let text = decodeXmlEntities(
                textBlock
                    .replacingOccurrences(of: #"^<text\b[^>]*>"#, with: "", options: [.regularExpression, .caseInsensitive])
                    .replacingOccurrences(of: #"</text>$"#, with: "", options: [.regularExpression, .caseInsensitive])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            )
            guard let contentRange = inner.range(of: #"<content\b[^>]*/?>"#, options: [.regularExpression, .caseInsensitive]) else { continue }
            let contentTag = String(inner[contentRange])
            guard let src = attr(contentTag, name: "src") else { continue }
            if !text.isEmpty {
                out.append((src, text))
            }
        }
        return out
    }

    private static func findOpfPath(in containerXml: String) -> String? {
        guard let r = containerXml.range(of: #"<rootfile\b[^>]*>"#, options: [.regularExpression, .caseInsensitive]) else { return nil }
        return attr(String(containerXml[r]), name: "full-path")
    }

    static func attr(_ tag: String, name: String) -> String? {
        let pattern = "\\b\(NSRegularExpression.escapedPattern(for: name))\\s*=\\s*(\"([^\"]*)\"|'([^']*)')"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let ns = tag as NSString
        guard let m = regex.firstMatch(in: tag, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let dq = m.range(at: 2)
        let sq = m.range(at: 3)
        let valueRange = dq.location != NSNotFound ? dq : sq
        guard valueRange.location != NSNotFound else { return nil }
        let raw = ns.substring(with: valueRange)
        return decodeXmlEntities(raw)
    }

    private static func firstBlock(_ xml: String, tag: String) -> String? {
        let pattern = "<(?:[a-zA-Z][\\w.-]*:)?\(tag)\\b[^>]*>([\\s\\S]*?)</(?:[a-zA-Z][\\w.-]*:)?\(tag)>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let ns = xml as NSString
        guard let m = regex.firstMatch(in: xml, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return ns.substring(with: m.range(at: 1))
    }

    private static func firstOpenTag(_ xml: String, name: String) -> String? {
        let pattern = "<(?:[a-zA-Z][\\w.-]*:)?\(name)\\b[^>]*>"
        guard let r = xml.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else { return nil }
        return String(xml[r])
    }

    private static func matchTags(_ xml: String, name: String) -> [String] {
        let pattern = "<\(name)\\b[^>]*/?>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let ns = xml as NSString
        let matches = regex.matches(in: xml, range: NSRange(location: 0, length: ns.length))
        return matches.map { ns.substring(with: $0.range) }
    }

    private static func findFirstTagText(_ xml: String, localName: String) -> String? {
        let pattern = "<(?:[a-zA-Z][\\w.-]*:)?\(localName)\\b[^>]*>([\\s\\S]*?)</(?:[a-zA-Z][\\w.-]*:)?\(localName)>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let ns = xml as NSString
        guard let m = regex.firstMatch(in: xml, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let raw = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
        return decodeXmlEntities(raw)
    }

    private static func innerBetween(_ sub: Substring, openTagName: String, closeTag: String) -> String? {
        let s = String(sub)
        guard let openEnd = s.range(of: ">") else { return nil }
        guard let closeStart = s.range(of: closeTag, options: [.backwards, .caseInsensitive]) else { return nil }
        if openEnd.upperBound > closeStart.lowerBound { return nil }
        return String(s[openEnd.upperBound..<closeStart.lowerBound])
    }
}

// MARK: - Helpers (file-internal)

private func directory(of path: String) -> String {
    if let slash = path.lastIndex(of: "/") {
        return String(path[...slash])
    }
    return ""
}

private func stripFragment(_ href: String) -> String {
    if let i = href.firstIndex(of: "#") {
        return String(href[..<i])
    }
    return href
}

private func joinPath(base: String, rel: String) -> String {
    if rel.isEmpty { return rel }
    if rel.range(of: #"^[a-z][a-z0-9+.-]*:"#, options: [.regularExpression, .caseInsensitive]) != nil {
        return rel
    }
    let cleanRel = stripFragment(rel)
    let baseDir = directory(of: base)
    let combined = baseDir + cleanRel
    var stack: [String] = []
    for part in combined.split(separator: "/", omittingEmptySubsequences: false) {
        if part.isEmpty || part == "." { continue }
        if part == ".." { _ = stack.popLast() }
        else { stack.append(String(part)) }
    }
    return stack.joined(separator: "/")
}

private func decodeUtf8(_ data: Data) -> String {
    String(data: data, encoding: .utf8) ?? ""
}

private func decodeXmlEntities(_ s: String) -> String {
    var out = s
        .replacingOccurrences(of: "&lt;", with: "<")
        .replacingOccurrences(of: "&gt;", with: ">")
        .replacingOccurrences(of: "&quot;", with: "\"")
        .replacingOccurrences(of: "&apos;", with: "'")
    out = decodeNumericEntities(out)
    out = out.replacingOccurrences(of: "&amp;", with: "&")
    return out
}

private func decodeNumericEntities(_ s: String) -> String {
    var result = ""
    var i = s.startIndex
    while i < s.endIndex {
        if s[i] == "&", let semi = s[i...].firstIndex(of: ";") {
            let entity = String(s[s.index(after: i)..<semi])
            if entity.hasPrefix("#x") || entity.hasPrefix("#X") {
                if let code = UInt32(entity.dropFirst(2), radix: 16), let scalar = Unicode.Scalar(code) {
                    result.append(Character(scalar))
                    i = s.index(after: semi)
                    continue
                }
            } else if entity.hasPrefix("#") {
                if let code = UInt32(entity.dropFirst(1)), let scalar = Unicode.Scalar(code) {
                    result.append(Character(scalar))
                    i = s.index(after: semi)
                    continue
                }
            }
        }
        result.append(s[i])
        i = s.index(after: i)
    }
    return result
}

// MARK: - HTML to text (parity with src/article-extract.js htmlToText)

public enum EpubHtmlText {
    public static func htmlToText(_ html: String) -> String {
        var s = html

        let patterns: [(String, String)] = [
            (#"<!--[\s\S]*?-->"#, " "),
            (#"<script\b[\s\S]*?</script>"#, " "),
            (#"<style\b[\s\S]*?</style>"#, " "),
            (#"<svg\b[\s\S]*?</svg>"#, " "),
            (#"<noscript\b[\s\S]*?</noscript>"#, " "),
            (#"<template\b[\s\S]*?</template>"#, " "),
            (#"<iframe\b[\s\S]*?</iframe>"#, " "),
            (#"<(nav|header|footer|aside|form)\b[\s\S]*?</\1>"#, " "),
            (#"<(h[1-6]|p|blockquote|li|figcaption|pre|tr|div|section|article)\b[^>]*>"#, "\n"),
            (#"<br\s*/?>"#, "\n"),
            (#"</(h[1-6]|p|blockquote|li|figcaption|pre|tr|div|section|article)>"#, "\n"),
            (#"<[^>]+>"#, " "),
        ]

        for (pattern, replacement) in patterns {
            s = s.replacingOccurrences(of: pattern, with: replacement, options: [.regularExpression, .caseInsensitive])
        }
        s = decodeXmlEntities(s)
        return normalizeText(s)
    }

    public static func normalizeText(_ value: String) -> String {
        var s = value
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: #"[ \t\f\v]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #" *\n *"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return s
    }
}

// MARK: - Adapter

public struct EpubImporter: Sendable {
    public let kind: SourceKind = .epub

    public init() {}

    public func canHandle(filename: String) -> Bool {
        filename.range(of: #"\.epub$"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    public func canHandle(data: Data) -> Bool {
        guard data.count >= 4 else { return false }
        return data[0] == 0x50 && data[1] == 0x4b && data[2] == 0x03 && data[3] == 0x04
    }

    public func `import`(data: Data, options: ImportOptions = ImportOptions()) throws -> Document {
        let parsed = try EpubParser.parse(data: data)
        var sections: [Section] = []
        for item in parsed.spine {
            let hrefNoFrag = stripFragment(item.href)
            let chapterPath = joinPath(base: parsed.opfPath, rel: hrefNoFrag)
            guard let bytes = parsed.entries[chapterPath] else { continue }
            let html = decodeUtf8(bytes)
            let text = EpubHtmlText.htmlToText(html)
            if text.isEmpty { continue }
            sections.append(Section(
                id: item.id,
                title: item.navTitle ?? "",
                kind: .chapter,
                text: text
            ))
        }
        let title = !options.title.isEmpty
            ? options.title
            : (parsed.metadata.title ?? "")
        let author = !options.author.isEmpty
            ? options.author
            : (parsed.metadata.author ?? "")
        return Document(
            title: title,
            author: author,
            sourceUrl: options.sourceUrl,
            sourceKind: SourceKind.epub.rawValue,
            sections: sections
        )
    }
}

// MARK: - Registry extension

extension ImporterRegistry {
    public func importEpub(data: Data, options: ImportOptions = ImportOptions()) throws -> Document {
        let importer = EpubImporter()
        return try importer.import(data: data, options: options)
    }
}

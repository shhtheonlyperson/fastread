import Foundation
import NaturalLanguage

public enum RSVPEngine {
    /// Bump when the tokenizer or shaper produces a materially different
    /// chunking for the same input. Persisted tokens whose recorded
    /// `tokenizerVersion` doesn't match are discarded and recomputed.
    // Constants & rule tables are single-sourced from Tools/rsvp-spec.json via
    // the generated RSVPSpec (see RSVPSpec.generated.swift). Don't inline new
    // literals here — add them to the spec so all three platforms stay in sync.
    public static let version: Int = RSVPSpec.version
    public static let defaultWPM: Double = RSVPSpec.WPM.default
    public static let minimumSafeWPM: Double = RSVPSpec.WPM.minimumSafe
    /// Latin-script floor for the user-facing WPM slider. CJK content uses the
    /// lower `minimumUserWPM(forCJK:)` floor.
    public static let minimumUserWPM: Double = RSVPSpec.WPM.minimumUserLatin
    public static let maximumWPM: Double = RSVPSpec.WPM.maximum
    public static let wpmStep: Double = RSVPSpec.WPM.step

    /// Script-dependent floor for the WPM slider: CJK is denser per glyph and
    /// already carries a duration multiplier, so it reads comfortably slower.
    public static func minimumUserWPM(forCJK isCJK: Bool) -> Double {
        isCJK ? RSVPSpec.WPM.minimumUserCJK : RSVPSpec.WPM.minimumUserLatin
    }

    public struct FocusSplit: Equatable {
        public let before: String
        public let focus: String
        public let after: String

        public init(before: String, focus: String, after: String) {
            self.before = before
            self.focus = focus
            self.after = after
        }
    }

    public struct ContextWindow: Equatable {
        public let lowerBound: Int
        public let upperBound: Int
        public let hasLeadingOverflow: Bool
        public let hasTrailingOverflow: Bool

        public init(lowerBound: Int, upperBound: Int, hasLeadingOverflow: Bool, hasTrailingOverflow: Bool) {
            self.lowerBound = lowerBound
            self.upperBound = upperBound
            self.hasLeadingOverflow = hasLeadingOverflow
            self.hasTrailingOverflow = hasTrailingOverflow
        }

        public var range: Range<Int> {
            lowerBound..<upperBound
        }

        public var count: Int {
            max(upperBound - lowerBound, 0)
        }
    }

    public static func countReadingUnits(_ input: String?) -> Int {
        tokenize(input).filter { token in
            token.contains { isFocusable($0) || isCJKCharacter($0) }
        }.count
    }

    public static func containsCJK(_ input: String?) -> Bool {
        guard let input else { return false }
        return hasCJK(input)
    }

    public static func tokenize(_ input: String?, userDictionary: [String] = []) -> [String] {
        guard let input else { return [] }
        let normalized = input.replacingOccurrences(of: "\u{00a0}", with: " ")
        guard hasCJK(normalized) else {
            return normalized
                .split(whereSeparator: { $0.isWhitespace })
                .map(String.init)
        }
        return tokenizeMixed(normalized, userDictionary: userDictionary)
    }

    public static func focusIndex(in token: String?) -> Int {
        let characters = Array(token ?? "")
        guard !characters.isEmpty else { return 0 }

        let focusable = characters.indices.filter { isFocusable(characters[$0]) }
        guard !focusable.isEmpty else {
            return characters.count / 2
        }

        let target: Int
        switch focusable.count {
        case ...1:
            target = 0
        case 2...5:
            target = 1
        case 6...9:
            target = 2
        case 10...13:
            target = 3
        default:
            target = 4
        }

        return focusable[min(target, focusable.count - 1)]
    }

    public static func splitForFocus(_ token: String?) -> FocusSplit {
        let characters = Array(token ?? "")
        guard !characters.isEmpty else {
            return FocusSplit(before: "", focus: "", after: "")
        }

        let index = focusIndex(in: token)
        return FocusSplit(
            before: String(characters[..<index]),
            focus: String(characters[index]),
            after: String(characters[(index + 1)...])
        )
    }

    public static func duration(for token: String?, wpm: Double, punctuationPause: Bool = true) -> Int {
        let safeWPM = safeWPM(wpm)
        let base = RSVPSpec.Duration.baseMillisPerMinute / safeWPM
        let rawToken = token ?? ""
        let isCJK = hasCJK(rawToken)
        let focusableCount = Array(rawToken).filter { isFocusable($0) || isCJKCharacter($0) }.count
        let cjkMultiplier = isCJK ? RSVPSpec.Duration.cjkMultiplier : 1
        let threshold = RSVPSpec.Duration.lengthThreshold
        let lengthMultiplier = focusableCount > threshold
            ? 1 + min(Double(focusableCount - threshold) * RSVPSpec.Duration.lengthPerCharIncrement, RSVPSpec.Duration.lengthMaxIncrement)
            : 1
        let pauseMultiplier = punctuationPause && endsWithPunctuationPause(rawToken) ? RSVPSpec.Duration.pauseMultiplier : 1

        return Int((base * cjkMultiplier * lengthMultiplier * pauseMultiplier).rounded())
    }

    public static func estimateMinutes(wordCount: Int, wpm: Double) -> Double {
        let safeWPM = safeWPM(wpm)
        return Double(wordCount) / safeWPM
    }

    public static func contextWindow(
        tokenCount: Int,
        currentIndex: Int,
        before: Int = 18,
        after: Int = 36
    ) -> ContextWindow {
        guard tokenCount > 0 else {
            return ContextWindow(
                lowerBound: 0,
                upperBound: 0,
                hasLeadingOverflow: false,
                hasTrailingOverflow: false
            )
        }

        let safeBefore = max(before, 0)
        let safeAfter = max(after, 0)
        let clampedIndex = clamp(currentIndex, min: 0, max: tokenCount - 1)
        let lowerBound = max(0, clampedIndex - safeBefore)
        let upperBound = min(tokenCount, clampedIndex + safeAfter + 1)
        return ContextWindow(
            lowerBound: lowerBound,
            upperBound: upperBound,
            hasLeadingOverflow: lowerBound > 0,
            hasTrailingOverflow: upperBound < tokenCount
        )
    }

    public static func clamp<T: Comparable>(_ value: T, min: T, max: T) -> T {
        Swift.min(Swift.max(value, min), max)
    }

    private static func isFocusable(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            switch scalar.properties.generalCategory {
            case .uppercaseLetter,
                 .lowercaseLetter,
                 .titlecaseLetter,
                 .modifierLetter,
                 .otherLetter,
                 .decimalNumber,
                 .letterNumber,
                 .otherNumber:
                return true
            default:
                return false
            }
        }
    }

    private static func tokenizeMixed(_ input: String, userDictionary: [String]) -> [String] {
        var tokens: [String] = []
        for segment in splitByScript(input) {
            if segment.isCJK {
                tokens.append(contentsOf: tokenizeCJKSegment(segment.text, userDictionary: userDictionary))
            } else {
                tokens.append(
                    contentsOf: segment.text
                        .split(whereSeparator: { $0.isWhitespace })
                        .map(String.init)
                )
            }
        }
        // ICU + script-split alone over-segments — names, particles, and
        // number+measure-word pairs come out as single Han chars. The
        // ChunkShaper post-pass merges those back into rhythmic 2–4 char
        // chunks that match how the eye-brain pipeline actually reads.
        // See Tools/FastReadTokenizerStats + Tests/Fixtures/rsvp-gold-corpus.tsv.
        return ChunkShaper.shape(tokens)
    }

    private static func splitByScript(_ input: String) -> [(text: String, isCJK: Bool)] {
        var segments: [(String, Bool)] = []
        var buffer = ""
        var bufferIsCJK: Bool? = nil
        for character in input {
            let cjk = isCJKCharacter(character) || isCJKPunctuation(character)
            if let previous = bufferIsCJK, previous != cjk {
                segments.append((buffer, previous))
                buffer = ""
            }
            buffer.append(character)
            bufferIsCJK = cjk
        }
        if let last = bufferIsCJK, !buffer.isEmpty {
            segments.append((buffer, last))
        }
        return segments
    }

    private static func tokenizeCJKSegment(_ text: String, userDictionary: [String]) -> [String] {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text

        var raw: [(text: String, lo: String.Index, hi: String.Index)] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let slice = String(text[range])
            if !slice.isEmpty {
                raw.append((slice, range.lowerBound, range.upperBound))
            }
            return true
        }

        let merged = applyUserDictionary(raw, in: text, dictionary: userDictionary)

        var tokens: [String] = []
        // Punctuation that appears in the gap BEFORE the first token (e.g.,
        // an opening 「) is buffered and prepended to the first word, so
        // quoted phrases keep their opening mark instead of dropping it.
        var leadingPunct = ""
        var lastEnd = text.startIndex
        for span in merged {
            if lastEnd < span.lo {
                let gap = text[lastEnd..<span.lo]
                for character in gap {
                    guard isCJKPunctuation(character) || isASCIIPunctuationPause(character) else { continue }
                    if tokens.isEmpty {
                        leadingPunct.append(character)
                    } else {
                        tokens[tokens.count - 1].append(character)
                    }
                }
            }
            if tokens.isEmpty, !leadingPunct.isEmpty {
                tokens.append(leadingPunct + span.text)
                leadingPunct = ""
            } else {
                tokens.append(span.text)
            }
            lastEnd = span.hi
        }
        if lastEnd < text.endIndex {
            attachInterstitialPunctuation(text[lastEnd..<text.endIndex], to: &tokens)
        }
        return tokens
    }

    private static func attachInterstitialPunctuation(_ slice: Substring, to tokens: inout [String]) {
        for character in slice {
            guard isCJKPunctuation(character) || isASCIIPunctuationPause(character) else { continue }
            if !tokens.isEmpty {
                tokens[tokens.count - 1].append(character)
            }
        }
    }

    private static func applyUserDictionary(
        _ raw: [(text: String, lo: String.Index, hi: String.Index)],
        in source: String,
        dictionary: [String]
    ) -> [(text: String, lo: String.Index, hi: String.Index)] {
        let entries = Set(dictionary.filter { !$0.isEmpty })
        guard !entries.isEmpty, !raw.isEmpty else { return raw }
        let maxLength = entries.map(\.count).max() ?? 0
        guard maxLength > 0 else { return raw }

        var result: [(text: String, lo: String.Index, hi: String.Index)] = []
        var index = 0
        while index < raw.count {
            var bestEnd: Int? = nil
            var concat = ""
            var probe = index
            while probe < raw.count {
                concat.append(raw[probe].text)
                if concat.count > maxLength { break }
                if entries.contains(concat) {
                    bestEnd = probe
                }
                probe += 1
            }
            if let end = bestEnd {
                let mergedText = String(source[raw[index].lo..<raw[end].hi])
                result.append((mergedText, raw[index].lo, raw[end].hi))
                index = end + 1
            } else {
                result.append(raw[index])
                index += 1
            }
        }
        return result
    }

    private static func hasCJK(_ string: String) -> Bool {
        string.contains(where: isCJKCharacter)
    }

    private static func isCJKCharacter(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            RSVPSpec.cjkRanges.contains { $0.contains(scalar.value) }
        }
    }

    private static func isCJKPunctuation(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            RSVPSpec.cjkPunctuationRanges.contains { $0.contains(scalar.value) }
        }
    }

    private static func safeWPM(_ wpm: Double) -> Double {
        let raw = wpm.isFinite && wpm != 0 ? wpm : defaultWPM
        return clamp(raw, min: minimumSafeWPM, max: maximumWPM)
    }

    private static func endsWithPunctuationPause(_ token: String) -> Bool {
        if hasCJK(token) {
            guard let last = token.last else { return false }
            return isCJKPunctuation(last) || isASCIIPunctuationPause(last)
        }

        let punctuation = RSVPSpec.latinSentenceEnd
        let trailingClosers = RSVPSpec.latinTrailingClosers
        let characters = Array(token)

        for index in characters.indices.reversed() {
            if punctuation.contains(characters[index]) {
                let tail = characters.dropFirst(index + 1)
                return tail.allSatisfy { trailingClosers.contains($0) }
            }

            if !trailingClosers.contains(characters[index]) {
                return false
            }
        }

        return false
    }

    private static func isASCIIPunctuationPause(_ character: Character) -> Bool {
        RSVPSpec.asciiPause.contains(character)
    }
}

public enum SourceInputClassifier {
    public static func normalizedURLString(from value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: { $0.isWhitespace }) else { return nil }

        let normalized = trimmed.range(
            of: #"^[a-z][a-z0-9+.-]*://"#,
            options: [.regularExpression, .caseInsensitive]
        ) == nil
            ? "https://\(trimmed)"
            : trimmed

        guard
            let components = URLComponents(string: normalized),
            let scheme = components.scheme?.lowercased(),
            ["http", "https"].contains(scheme),
            let host = components.host,
            isPlausibleHost(host)
        else {
            return nil
        }

        return normalized
    }

    public static func isLikelySingleURL(_ value: String) -> Bool {
        normalizedURLString(from: value) != nil
    }

    private static func isPlausibleHost(_ host: String) -> Bool {
        host == "localhost" || host.contains(".") || host.contains(":")
    }
}

public enum ArticleTextExtractor {
    public static func readableText(from html: String) -> String {
        normalize(stripTags(html))
    }

    public static func extractTitle(from html: String) -> String? {
        guard let range = html.range(of: #"<title[^>]*>(.*?)</title>"#, options: [.regularExpression, .caseInsensitive]) else {
            return nil
        }
        let raw = html[range]
            .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        let title = normalize(stripTags(String(raw)))
        return title.isEmpty ? nil : title
    }

    public static func stripTags(_ html: String) -> String {
        html
            .replacingOccurrences(of: #"<head[\s\S]*?</head>"#, with: " ", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"<(script|style|noscript|svg)[\s\S]*?</\1>"#, with: " ", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"</(p|div|article|section|h[1-6]|li|br)[^>]*>"#, with: "\n", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&rsquo;", with: "'")
            .replacingOccurrences(of: "&lsquo;", with: "'")
            .replacingOccurrences(of: "&ldquo;", with: "\"")
            .replacingOccurrences(of: "&rdquo;", with: "\"")
            .replacingOccurrences(of: "&mdash;", with: "-")
            .replacingOccurrences(of: "&ndash;", with: "-")
    }

    public static func normalize(_ text: String) -> String {
        text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

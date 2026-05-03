import Foundation

public enum RSVPEngine {
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

    public static func tokenize(_ input: String?) -> [String] {
        guard let input else { return [] }
        let normalized = input.replacingOccurrences(of: "\u{00a0}", with: " ")
        guard hasCJK(normalized) else {
            return normalized
                .split(whereSeparator: { $0.isWhitespace })
                .map(String.init)
        }
        return tokenizeCJK(normalized)
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
        let base = 60_000 / safeWPM
        let rawToken = token ?? ""
        let isCJK = hasCJK(rawToken)
        let focusableCount = Array(rawToken).filter { isFocusable($0) || isCJKCharacter($0) }.count
        let cjkMultiplier = isCJK ? 1.5 : 1
        let lengthMultiplier = focusableCount > 9
            ? 1 + min(Double(focusableCount - 9) * 0.07, 0.6)
            : 1
        let pauseMultiplier = punctuationPause && endsWithPunctuationPause(rawToken) ? 1.65 : 1

        return Int((base * cjkMultiplier * lengthMultiplier * pauseMultiplier).rounded())
    }

    public static func estimateMinutes(wordCount: Int, wpm: Double) -> Double {
        let safeWPM = safeWPM(wpm)
        return Double(wordCount) / safeWPM
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

    private static func tokenizeCJK(_ input: String) -> [String] {
        var tokens: [String] = []
        var buffer: [Character] = []
        let characters = Array(input)
        var index = 0

        func flush() {
            guard !buffer.isEmpty else { return }
            tokens.append(String(buffer))
            buffer.removeAll()
        }

        while index < characters.count {
            let character = characters[index]

            if character.isWhitespace {
                flush()
                index += 1
                continue
            }

            if isCJKPunctuation(character) || isASCIIPunctuationPause(character) {
                if !buffer.isEmpty {
                    buffer.append(character)
                    flush()
                } else if !tokens.isEmpty {
                    tokens[tokens.count - 1].append(character)
                }
                index += 1
                continue
            }

            if isCJKCharacter(character) {
                buffer.append(character)
                if buffer.filter(isCJKCharacter).count >= 2 {
                    flush()
                }
                index += 1
                continue
            }

            flush()
            var word = String(character)
            while index + 1 < characters.count,
                  !characters[index + 1].isWhitespace,
                  !isCJKCharacter(characters[index + 1]),
                  !isCJKPunctuation(characters[index + 1]) {
                index += 1
                word.append(characters[index])
            }
            tokens.append(word)
            index += 1
        }

        flush()
        return tokens
    }

    private static func hasCJK(_ string: String) -> Bool {
        string.contains(where: isCJKCharacter)
    }

    private static func isCJKCharacter(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            inRange(scalar.value, 0x3040, 0x30ff) ||
            inRange(scalar.value, 0x3400, 0x4dbf) ||
            inRange(scalar.value, 0x4e00, 0x9fff) ||
            inRange(scalar.value, 0xf900, 0xfaff) ||
            inRange(scalar.value, 0xac00, 0xd7af)
        }
    }

    private static func isCJKPunctuation(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            inRange(scalar.value, 0x3000, 0x303f) ||
            inRange(scalar.value, 0xff00, 0xffef)
        }
    }

    private static func inRange(_ value: UInt32, _ lower: UInt32, _ upper: UInt32) -> Bool {
        value >= lower && value <= upper
    }

    private static func safeWPM(_ wpm: Double) -> Double {
        let raw = wpm.isFinite && wpm != 0 ? wpm : 450
        return clamp(raw, min: 100, max: 1200)
    }

    private static func endsWithPunctuationPause(_ token: String) -> Bool {
        if hasCJK(token) {
            guard let last = token.last else { return false }
            return isCJKPunctuation(last) || isASCIIPunctuationPause(last)
        }

        let punctuation: Set<Character> = [".", "!", "?", ";", ":", ")"]
        let trailingClosers: Set<Character> = ["\"", "'", ")", "]"]
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
        [".", ",", "!", "?", ";", ":"].contains(character)
    }
}

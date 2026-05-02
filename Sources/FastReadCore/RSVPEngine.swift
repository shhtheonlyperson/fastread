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
        return input
            .replacingOccurrences(of: "\u{00a0}", with: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
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
        let focusableCount = Array(token ?? "").filter(isFocusable).count
        let lengthMultiplier = focusableCount > 9
            ? 1 + min(Double(focusableCount - 9) * 0.07, 0.6)
            : 1
        let pauseMultiplier = punctuationPause && endsWithPunctuationPause(token ?? "") ? 1.65 : 1

        return Int((base * lengthMultiplier * pauseMultiplier).rounded())
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

    private static func safeWPM(_ wpm: Double) -> Double {
        let raw = wpm.isFinite && wpm != 0 ? wpm : 450
        return clamp(raw, min: 100, max: 1200)
    }

    private static func endsWithPunctuationPause(_ token: String) -> Bool {
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
}

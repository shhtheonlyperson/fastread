import FastReadCore
import Foundation

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("Verifier failed: \(message)\n", stderr)
        exit(1)
    }
}

let tokens = RSVPEngine.tokenize("  Read\tfast.\nNow  ")
expect(tokens == ["Read", "fast.", "Now"], "tokenize should split whitespace and preserve punctuation")
expect(RSVPEngine.tokenize("Read\u{00a0}fast") == ["Read", "fast"], "tokenize should normalize nbsp")

expect(RSVPEngine.focusIndex(in: "a") == 0, "one focusable character should use index 0")
expect(RSVPEngine.focusIndex(in: "read") == 1, "2-5 focusable characters should use focusable index 1")
expect(RSVPEngine.focusIndex(in: "focused") == 2, "6-9 focusable characters should use focusable index 2")
expect(RSVPEngine.focusIndex(in: "recognition") == 3, "10-13 focusable characters should use focusable index 3")
expect(RSVPEngine.focusIndex(in: "\"read") == 2, "leading punctuation should not count as focusable")
expect(
    RSVPEngine.splitForFocus("\"read") == RSVPEngine.FocusSplit(before: "\"r", focus: "e", after: "ad"),
    "splitForFocus should return original string slices"
)

let base = RSVPEngine.duration(for: "read", wpm: 600, punctuationPause: false)
expect(base == 100, "600 wpm base duration should be 100ms")
expect(RSVPEngine.duration(for: "read.", wpm: 600, punctuationPause: true) > base, "punctuation should pause")
expect(RSVPEngine.duration(for: "internationalization", wpm: 600, punctuationPause: false) > base, "long words should last longer")
expect(RSVPEngine.duration(for: "read)", wpm: 600, punctuationPause: true) > base, "closing parenthesis should pause")
expect(RSVPEngine.duration(for: "read\")", wpm: 600, punctuationPause: true) > base, "quote plus closer should pause")

expect(RSVPEngine.estimateMinutes(wordCount: 900, wpm: 900) == 1, "ETA should divide words by wpm")
expect(RSVPEngine.duration(for: "read", wpm: 0, punctuationPause: false) == 133, "invalid wpm should default to 450")
expect(RSVPEngine.duration(for: "read", wpm: 10_000, punctuationPause: false) == 50, "wpm should clamp at 1200")

print("FastReadCoreVerifier passed")

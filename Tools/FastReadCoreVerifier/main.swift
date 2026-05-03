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
expect(
    RSVPEngine.tokenize("快速閱讀，眼睛更輕鬆。") == ["快速", "閱讀，", "眼睛", "更輕", "鬆。"],
    "tokenize should split Traditional Chinese into two-character chunks with punctuation attached"
)
expect(
    RSVPEngine.tokenize("JustRead 支援中文。") == ["JustRead", "支援", "中文。"],
    "tokenize should preserve mixed Latin and CJK runs"
)

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
expect(RSVPEngine.duration(for: "閱讀", wpm: 600, punctuationPause: false) == 150, "CJK chunks should get 1.5x base duration")
expect(RSVPEngine.duration(for: "internationalization", wpm: 600, punctuationPause: false) > base, "long words should last longer")
expect(RSVPEngine.duration(for: "read)", wpm: 600, punctuationPause: true) > base, "closing parenthesis should pause")
expect(RSVPEngine.duration(for: "read\")", wpm: 600, punctuationPause: true) > base, "quote plus closer should pause")

expect(RSVPEngine.estimateMinutes(wordCount: 900, wpm: 900) == 1, "ETA should divide words by wpm")
expect(RSVPEngine.duration(for: "read", wpm: 0, punctuationPause: false) == 133, "invalid wpm should default to 450")
expect(RSVPEngine.duration(for: "read", wpm: 10_000, punctuationPause: false) == 50, "wpm should clamp at 1200")

let middleContext = RSVPEngine.contextWindow(tokenCount: 1_000, currentIndex: 500)
expect(middleContext.lowerBound == 482, "context window should include bounded tokens before the current word")
expect(middleContext.upperBound == 537, "context window should include bounded tokens after the current word")
expect(middleContext.count == 55, "default context window should stay bounded")
expect(middleContext.hasLeadingOverflow && middleContext.hasTrailingOverflow, "middle context should mark both overflow sides")
let startContext = RSVPEngine.contextWindow(tokenCount: 10, currentIndex: 0)
expect(startContext.range == 0..<10, "short context should include all available tokens")
expect(!startContext.hasLeadingOverflow && !startContext.hasTrailingOverflow, "short context should not show overflow")

expect(SourceInputClassifier.normalizedURLString(from: "partyon.xyz/@nullagent/116499715071759135") == "https://partyon.xyz/@nullagent/116499715071759135", "URL classifier should add https to bare domains")
expect(SourceInputClassifier.isLikelySingleURL("https://partyon.xyz/@nullagent/116499715071759135"), "URL classifier should accept pasted https URLs")
expect(SourceInputClassifier.isLikelySingleURL("http://localhost:4173/article"), "URL classifier should accept localhost URLs")
expect(!SourceInputClassifier.isLikelySingleURL("hello"), "URL classifier should reject a single normal word")
expect(!SourceInputClassifier.isLikelySingleURL("hello world"), "URL classifier should reject multi-word pasted text")

let html = "<html><head><title>Readable &amp; Fast</title><style>.x{}</style></head><body><p>Hello&nbsp;reader.</p><script>bad()</script><p>Keep &ldquo;content&rdquo;.</p></body></html>"
expect(ArticleTextExtractor.extractTitle(from: html) == "Readable & Fast", "extractTitle should decode title text")
expect(ArticleTextExtractor.readableText(from: html) == "Hello reader. Keep \"content\".", "readableText should strip chrome and decode common entities")

print("FastReadCoreVerifier passed")

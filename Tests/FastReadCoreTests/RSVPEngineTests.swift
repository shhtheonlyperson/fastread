import FastReadCore
import XCTest

final class RSVPEngineTests: XCTestCase {
    func testTokenizeHandlesWhitespaceEnglishAndNBSP() {
        XCTAssertEqual(RSVPEngine.tokenize(nil), [])
        XCTAssertEqual(RSVPEngine.tokenize("  Read\tfast.\nNow  "), ["Read", "fast.", "Now"])
        XCTAssertEqual(RSVPEngine.tokenize("Read\u{00a0}fast"), ["Read", "fast"])
    }

    func testTokenizeHandlesTraditionalSimplifiedAndMixedCJK() {
        XCTAssertEqual(
            RSVPEngine.tokenize("快速閱讀，眼睛更輕鬆。"),
            ["快速", "閱讀，", "眼睛", "更輕", "鬆。"]
        )
        XCTAssertEqual(
            RSVPEngine.tokenize("快速阅读让注意力更稳定。"),
            ["快速", "阅读", "让注", "意力", "更稳", "定。"]
        )
        XCTAssertEqual(
            RSVPEngine.tokenize("JustRead 支援中文。"),
            ["JustRead", "支援", "中文。"]
        )
    }

    func testFocusIndexUsesFocusableCharacters() {
        XCTAssertEqual(RSVPEngine.focusIndex(in: ""), 0)
        XCTAssertEqual(RSVPEngine.focusIndex(in: "a"), 0)
        XCTAssertEqual(RSVPEngine.focusIndex(in: "read"), 1)
        XCTAssertEqual(RSVPEngine.focusIndex(in: "focused"), 2)
        XCTAssertEqual(RSVPEngine.focusIndex(in: "recognition"), 3)
        XCTAssertEqual(RSVPEngine.focusIndex(in: "\"read"), 2)
        XCTAssertEqual(
            RSVPEngine.splitForFocus("\"read"),
            RSVPEngine.FocusSplit(before: "\"r", focus: "e", after: "ad")
        )
    }

    func testDurationHandlesWPMClampsCJKPunctuationAndLongWords() {
        let base = RSVPEngine.duration(for: "read", wpm: 600, punctuationPause: false)

        XCTAssertEqual(base, 100)
        XCTAssertGreaterThan(RSVPEngine.duration(for: "read.", wpm: 600, punctuationPause: true), base)
        XCTAssertEqual(RSVPEngine.duration(for: "閱讀", wpm: 600, punctuationPause: false), 150)
        XCTAssertGreaterThan(RSVPEngine.duration(for: "讀。", wpm: 600, punctuationPause: true), 150)
        XCTAssertGreaterThan(RSVPEngine.duration(for: "internationalization", wpm: 600, punctuationPause: false), base)
        XCTAssertEqual(RSVPEngine.duration(for: "read", wpm: 0, punctuationPause: false), 133)
        XCTAssertEqual(RSVPEngine.duration(for: "read", wpm: 10_000, punctuationPause: false), 50)
    }

    func testEstimateMinutesUsesClampedWPM() {
        XCTAssertEqual(RSVPEngine.estimateMinutes(wordCount: 900, wpm: 900), 1)
        XCTAssertEqual(RSVPEngine.estimateMinutes(wordCount: 1200, wpm: 10_000), 1)
    }

    func testContextWindowStaysBoundedAndClamped() {
        XCTAssertEqual(
            RSVPEngine.contextWindow(tokenCount: 0, currentIndex: 0),
            RSVPEngine.ContextWindow(
                lowerBound: 0,
                upperBound: 0,
                hasLeadingOverflow: false,
                hasTrailingOverflow: false
            )
        )

        XCTAssertEqual(RSVPEngine.contextWindow(tokenCount: 10, currentIndex: 0).range, 0..<10)

        let middle = RSVPEngine.contextWindow(tokenCount: 1_000, currentIndex: 500)
        XCTAssertEqual(middle.lowerBound, 482)
        XCTAssertEqual(middle.upperBound, 537)
        XCTAssertEqual(middle.count, 55)
        XCTAssertTrue(middle.hasLeadingOverflow)
        XCTAssertTrue(middle.hasTrailingOverflow)

        let clampedStart = RSVPEngine.contextWindow(tokenCount: 100, currentIndex: -50)
        XCTAssertEqual(clampedStart.range, 0..<37)
        XCTAssertFalse(clampedStart.hasLeadingOverflow)
        XCTAssertTrue(clampedStart.hasTrailingOverflow)

        let clampedEnd = RSVPEngine.contextWindow(tokenCount: 100, currentIndex: 1_000)
        XCTAssertEqual(clampedEnd.range, 81..<100)
        XCTAssertTrue(clampedEnd.hasLeadingOverflow)
        XCTAssertFalse(clampedEnd.hasTrailingOverflow)

        let zeroRadius = RSVPEngine.contextWindow(tokenCount: 100, currentIndex: 50, before: -1, after: -1)
        XCTAssertEqual(zeroRadius.range, 50..<51)
    }

    func testSourceInputClassifierNormalizesSingleURLsOnly() {
        XCTAssertEqual(
            SourceInputClassifier.normalizedURLString(from: "partyon.xyz/@nullagent/116499715071759135"),
            "https://partyon.xyz/@nullagent/116499715071759135"
        )
        XCTAssertTrue(SourceInputClassifier.isLikelySingleURL("https://partyon.xyz/@nullagent/116499715071759135"))
        XCTAssertTrue(SourceInputClassifier.isLikelySingleURL("http://localhost:4173/article"))
        XCTAssertFalse(SourceInputClassifier.isLikelySingleURL("hello"))
        XCTAssertFalse(SourceInputClassifier.isLikelySingleURL("hello world"))
        XCTAssertFalse(SourceInputClassifier.isLikelySingleURL("ftp://example.com/article"))
    }

    func testArticleTextExtractorStripsChromeAndDecodesCommonEntities() {
        let html = """
        <html>
          <head>
            <title>Readable &amp; Fast</title>
            <style>.hidden { display: none; }</style>
          </head>
          <body>
            <nav>Share Related Subscribe</nav>
            <p>Hello&nbsp;reader.</p>
            <script>bad()</script>
            <p>Keep &ldquo;content&rdquo; &mdash; safely.</p>
          </body>
        </html>
        """

        XCTAssertEqual(ArticleTextExtractor.extractTitle(from: html), "Readable & Fast")
        XCTAssertEqual(
            ArticleTextExtractor.readableText(from: html),
            "Share Related Subscribe Hello reader. Keep \"content\" - safely."
        )
    }
}

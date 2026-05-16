import FastReadCore
import XCTest

final class RSVPEngineTests: XCTestCase {
    func testTokenizeHandlesWhitespaceEnglishAndNBSP() {
        XCTAssertEqual(RSVPEngine.tokenize(nil), [])
        XCTAssertEqual(RSVPEngine.tokenize("  Read\tfast.\nNow  "), ["Read", "fast.", "Now"])
        XCTAssertEqual(RSVPEngine.tokenize("Read\u{00a0}fast"), ["Read", "fast"])
    }

    func testTokenizeHandlesTraditionalSimplifiedAndMixedCJK() {
        // ChunkShaper rhythm rules merge orphan particles + content adverbs
        // (更 / 让) with their semantic neighbour. The bare ICU output here
        // was 5 singletons; the shaped output is 4 rhythmic chunks.
        XCTAssertEqual(
            RSVPEngine.tokenize("快速閱讀，眼睛更輕鬆。"),
            ["快速", "閱讀，", "眼睛", "更輕鬆。"]
        )
        XCTAssertEqual(
            RSVPEngine.tokenize("快速阅读让注意力更稳定。"),
            ["快速", "阅读让", "注意力", "更稳定。"]
        )
        XCTAssertEqual(
            RSVPEngine.tokenize("JustRead 支援中文。"),
            ["JustRead", "支援", "中文。"]
        )
    }

    func testTokenizePreservesContentAtChineseEnglishBoundaries() {
        // The hybrid pipeline still keeps every word at the script boundary
        // — the shaper additionally merges digit + 年 / 新 + … into compact
        // 2–3 char rhythm groups.
        XCTAssertEqual(
            RSVPEngine.tokenize("Apple在2025年發表新MacBook Pro"),
            ["Apple", "在", "2025年", "發表新", "MacBook", "Pro"]
        )
        XCTAssertEqual(
            RSVPEngine.tokenize("我用VS Code寫iOS app"),
            ["我用", "VS", "Code", "寫", "iOS", "app"]
        )
    }

    func testTokenizeKeepsCompoundLatinUnitsWhole() {
        // Latin runs split only on whitespace so 25°C, 12.5%, RFC-7231,
        // HTTP/1.1 etc. survive intact.
        XCTAssertEqual(
            RSVPEngine.tokenize("今天氣溫 25°C 大約華氏 77°F"),
            ["今天", "氣溫", "25°C", "大約", "華氏", "77°F"]
        )
        XCTAssertEqual(
            RSVPEngine.tokenize("可參考 RFC-7231 (HTTP/1.1)"),
            ["可參考", "RFC-7231", "(HTTP/1.1)"]
        )
        XCTAssertEqual(
            RSVPEngine.tokenize("Dr. Smith 在 NTU 教 AI 課程"),
            ["Dr.", "Smith", "在", "NTU", "教", "AI", "課程"]
        )
    }

    func testTokenizeUserDictionaryMergesProperNouns() {
        // The shaper now auto-merges 黃士旗 even without a dictionary, via
        // the 4-char Han-run + peel-forward rule. Where the dictionary
        // still matters is when ICU produces *adjacent multi-char* chunks
        // that ought to fuse (王 + 老師 → 王老師) — the shaper alone has
        // no way to know that the 王 belongs to the next word.
        XCTAssertEqual(
            RSVPEngine.tokenize("黃士旗去吃飯"),
            ["黃士旗", "去吃飯"]
        )
        XCTAssertEqual(
            RSVPEngine.tokenize("張三王老師很嚴格"),
            ["張三王", "老師", "很嚴格"]
        )
        XCTAssertEqual(
            RSVPEngine.tokenize("張三王老師很嚴格", userDictionary: ["王老師"]),
            ["張三", "王老師", "很嚴格"]
        )
    }

    func testTokenizeUserDictionaryPrefersLongestMatch() {
        XCTAssertEqual(
            RSVPEngine.tokenize("台灣大學資訊系很棒", userDictionary: ["台灣", "台灣大學", "資訊系"]),
            ["台灣大學", "資訊系", "很", "棒"]
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
        XCTAssertEqual(RSVPEngine.duration(for: "read", wpm: 10_000, punctuationPause: false), 40)
    }

    func testEstimateMinutesUsesClampedWPM() {
        XCTAssertEqual(RSVPEngine.estimateMinutes(wordCount: 900, wpm: 900), 1)
        XCTAssertEqual(RSVPEngine.estimateMinutes(wordCount: 1500, wpm: 10_000), 1)
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

import Dispatch
import FastReadCore
import Foundation

struct Measurement {
    let name: String
    let millis: Double
    let budgetMillis: Double
}

var measurements: [Measurement] = []

func fail(_ message: String) -> Never {
    fputs("FastReadPerformanceVerifier failed: \(message)\n", stderr)
    exit(1)
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fail(message)
    }
}

func budget(_ baseMillis: Double) -> Double {
    let raw = ProcessInfo.processInfo.environment["FASTREAD_PERF_BUDGET_MULTIPLIER"]
    let multiplier = raw.flatMap(Double.init) ?? 1
    return baseMillis * max(multiplier, 1)
}

@discardableResult
@MainActor
func measure<T>(_ name: String, budget baseBudgetMillis: Double, _ operation: () throws -> T) rethrows -> T {
    let budgetMillis = budget(baseBudgetMillis)
    let start = DispatchTime.now().uptimeNanoseconds
    let result = try operation()
    let elapsedMillis = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
    measurements.append(Measurement(name: name, millis: elapsedMillis, budgetMillis: budgetMillis))
    if elapsedMillis > budgetMillis {
        fail("\(name) took \(String(format: "%.2f", elapsedMillis))ms; budget is \(String(format: "%.2f", budgetMillis))ms")
    }
    return result
}

func makeLongArticle(wordCount: Int) -> String {
    (0..<wordCount)
        .map { index in
            switch index % 11 {
            case 0: "performance,"
            case 5: "reader."
            default: "word\(index)"
            }
        }
        .joined(separator: " ")
}

func makeHTML(paragraphs: Int) -> String {
    let body = (0..<paragraphs)
        .map { "<p>Paragraph&nbsp;\($0) keeps readable content &ldquo;fast&rdquo; while navigation chrome stays out.</p>" }
        .joined(separator: "\n")
    return """
    <html>
      <head>
        <title>Performance fixture</title>
        <style>.hidden { display: none; }</style>
      </head>
      <body>
        <nav>Share Related Subscribe</nav>
        \(body)
        <script>window.bad = true;</script>
      </body>
    </html>
    """
}

let longArticle = makeLongArticle(wordCount: 50_000)
_ = RSVPEngine.tokenize("warm up")

let tokens = measure("tokenize 50k words", budget: 250) {
    RSVPEngine.tokenize(longArticle)
}
expect(tokens.count == 50_000, "tokenizer should preserve the long fixture word count")

let defaultWindow = RSVPEngine.contextWindow(tokenCount: tokens.count, currentIndex: 25_000)
expect(defaultWindow.count <= 55, "reader context must stay bounded instead of exposing the full article")
expect(defaultWindow.hasLeadingOverflow && defaultWindow.hasTrailingOverflow, "middle reader context should show both overflow markers")

measure("compute 20k context windows", budget: 35) {
    var total = 0
    for index in 0..<20_000 {
        total += RSVPEngine.contextWindow(tokenCount: tokens.count, currentIndex: index).count
    }
    expect(total > 0, "context windows should be non-empty for long articles")
}

let sectionedDocument = Document(
    title: "TOC performance fixture",
    author: "JustRead",
    sections: (0..<1_200).map { index in
        Section(
            id: "section-\(index)",
            title: "Chapter \(index)",
            kind: .chapter,
            text: "Chapter \(index) " + makeLongArticle(wordCount: 60)
        )
    }
)

let tocBoundaries = measure("build 1200 section boundaries", budget: 180) {
    Document.sectionBoundaries(sectionedDocument)
}
expect(tocBoundaries.count == 1_200, "TOC boundary count should match document sections")
expect(tocBoundaries.last?.tokenEnd == RSVPEngine.tokenize(Document.flattenText(sectionedDocument)).count, "TOC token boundaries should match flattened document tokens")

let frontMatter = measure("detect front matter with cached boundaries", budget: 20) {
    Document.detectFrontMatter(sectionedDocument, boundaries: tocBoundaries)
}
expect(frontMatter.totalTokens == tocBoundaries.last?.tokenEnd, "front matter detection should reuse the supplied boundaries")

measure("simulate 20k cached playback ticks", budget: 250) {
    var index = 0
    var totalDuration = 0
    for _ in 0..<20_000 {
        totalDuration += RSVPEngine.duration(for: tokens[index], wpm: 540)
        index = index == tokens.count - 1 ? 0 : index + 1
    }
    expect(totalDuration > 0, "playback tick simulation should produce durations")
}

measure("classify 20k pasted URL inputs", budget: 200) {
    var accepted = 0
    for index in 0..<20_000 {
        if SourceInputClassifier.isLikelySingleURL("https://partyon.xyz/@nullagent/\(116_499_715_071_759_135 + index)") {
            accepted += 1
        }
    }
    expect(accepted == 20_000, "URL classifier should accept every generated URL")
}

let html = makeHTML(paragraphs: 8_000)
let extracted = measure("extract readable text from large HTML", budget: 450) {
    ArticleTextExtractor.readableText(from: html)
}
expect(extracted.contains("Paragraph 7999"), "HTML extractor should preserve late body text")
expect(!extracted.contains("window.bad"), "HTML extractor should remove script content")

measure("apply 20k WPM slider updates", budget: 25) {
    var value = 550.0
    for index in 0..<20_000 {
        value = RSVPEngine.clamp(300 + Double(index % 700) + 0.42, min: 300, max: 1_000)
    }
    expect(value > 300, "WPM updates should preserve continuous values")
}

print("FastReadPerformanceVerifier passed")
for item in measurements {
    print("- \(item.name): \(String(format: "%.2f", item.millis))ms / \(String(format: "%.2f", item.budgetMillis))ms")
}

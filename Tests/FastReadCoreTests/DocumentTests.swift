import XCTest
@testable import FastReadCore

final class DocumentTests: XCTestCase {
    func testEmptyDocumentFlattenAndBoundaries() {
        let doc = Document()
        XCTAssertEqual(Document.flattenText(doc), "")
        XCTAssertEqual(Document.sectionBoundaries(doc), [])
    }

    func testBodyOnlyDocument() {
        let doc = Document(
            title: "Body Only",
            sourceKind: "text",
            sections: [
                Section(id: "body", kind: .body, text: "hello world from a single section"),
            ]
        )
        XCTAssertEqual(Document.flattenText(doc), "hello world from a single section")
        let boundaries = Document.sectionBoundaries(doc)
        XCTAssertEqual(boundaries.count, 1)
        XCTAssertEqual(boundaries[0].sectionId, "body")
        XCTAssertEqual(boundaries[0].tokenStart, 0)
        XCTAssertEqual(boundaries[0].tokenEnd, 6)
    }

    func testMultiChapterCJKBoundariesMatchTokenize() {
        let sections = [
            Section(id: "ch-1", title: "Chapter One", kind: .chapter, text: "The quick brown fox."),
            Section(id: "ch-2", title: "第二章", kind: .chapter, text: "快速的棕色狐狸跳過懶狗。"),
            Section(id: "p-1", title: "Appendix", kind: .page, text: "A short appendix page."),
        ]
        let doc = Document(title: "Multi", sections: sections)

        let flat = Document.flattenText(doc)
        let expectedFlat = sections.map { $0.text }.joined(separator: "\n\n")
        XCTAssertEqual(flat, expectedFlat)

        let totalTokens = RSVPEngine.tokenize(flat).count
        let boundaries = Document.sectionBoundaries(doc)
        XCTAssertEqual(boundaries.count, sections.count)
        XCTAssertEqual(boundaries.first?.tokenStart, 0)
        XCTAssertEqual(boundaries.last?.tokenEnd, totalTokens)
        for i in 1..<boundaries.count {
            XCTAssertEqual(boundaries[i].tokenStart, boundaries[i - 1].tokenEnd)
        }
        for (i, section) in sections.enumerated() {
            XCTAssertEqual(boundaries[i].sectionId, section.id)
            XCTAssertGreaterThan(boundaries[i].tokenEnd, boundaries[i].tokenStart)
        }
    }

    func testCodableRoundTrip() throws {
        let doc = Document(
            title: "Round Trip",
            author: "Ada",
            sourceUrl: "https://example.com",
            sourceKind: "html",
            sections: [
                Section(id: "s1", title: "A", kind: .chapter, text: "alpha beta"),
                Section(id: "s2", title: "B", kind: .body, text: "gamma delta epsilon"),
            ]
        )
        let data = try JSONEncoder().encode(doc)
        let decoded = try JSONDecoder().decode(Document.self, from: data)
        XCTAssertEqual(decoded, doc)
    }

    func testDocumentSampleFixtureMatchesJSProducedShape() throws {
        guard let url = Bundle.module.url(
            forResource: "document-sample",
            withExtension: "json",
            subdirectory: "Fixtures"
        ) else {
            XCTFail("document-sample.json fixture not found in test bundle")
            return
        }
        let data = try Data(contentsOf: url)
        let decoded = try JSONDecoder().decode(Document.self, from: data)

        let expected = Document(
            title: "Sample Document 範例",
            author: "Ada Lovelace",
            sourceUrl: "https://example.com/sample",
            sourceKind: "epub",
            sections: [
                Section(id: "ch-1", title: "Chapter One", kind: .chapter, text: "The quick brown fox jumps over the lazy dog."),
                Section(id: "ch-2", title: "第二章", kind: .chapter, text: "快速的棕色狐狸跳過懶狗。"),
                Section(id: "p-1", title: "Appendix", kind: .page, text: "A short appendix page."),
            ]
        )
        XCTAssertEqual(decoded, expected)

        let reEncoded = try JSONEncoder().encode(decoded)
        let reDecoded = try JSONDecoder().decode(Document.self, from: reEncoded)
        XCTAssertEqual(reDecoded, decoded)
    }

    private func chapterText(_ words: Int) -> String {
        Array(repeating: "word", count: words).joined(separator: " ")
    }

    func testDetectFrontMatterEmptyDocument() {
        let result = Document.detectFrontMatter(Document())
        XCTAssertNil(result.firstChapterSectionIndex)
        XCTAssertEqual(result.firstChapterTokenIndex, 0)
        XCTAssertEqual(result.frontMatterSectionIds, [])
        XCTAssertEqual(result.totalTokens, 0)
        XCTAssertFalse(result.hasSkippableFrontMatter)
    }

    func testDetectFrontMatterChineseTitlesAreClassified() {
        let doc = Document(
            sourceKind: "epub",
            sections: [
                Section(id: "cov", title: "封面", kind: .chapter, text: "封面"),
                Section(id: "ver", title: "版權頁", kind: .chapter, text: "版權所有 翻印必究"),
                Section(id: "tof", title: "目錄", kind: .chapter, text: "第一章 第二章"),
                Section(id: "rec", title: "推薦序 · 閱讀是一扇門", kind: .chapter, text: chapterText(120)),
                Section(id: "ch1", title: "樂園", kind: .chapter, text: chapterText(2500)),
                Section(id: "ch2", title: "失樂園", kind: .chapter, text: chapterText(2500)),
            ]
        )
        let result = Document.detectFrontMatter(doc)
        XCTAssertEqual(result.firstChapterSectionIndex, 4)
        XCTAssertEqual(result.frontMatterSectionIds, ["cov", "ver", "tof", "rec"])
        XCTAssertGreaterThan(result.firstChapterTokenIndex, 0)
        XCTAssertTrue(result.hasSkippableFrontMatter)
    }

    func testDetectFrontMatterEnglishTitlesAreClassified() {
        let doc = Document(
            sourceKind: "epub",
            sections: [
                Section(id: "cover", title: "Cover", kind: .chapter, text: ""),
                Section(id: "title", title: "Title Page", kind: .chapter, text: "Pride and Prejudice"),
                Section(id: "copy", title: "Copyright", kind: .chapter, text: "Public domain."),
                Section(id: "fore", title: "Foreword", kind: .chapter, text: chapterText(50)),
                Section(id: "ch1", title: "Chapter 1", kind: .chapter, text: chapterText(2000)),
            ]
        )
        let result = Document.detectFrontMatter(doc)
        XCTAssertEqual(result.firstChapterSectionIndex, 4)
        XCTAssertEqual(result.frontMatterSectionIds, ["cover", "title", "copy", "fore"])
    }

    func testDetectFrontMatterFallsBackToShortSectionHeuristic() {
        let doc = Document(
            sourceKind: "epub",
            sections: [
                Section(id: "s0", title: "Section 0", kind: .chapter, text: chapterText(40)),
                Section(id: "s1", title: "Section 1", kind: .chapter, text: chapterText(60)),
                Section(id: "s2", title: "Section 2", kind: .chapter, text: chapterText(3000)),
                Section(id: "s3", title: "Section 3", kind: .chapter, text: chapterText(3000)),
            ]
        )
        let result = Document.detectFrontMatter(doc)
        XCTAssertEqual(result.firstChapterSectionIndex, 2)
        XCTAssertEqual(result.frontMatterSectionIds, ["s0", "s1"])
    }

    func testDetectFrontMatterNoSkipWhenFirstSectionIsAChapter() {
        let doc = Document(
            sourceKind: "epub",
            sections: [
                Section(id: "ch1", title: "Chapter 1", kind: .chapter, text: chapterText(3000)),
                Section(id: "ch2", title: "Chapter 2", kind: .chapter, text: chapterText(3000)),
            ]
        )
        let result = Document.detectFrontMatter(doc)
        XCTAssertEqual(result.firstChapterSectionIndex, 0)
        XCTAssertEqual(result.frontMatterSectionIds, [])
        XCTAssertEqual(result.firstChapterTokenIndex, 0)
        XCTAssertFalse(result.hasSkippableFrontMatter)
    }

    func testDetectFrontMatterDoesNotMisclassifyChapterTitleStartingWith前() {
        let doc = Document(
            sourceKind: "epub",
            sections: [
                Section(id: "fmw", title: "推薦序", kind: .chapter, text: chapterText(50)),
                Section(id: "ch1", title: "前進的勇氣", kind: .chapter, text: chapterText(2500)),
            ]
        )
        let result = Document.detectFrontMatter(doc)
        XCTAssertEqual(result.firstChapterSectionIndex, 1)
        XCTAssertEqual(result.frontMatterSectionIds, ["fmw"])
    }
}

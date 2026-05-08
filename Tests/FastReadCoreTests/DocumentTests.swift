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
}

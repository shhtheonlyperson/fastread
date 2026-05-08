import Foundation
import XCTest
@testable import FastReadCore

final class EpubImporterTests: XCTestCase {

    private func loadFixture(_ name: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: "epub", subdirectory: "Fixtures/epub") else {
            XCTFail("Missing fixture: \(name).epub")
            return Data()
        }
        return try Data(contentsOf: url)
    }

    func testPrideAndPrejudiceEpub3WithNav() throws {
        let data = try loadFixture("pride-and-prejudice")
        let importer = EpubImporter()
        XCTAssertTrue(importer.canHandle(data: data))
        let doc = try importer.import(data: data)

        XCTAssertEqual(doc.title, "Pride and Prejudice")
        XCTAssertEqual(doc.author, "Jane Austen")
        XCTAssertEqual(doc.sourceKind, "epub")
        XCTAssertEqual(doc.sections.count, 2)
        XCTAssertEqual(doc.sections.map(\.title), ["Chapter 1", "Chapter 2"])
        XCTAssertTrue(doc.sections.allSatisfy { $0.kind == .chapter })

        let flat = Document.flattenText(doc)
        XCTAssertTrue(flat.contains("It is a truth universally acknowledged"))
        XCTAssertTrue(flat.contains("Mr. Bennet"))

        // JS baseline (US-014): 44 tokens, +/-2% (1 token).
        let tokenCount = RSVPEngine.tokenize(flat).count
        let jsBaseline = 44
        let tolerance = max(1, Int((Double(jsBaseline) * 0.02).rounded()))
        XCTAssertLessThanOrEqual(
            abs(tokenCount - jsBaseline), tolerance,
            "Pride token count \(tokenCount) outside +/-\(tolerance) of JS baseline \(jsBaseline)"
        )
    }

    func testTaoTeChingEpub2WithNcx() throws {
        let data = try loadFixture("tao-te-ching")
        let importer = EpubImporter()
        XCTAssertTrue(importer.canHandle(data: data))
        let doc = try importer.import(data: data)

        XCTAssertEqual(doc.title, "道德經")
        XCTAssertEqual(doc.author, "老子")
        XCTAssertEqual(doc.sourceKind, "epub")
        XCTAssertEqual(doc.sections.count, 3)
        XCTAssertEqual(doc.sections.map(\.title), ["第一章", "第二章", "第三章"])
        XCTAssertTrue(doc.sections.allSatisfy { $0.kind == .chapter })

        let flat = Document.flattenText(doc)
        XCTAssertTrue(flat.contains("道可道，非常道。"))

        // JS baseline (US-014): 41 tokens, +/-2% (1 token).
        let tokenCount = RSVPEngine.tokenize(flat).count
        let jsBaseline = 41
        let tolerance = max(1, Int((Double(jsBaseline) * 0.02).rounded()))
        XCTAssertLessThanOrEqual(
            abs(tokenCount - jsBaseline), tolerance,
            "Tao token count \(tokenCount) outside +/-\(tolerance) of JS baseline \(jsBaseline)"
        )
    }

    func testCanHandleRejectsNonZip() {
        let importer = EpubImporter()
        XCTAssertFalse(importer.canHandle(data: Data("not a zip".utf8)))
        XCTAssertTrue(importer.canHandle(filename: "Book.epub"))
        XCTAssertFalse(importer.canHandle(filename: "Book.pdf"))
    }
}

import Foundation
import XCTest
@testable import FastReadCore

final class EpubRegistryFlowTests: XCTestCase {

    private func loadFixture(_ name: String) throws -> Data {
        guard let url = Bundle.module.url(
            forResource: name, withExtension: "epub", subdirectory: "Fixtures/epub"
        ) else {
            XCTFail("Missing fixture: \(name).epub")
            return Data()
        }
        return try Data(contentsOf: url)
    }

    func testRegistryImportEpubProducesChapterDocument() throws {
        let data = try loadFixture("pride-and-prejudice")
        let doc = try ImporterRegistry.shared.importEpub(data: data)

        XCTAssertEqual(doc.sourceKind, "epub")
        XCTAssertGreaterThan(doc.sections.count, 0)
        XCTAssertTrue(doc.sections.allSatisfy { $0.kind == .chapter })
        XCTAssertGreaterThan(RSVPEngine.tokenize(Document.flattenText(doc)).count, 0)
    }

    func testRegistryImportEpubRejectsNonEpubData() {
        let bogus = Data("totally not a zip archive".utf8)
        XCTAssertThrowsError(try ImporterRegistry.shared.importEpub(data: bogus))
    }

    func testRegistryImportEpubOptionsOverrideMetadata() throws {
        let data = try loadFixture("pride-and-prejudice")
        let doc = try ImporterRegistry.shared.importEpub(
            data: data,
            options: ImportOptions(sourceUrl: "file://book.epub", title: "Custom", author: "Reader")
        )
        XCTAssertEqual(doc.title, "Custom")
        XCTAssertEqual(doc.author, "Reader")
        XCTAssertEqual(doc.sourceUrl, "file://book.epub")
    }
}

import XCTest
import ZIPFoundation
@testable import FastReadCore

// Negative-path coverage for EpubImporter. Each test feeds a known-bad
// blob into the importer and asserts a typed error rather than a crash
// or silently empty Document.
final class EpubErrorPathsTests: XCTestCase {
    private let importer = EpubImporter()

    func testNonZipBlobThrows() {
        let bytes: [UInt8] = [0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08]
        let data = Data(bytes)
        XCTAssertThrowsError(try importer.import(data: data, options: ImportOptions())) { error in
            XCTAssertTrue(
                "\(error)".contains("epub") || "\(error)".contains("zip") || "\(error)".contains("invalidInput") || "\(error)".contains("invalid"),
                "expected an importer error for a non-zip blob, got \(error)"
            )
        }
    }

    func testEmptyDataThrows() {
        XCTAssertThrowsError(try importer.import(data: Data(), options: ImportOptions()))
    }

    func testZipWithoutContainerXmlThrows() throws {
        // A valid zip file that is missing the META-INF/container.xml that
        // EPUB requires. Importer should refuse it instead of returning a
        // zero-section Document.
        let archive = try Archive(accessMode: .create)
        let dummy = "not an EPUB".data(using: .utf8)!
        try archive.addEntry(with: "hello.txt", type: .file, uncompressedSize: Int64(dummy.count)) { position, size in
            dummy.subdata(in: Int(position)..<Int(position) + size)
        }
        guard let zipData = archive.data else {
            XCTFail("Failed to materialize zip data")
            return
        }
        XCTAssertThrowsError(try importer.import(data: zipData, options: ImportOptions())) { error in
            XCTAssertTrue(
                "\(error)".lowercased().contains("container") || "\(error)".lowercased().contains("epub") || "\(error)".lowercased().contains("opf") || "\(error)".contains("invalidInput"),
                "expected a container/OPF/epub error, got \(error)"
            )
        }
    }

    func testZipWithContainerButNoOpfManifestThrows() throws {
        // META-INF/container.xml present but rootfile path points to an
        // OPF that is not in the archive.
        let containerXml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
          <rootfiles>
            <rootfile full-path="OEBPS/missing.opf" media-type="application/oebps-package+xml"/>
          </rootfiles>
        </container>
        """.data(using: .utf8)!

        let archive = try Archive(accessMode: .create)
        try archive.addEntry(with: "META-INF/container.xml", type: .file, uncompressedSize: Int64(containerXml.count)) { position, size in
            containerXml.subdata(in: Int(position)..<Int(position) + size)
        }
        guard let zipData = archive.data else {
            XCTFail("Failed to materialize zip data")
            return
        }
        XCTAssertThrowsError(try importer.import(data: zipData, options: ImportOptions()))
    }

    func testEpubWithEmptySpineYieldsEmptyOrThrows() throws {
        // Valid container + OPF, but the spine is empty so there are no
        // chapter items to render. Either an explicit error or an empty-
        // Document result with zero readable text would be a reasonable
        // outcome; what we want is "does not crash".
        let containerXml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
          <rootfiles>
            <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
          </rootfiles>
        </container>
        """.data(using: .utf8)!

        let opf = """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="bookid">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:identifier id="bookid">urn:fixture:empty-spine</dc:identifier>
            <dc:title>Empty Spine Book</dc:title>
            <dc:language>en</dc:language>
          </metadata>
          <manifest/>
          <spine/>
        </package>
        """.data(using: .utf8)!

        let archive = try Archive(accessMode: .create)
        try archive.addEntry(with: "META-INF/container.xml", type: .file, uncompressedSize: Int64(containerXml.count)) { position, size in
            containerXml.subdata(in: Int(position)..<Int(position) + size)
        }
        try archive.addEntry(with: "OEBPS/content.opf", type: .file, uncompressedSize: Int64(opf.count)) { position, size in
            opf.subdata(in: Int(position)..<Int(position) + size)
        }
        guard let zipData = archive.data else {
            XCTFail("Failed to materialize zip data")
            return
        }
        // Either throws or returns a near-empty Document — both are
        // acceptable, but the importer must NOT crash.
        let result = Result { try importer.import(data: zipData, options: ImportOptions()) }
        switch result {
        case .success(let doc):
            XCTAssertEqual(doc.sourceKind, "epub")
            XCTAssertEqual(doc.title, "Empty Spine Book")
            XCTAssertTrue(
                doc.sections.isEmpty || RSVPEngine.countReadingUnits(Document.flattenText(doc)) == 0,
                "spine-less EPUB should yield no readable text, got \(RSVPEngine.countReadingUnits(Document.flattenText(doc))) units"
            )
        case .failure:
            // Acceptable: importer rejected an EPUB with no spine items.
            break
        }
    }
}

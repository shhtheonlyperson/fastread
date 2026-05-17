import XCTest
@testable import FastReadCore

// Walks a directory of real EPUBs and asserts every file imports cleanly.
//
// Gated by FASTREAD_RUN_EPUB_CORPUS=1 — keeps the default `swift test` run
// fast and CI-safe. Override with FASTREAD_EPUB_CORPUS_DIR.
// Cap iteration with FASTREAD_EPUB_CORPUS_LIMIT.
//
// For each *.epub:
//   1. EpubImporter().import succeeds
//   2. Document has at least one section with non-empty text
//   3. flattenText + tokenize produces > 50 reading units
//
// Failures are aggregated into a single XCTFail so a noisy file doesn't
// hide the others.
final class EpubCorpusTests: XCTestCase {
    private static let env = ProcessInfo.processInfo.environment
    private static let enabled = env["FASTREAD_RUN_EPUB_CORPUS"] == "1"
    // Default location is the iCloud Drive "books" folder. The test
    // runner's process must have Files-and-Folders access for iCloud
    // Drive (System Settings → Privacy & Security → Files and Folders);
    // without it the path is unreadable and the test skips with a hint.
    private static let corpusDir: String = {
        if let override = env["FASTREAD_EPUB_CORPUS_DIR"], !override.isEmpty {
            return (override as NSString).expandingTildeInPath
        }
        return (NSHomeDirectory() as NSString)
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/books")
    }()
    private static let limit: Int = {
        if let raw = env["FASTREAD_EPUB_CORPUS_LIMIT"], let n = Int(raw), n > 0 {
            return n
        }
        return Int.max
    }()

    private struct CorpusFailure {
        let name: String
        let reason: String
    }

    func testEveryEpubImportsAsNonEmptyDocument() throws {
        try XCTSkipUnless(Self.enabled, "Set FASTREAD_RUN_EPUB_CORPUS=1 to run.")
        let fileManager = FileManager.default
        let dirURL = URL(fileURLWithPath: Self.corpusDir)

        let allFiles: [URL]
        do {
            allFiles = try fileManager.contentsOfDirectory(at: dirURL, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension.lowercased() == "epub" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
        } catch let error as NSError {
            // POSIX EPERM (1) under iCloud Drive means the test runner is
            // missing Files-and-Folders TCC access. Skip rather than fail.
            let posixCode = (error.userInfo[NSUnderlyingErrorKey] as? NSError)?.code ?? error.code
            let permissionDenied = error.code == NSFileReadNoPermissionError || posixCode == 1 || error.code == 257
            try XCTSkipIf(
                permissionDenied,
                """
                Corpus directory unreadable at \(Self.corpusDir):
                  \(error.localizedDescription)
                • iCloud Drive paths require Files-and-Folders access for the test runner — System Settings → Privacy & Security → Files and Folders.
                • Override the default with FASTREAD_EPUB_CORPUS_DIR=/absolute/path/to/dir.
                """
            )
            try XCTSkipIf(
                error.code == NSFileReadNoSuchFileError || error.code == 260,
                "Corpus directory not found at \(Self.corpusDir). Override with FASTREAD_EPUB_CORPUS_DIR."
            )
            throw error
        }
        XCTAssertGreaterThan(allFiles.count, 0, "expected at least one .epub under \(Self.corpusDir)")

        let files = Array(allFiles.prefix(Self.limit))
        var failures: [CorpusFailure] = []
        let importer = EpubImporter()

        for url in files {
            let name = url.lastPathComponent
            do {
                let data = try Data(contentsOf: url)
                let doc = try importer.import(data: data, options: ImportOptions())
                if doc.sourceKind != "epub" {
                    failures.append(.init(name: name, reason: "sourceKind=\(doc.sourceKind)"))
                    continue
                }
                if doc.sections.isEmpty {
                    failures.append(.init(name: name, reason: "no sections"))
                    continue
                }
                let nonEmpty = doc.sections.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                if nonEmpty.isEmpty {
                    failures.append(.init(name: name, reason: "all sections empty"))
                    continue
                }
                let units = RSVPEngine.countReadingUnits(Document.flattenText(doc))
                if units < 50 {
                    failures.append(.init(name: name, reason: "only \(units) reading units"))
                    continue
                }
            } catch {
                failures.append(.init(name: name, reason: "\(error)"))
            }
        }

        if !failures.isEmpty {
            let detail = failures.map { "  - \($0.name): \($0.reason)" }.joined(separator: "\n")
            XCTFail("\(failures.count)/\(files.count) EPUB(s) failed import:\n\(detail)")
        } else {
            print("epub-corpus: \(files.count) EPUB(s) under \(Self.corpusDir) all imported cleanly.")
        }
    }
}

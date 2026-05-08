import FastReadCore
import XCTest

final class ParityTests: XCTestCase {
    private struct FocusSplitFixture: Decodable, Equatable {
        let before: String
        let focus: String
        let after: String
    }

    private struct Entry: Decodable {
        let id: String
        let description: String
        let input: String
        let tokens: [String]
        let focusSplits: [FocusSplitFixture]
        let durations: [Int]
        let wpm: Double
        let punctuationPause: Bool
    }

    private struct Corpus: Decodable {
        let generatedBy: String
        let source: String
        let entries: [Entry]
    }

    func testParityCorpusMatchesRSVPEngine() throws {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "parity-corpus", withExtension: "json", subdirectory: "Fixtures"),
            "parity-corpus.json must be bundled with the test target"
        )
        let data = try Data(contentsOf: url)
        let corpus = try JSONDecoder().decode(Corpus.self, from: data)
        XCTAssertGreaterThanOrEqual(corpus.entries.count, 12, "Parity corpus should have at least 12 entries")

        for entry in corpus.entries {
            let tokens = RSVPEngine.tokenize(entry.input)
            XCTAssertEqual(tokens, entry.tokens, "tokens mismatch for \(entry.id)")

            let splits = tokens.map { token -> FocusSplitFixture in
                let s = RSVPEngine.splitForFocus(token)
                return FocusSplitFixture(before: s.before, focus: s.focus, after: s.after)
            }
            XCTAssertEqual(splits, entry.focusSplits, "focusSplits mismatch for \(entry.id)")

            let durations = tokens.map {
                RSVPEngine.duration(for: $0, wpm: entry.wpm, punctuationPause: entry.punctuationPause)
            }
            XCTAssertEqual(durations, entry.durations, "durations mismatch for \(entry.id)")
        }
    }
}

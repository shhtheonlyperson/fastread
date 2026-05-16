import FastReadCore
import XCTest

final class PlaybackTimingTests: XCTestCase {
    func testDurationDelegatesWPMAndPunctuationRules() {
        let plain = PlaybackTiming(wpm: 600, punctuationPause: false)
        let paused = PlaybackTiming(wpm: 600, punctuationPause: true)

        XCTAssertEqual(plain.durationMilliseconds(for: "read"), 100)
        XCTAssertGreaterThan(paused.durationMilliseconds(for: "read."), plain.durationMilliseconds(for: "read"))
    }

    func testNextIndexStopsAtEndAndClampsNegativeInput() {
        XCTAssertEqual(PlaybackTiming.nextIndex(after: -4, tokenCount: 5), 0)
        XCTAssertEqual(PlaybackTiming.nextIndex(after: 0, tokenCount: 5), 1)
        XCTAssertNil(PlaybackTiming.nextIndex(after: 4, tokenCount: 5))
        XCTAssertNil(PlaybackTiming.nextIndex(after: 0, tokenCount: 0))
    }
}

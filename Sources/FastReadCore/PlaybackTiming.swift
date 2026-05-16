import Foundation

public struct PlaybackTiming: Equatable, Sendable {
    public var wpm: Double
    public var punctuationPause: Bool

    public init(wpm: Double, punctuationPause: Bool) {
        self.wpm = wpm
        self.punctuationPause = punctuationPause
    }

    public func durationMilliseconds(for token: String) -> Int {
        RSVPEngine.duration(for: token, wpm: wpm, punctuationPause: punctuationPause)
    }

    public static func nextIndex(after index: Int, tokenCount: Int) -> Int? {
        guard tokenCount > 0, index < tokenCount - 1 else { return nil }
        return RSVPEngine.clamp(index + 1, min: 0, max: tokenCount - 1)
    }
}

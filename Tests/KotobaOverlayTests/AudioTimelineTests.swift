import XCTest
import CoreMedia
@testable import KotobaOverlay
final class AudioTimelineTests: XCTestCase {
    func testResampledPacketOverlapIsClampedToPriorEnd() throws {
        var clock = AudioTimeline()
        let first = try XCTUnwrap(clock.startTime(captureTime: CMTime(value: 480000, timescale: 48000), outputFrames: 342, sampleRate: 16000))
        XCTAssertEqual(first, .zero)
        let end = clock.nextEnd
        let second = try XCTUnwrap(clock.startTime(captureTime: CMTime(value: 481024, timescale: 48000), outputFrames: 341, sampleRate: 16000))
        XCTAssertEqual(second, end) // Old packet time was 1/24000 second too early.
    }
    func testBackwardsTimestampCannotOverlapAndRealPauseIsPreserved() throws {
        var clock = AudioTimeline()
        _ = clock.startTime(captureTime: CMTime(seconds: 100, preferredTimescale: 48000), outputFrames: 480, sampleRate: 48000)
        let second = try XCTUnwrap(clock.startTime(captureTime: CMTime(seconds: 99.999, preferredTimescale: 48000), outputFrames: 480, sampleRate: 48000))
        XCTAssertEqual(second.seconds, 0.01, accuracy: 0.000001)
        let resumed = try XCTUnwrap(clock.startTime(captureTime: CMTime(seconds: 110, preferredTimescale: 48000), outputFrames: 480, sampleRate: 48000))
        XCTAssertEqual(resumed.seconds, 10, accuracy: 0.000001)
    }
    func testTenMinutesOfConversionNeverOverlap() throws {
        var clock = AudioTimeline()
        var previousEnd = CMTime.zero
        for i in 0..<30000 {
            let frames = i % 3 == 0 ? 342 : 341
            let start = try XCTUnwrap(clock.startTime(captureTime: CMTime(value: Int64(i * 1024), timescale: 48000), outputFrames: frames, sampleRate: 16000))
            XCTAssertGreaterThanOrEqual(CMTimeCompare(start, previousEnd), 0)
            previousEnd = clock.nextEnd
        }
        XCTAssertEqual(previousEnd.seconds, 640, accuracy: 0.001)
    }
    func testRateChangeAndInvalidInput() throws {
        var clock = AudioTimeline()
        XCTAssertNil(clock.startTime(captureTime: .invalid, outputFrames: 1, sampleRate: 16000))
        XCTAssertNil(clock.startTime(captureTime: .zero, outputFrames: 0, sampleRate: 16000))
        _ = clock.startTime(captureTime: .zero, outputFrames: 341, sampleRate: 16000)
        let oldEnd = clock.nextEnd
        let next = try XCTUnwrap(clock.startTime(captureTime: .zero, outputFrames: 441, sampleRate: 44100))
        XCTAssertGreaterThanOrEqual(CMTimeCompare(next, oldEnd), 0)
    }
}

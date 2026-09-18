import XCTest
@testable import KotobaOverlay

final class SubtitleTimelineTests: XCTestCase {
    func testFirstTimestampShiftsEveryCuePreservingDurationsAndGaps() throws {
        let cues = [TimedSubtitle(start: 5, end: 7.5, original: "こんにちは", translated: "你好"), TimedSubtitle(start: 9, end: 11, original: "ありがとう", translated: "謝謝")]
        let srt = try SubtitleTimeline.srt(cues, firstStart: SubtitleTimeline.parse("00:01:20,000"), mode: .both)
        XCTAssertTrue(srt.contains("00:01:20,000 --> 00:01:22,500"))
        XCTAssertTrue(srt.contains("00:01:24,000 --> 00:01:26,000"))
        XCTAssertTrue(srt.contains("こんにちは\n你好"))
        XCTAssertEqual(cues[0].start, 5) // Export is non-destructive.
    }
    func testZeroStartAndRepeatedPhrasesRemainSeparateCues() throws {
        let cues = [TimedSubtitle(start: 10, end: 11, original: "Yes"), TimedSubtitle(start: 15, end: 16, original: "Yes")]
        let srt = try SubtitleTimeline.srt(cues, firstStart: 0, mode: .original)
        XCTAssertTrue(srt.contains("1\n00:00:00,000 --> 00:00:01,000"))
        XCTAssertTrue(srt.contains("2\n00:00:05,000 --> 00:00:06,000"))
    }
    func testMissingTranslationIsNotSilentlyDropped() throws {
        let cues = [TimedSubtitle(start: 0, end: 1, original: "Hello")]
        XCTAssertThrowsError(try SubtitleTimeline.srt(cues, firstStart: nil, mode: .translated))
        XCTAssertNoThrow(try SubtitleTimeline.srt(cues, firstStart: nil, mode: .original))
    }
    func testTimestampValidationAndMillisecondCarry() throws {
        for invalid in ["", "-1:00:00,000", "00:60:00,000", "00:00:60,000", "00:00:01,1", "abc"] {
            XCTAssertThrowsError(try SubtitleTimeline.parse(invalid))
        }
        XCTAssertEqual(try SubtitleTimeline.parse("01:02:03.456"), 3723.456, accuracy: 0.0001)
        XCTAssertEqual(SubtitleTimeline.timestamp(59.9996), "00:01:00,000")
    }
    func testUnchangedTimingUnicodeAndExportModes() throws {
        let cues = [TimedSubtitle(start: 1.234, end: 3.456, original: "字幕", translated: "字幕翻譯")]
        let text = try SubtitleTimeline.srt(cues, firstStart: nil, mode: .translated)
        XCTAssertEqual(text, "1\n00:00:01,234 --> 00:00:03,456\n字幕翻譯\n")
        XCTAssertEqual(String(data: Data(text.utf8), encoding: .utf8), text)
    }
    func testInvalidRangesAndBlankTranslationsAreRejected() {
        for (start, end) in [(Double.nan, 1.0), (0, Double.infinity), (-1, 2), (2, 1), (1, 1)] {
            XCTAssertThrowsError(try SubtitleTimeline.srt([TimedSubtitle(start: start, end: end, original: "Hello")], firstStart: nil, mode: .original))
        }
        let cue = TimedSubtitle(start: 0, end: 1, original: "Hello", translated: "  ")
        XCTAssertThrowsError(try SubtitleTimeline.srt([cue], firstStart: nil, mode: .both))
        XCTAssertThrowsError(try SubtitleTimeline.srt([cue], firstStart: .nan, mode: .original))
        XCTAssertThrowsError(try SubtitleTimeline.parse("+1:00:00,000"))
        XCTAssertThrowsError(try SubtitleTimeline.srt([TimedSubtitle(start: 3_599_999.9989, end: 3_599_999.999, original: "End")], firstStart: nil, mode: .original))
    }
    func testOutOfOrderCuesUseEarliestCueForOffset() throws {
        let cues = [TimedSubtitle(start: 5, end: 6, original: "Later"), TimedSubtitle(start: 1, end: 2, original: "First")]
        let result = try SubtitleTimeline.srt(cues, firstStart: 10, mode: .original)
        XCTAssertTrue(result.hasPrefix("1\n00:00:10,000 --> 00:00:11,000\nFirst"))
        XCTAssertTrue(result.contains("00:00:14,000 --> 00:00:15,000"))
    }
    func testShortCueStillHasPositiveExportDuration() throws {
        let result = try SubtitleTimeline.srt([TimedSubtitle(start: 1, end: 1.0001, original: "Hi")], firstStart: nil, mode: .original)
        XCTAssertTrue(result.contains("00:00:01,000 --> 00:00:01,001"))
    }
    func testPendingQueueRetainsFailedCueAndCompactsWithoutDroppingWork() {
        var queue = PendingCueQueue()
        for index in 0..<2000 { queue.append(index) }
        XCTAssertEqual(queue.first, 0)
        // A failed translation leaves the first item available for retry.
        XCTAssertEqual(queue.first, 0)
        for index in 0..<2000 {
            XCTAssertEqual(queue.first, index)
            queue.finishFirst()
        }
        XCTAssertEqual(queue.count, 0)
        XCTAssertNil(queue.first)
        queue.append(2000)
        XCTAssertEqual(queue.first, 2000)
    }
}

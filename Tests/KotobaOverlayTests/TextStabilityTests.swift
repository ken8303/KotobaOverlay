import XCTest
@testable import KotobaOverlay
final class TextStabilityTests: XCTestCase {
    func testStabilizesDeduplicatesAndClears() {
        var state = TextStability()
        XCTAssertNil(state.update("こんにちは"))
        XCTAssertEqual(state.update("こんにちは"), "こんにちは")
        XCTAssertNil(state.update("こんにちは"))
        XCTAssertNil(state.update(""))
        XCTAssertNil(state.update(""))
        XCTAssertEqual(state.update(""), "")
    }
    func testShortConfidentSubtitleEmitsOnFirstReading() {
        var state = TextStability()
        XCTAssertEqual(state.update("危ない！", confidence: 0.95), "危ない！")
        XCTAssertNil(state.update("危ない！", confidence: 0.95))
        XCTAssertEqual(state.update("逃げて！", confidence: 0.95), "逃げて！")
    }
    func testSingleEmptyOCRDoesNotClearVisibleSubtitle() {
        var state = TextStability()
        _ = state.update("待って", confidence: 0.9)
        XCTAssertNil(state.update(""))
        XCTAssertNil(state.update("待って", confidence: 0.9))
        XCTAssertEqual(state.emitted, "待って")
    }
    func testTransientTextNeverEmits() {
        var state = TextStability()
        XCTAssertNil(state.update("partial"))
        XCTAssertNil(state.update("complete"))
        XCTAssertEqual(state.update("complete"), "complete")
    }
}

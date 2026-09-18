import XCTest
@testable import KotobaOverlay

final class InputFieldExclusionTests: XCTestCase {
    func testInputLineRemovedButNearbySubtitleRetained() {
        let lines = [
            OCRLine(text: "typing", rect: CGRect(x: 0.1, y: 0.1, width: 0.5, height: 0.1), confidence: 1),
            OCRLine(text: "subtitle", rect: CGRect(x: 0.1, y: 0.6, width: 0.5, height: 0.1), confidence: 1)
        ]
        let result = excludingInputFields(lines, captureFrame: CGRect(x: -800, y: 200, width: 800, height: 400), fields: [CGRect(x: -730, y: 235, width: 420, height: 50)])
        XCTAssertEqual(result.map(\.text), ["subtitle"])
        XCTAssertEqual(excludingInputFields(lines, captureFrame: .zero, fields: []).count, 2)
    }
    func testPartialOverlapIsExcluded() {
        let line = OCRLine(text: "input", rect: CGRect(x: 0.1, y: 0.1, width: 0.5, height: 0.1), confidence: 1)
        XCTAssertTrue(excludingInputFields([line], captureFrame: CGRect(x: 0, y: 0, width: 1000, height: 500), fields: [CGRect(x: 590, y: 50, width: 100, height: 60)]).isEmpty)
    }
}

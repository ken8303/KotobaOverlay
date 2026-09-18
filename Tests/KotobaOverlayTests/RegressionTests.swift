import XCTest
import AppKit
@testable import KotobaOverlay

final class RegressionTests: XCTestCase {
    @MainActor func testBilingualLabelHonorsFontSizeAndExpandsBeyondOCRBox() throws {
        let text = "ここで待ってください。\n請在這裡等候。"
        let anchor = CGRect(x: 100, y: 180, width: 400, height: 24)
        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 400)
        let small = translationLabelLayout(text: text, anchor: anchor, bounds: bounds, fontSize: 18)
        let large = translationLabelLayout(text: text, anchor: anchor, bounds: bounds, fontSize: 48)
        XCTAssertEqual((large.attributes[.font] as? NSFont)?.pointSize, 48)
        XCTAssertGreaterThan(large.box.height, small.box.height)
        XCTAssertGreaterThan(large.box.height, anchor.height)
        XCTAssertTrue(bounds.contains(large.box))
        let canvas = TranslationCanvas(frame: bounds)
        canvas.fontSize = 48
        canvas.items = [PositionedTranslation(id: 0, text: text, rect: CGRect(x: 0.1, y: 0.45, width: 0.4, height: 0.06))]
        let image = NSImage(size: bounds.size, flipped: false) { rect in
            canvas.draw(rect)
            return true
        }
        let bitmap = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let data = try XCTUnwrap(NSBitmapImageRep(cgImage: bitmap).representation(using: .png, properties: [:]))
        try data.write(to: URL(fileURLWithPath: "/private/tmp/kotoba-font-size-fix.png"))
    }

    private func reading(_ text: String, confidence: Float = 0.95, x: CGFloat = 0) -> OCRReading {
        OCRReading(lines: text.isEmpty ? [] : [OCRLine(text: text, rect: CGRect(x: x, y: 0, width: 0.5, height: 0.1), confidence: confidence)])
    }

    func testOverlaySurvivesTwoEmptyFramesThenClears() {
        var state = StableOCRReading()
        XCTAssertTrue(state.update(reading("待って")))
        for _ in 0..<2 {
            XCTAssertFalse(state.update(reading("")))
            XCTAssertEqual(state.lines.first?.text, "待って")
        }
        XCTAssertTrue(state.update(reading("")))
        XCTAssertTrue(state.lines.isEmpty)
    }

    func testUnstableReplacementDoesNotReplaceAcceptedLines() {
        var state = StableOCRReading()
        _ = state.update(reading("old"))
        XCTAssertFalse(state.update(reading("new", confidence: 0.4)))
        XCTAssertEqual(state.lines.first?.text, "old")
        XCTAssertTrue(state.update(reading("new", confidence: 0.4)))
        XCTAssertEqual(state.lines.first?.text, "new")
        XCTAssertFalse(state.update(reading("new", x: 0.2)))
        XCTAssertEqual(state.lines.first?.rect.minX, 0.2)
    }

    func testCacheEvictsOldOffscreenTextWithoutErasingVisibleBatch() {
        var cache = TranslationCache(capacity: 2)
        cache.insert("old", for: "old", protecting: [])
        cache.insert("A", for: "a", protecting: ["a", "b"])
        cache.insert("B", for: "b", protecting: ["a", "b"])
        XCTAssertNil(cache["old"])
        XCTAssertEqual(cache["a"], "A")
        XCTAssertEqual(cache["b"], "B")
        cache.removeAll()
        XCTAssertNil(cache["a"])
    }
}

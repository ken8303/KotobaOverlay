import AppKit
import XCTest
@testable import KotobaOverlay
final class OCRTests: XCTestCase {
    @MainActor func testTwoSubtitleLinesKeepSeparatePositions() async throws {
        let image = NSImage(size: NSSize(width: 700, height: 180), flipped: false) { rect in
            NSColor.black.setFill(); rect.fill()
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 32), .foregroundColor: NSColor.white]
            ("ここで待ってください。" as NSString).draw(at: CGPoint(x: 24, y: 110), withAttributes: attributes)
            ("すぐに戻ります。" as NSString).draw(at: CGPoint(x: 24, y: 40), withAttributes: attributes)
            return true
        }
        let bitmap = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let normalized = try CaptureService.recognitionBitmap(bitmap)
        XCTAssertEqual(normalized.width, bitmap.width)
        XCTAssertEqual(normalized.height, bitmap.height)
        XCTAssertEqual(normalized.bitsPerComponent, 8)
        let reading = try await CaptureService.recognize(normalized, language: "ja-JP")
        XCTAssertEqual(reading.lines.count, 2)
        XCTAssertTrue(reading.lines[0].text.contains("待って"))
        XCTAssertTrue(reading.lines[1].text.contains("戻り"))
        XCTAssertGreaterThan(reading.lines[0].rect.minY, reading.lines[1].rect.maxY)
    }
    @MainActor func testJapaneseSubtitleRecognition() async throws {
        let text = "危ない！早く逃げて！"
        let image = NSImage(size: NSSize(width: 700, height: 100), flipped: false) { rect in
            NSColor.black.setFill(); rect.fill()
            (text as NSString).draw(at: CGPoint(x: 24, y: 24), withAttributes: [.font: NSFont.systemFont(ofSize: 40), .foregroundColor: NSColor.white])
            return true
        }
        let bitmap = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let start = ContinuousClock.now
        let reading = try await CaptureService.recognize(bitmap, language: "ja-JP")
        print("Japanese subtitle OCR duration: \(start.duration(to: .now)); confidence: \(reading.confidence)")
        XCTAssertTrue(reading.text.contains("早く逃げて"), reading.text)
        let warmStart = ContinuousClock.now
        let warmReading = try await CaptureService.recognize(bitmap, language: "ja-JP")
        print("Warm Japanese subtitle OCR duration: \(warmStart.duration(to: .now))")
        XCTAssertTrue(warmReading.text.contains("早く逃げて"))
        var stability = TextStability()
        XCTAssertNotNil(stability.update(reading.text, confidence: reading.confidence))
    }
}

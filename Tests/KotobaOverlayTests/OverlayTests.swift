import AppKit
import XCTest
@testable import KotobaOverlay
final class OverlayTests: XCTestCase {
    @MainActor func testMultilineTranslationRendering() async throws {
        let canvas = TranslationCanvas(frame: CGRect(x: 0, y: 0, width: 900, height: 260))
        canvas.opacity = 1
        canvas.items = [
            PositionedTranslation(id: 0, text: "請在這裡等候，我很快就會回來。", rect: CGRect(x: 0.1, y: 0.6, width: 0.8, height: 0.2)),
            PositionedTranslation(id: 1, text: "前方有危險，請小心！", rect: CGRect(x: 0.1, y: 0.2, width: 0.8, height: 0.2))
        ]
        let image = NSImage(size: canvas.bounds.size, flipped: false) { rect in
            NSColor.darkGray.setFill(); rect.fill()
            canvas.draw(rect)
            return true
        }
        let bitmap = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let reading = try await CaptureService.recognize(bitmap, language: "zh-Hant")
        XCTAssertTrue(reading.text.contains("請在這裡等候"), reading.text)
        XCTAssertTrue(reading.text.contains("前方有危險"), reading.text)
        let rep = NSBitmapImageRep(cgImage: bitmap)
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: "/private/tmp/kotoba-multiline-preview.png"))
    }
}

import XCTest
@testable import KotobaOverlay
final class TranslationHistoryTests: XCTestCase {
    func testDeduplicatesWithoutLosingLanguagePairsOrOrder() {
        var history = TranslationHistory()
        history.append(source: "ja", target: "zh-TW", original: "待って", translated: "等一下")
        history.append(source: "ja", target: "zh-TW", original: "待って", translated: "等一下")
        history.append(source: "ja", target: "en", original: "待って", translated: "Wait")
        XCTAssertEqual(history.records.count, 2)
        XCTAssertEqual(history.records.first?.translated, "等一下")
        XCTAssertTrue(history.plainText.contains("1. ja → zh-TW\nOriginal: 待って\nTranslation: 等一下"))
        XCTAssertTrue(history.plainText.contains("2. ja → en"))
    }
    func testExportRetainsMultilineUnicodeAsUTF8() throws {
        var history = TranslationHistory()
        history.append(source: "ja", target: "zh-TW", original: "こんにちは\n世界", translated: "你好\n世界")
        let encoded = try XCTUnwrap(history.plainText.data(using: .utf8))
        XCTAssertEqual(String(data: encoded, encoding: .utf8), history.plainText)
        XCTAssertTrue(history.plainText.contains("Translation: 你好\n世界"))
    }
}

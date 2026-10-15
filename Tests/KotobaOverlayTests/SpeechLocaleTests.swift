import XCTest
@testable import KotobaOverlay
final class SpeechLocaleTests: XCTestCase {
    func testJapaneseLanguageCodeMapsToSpeechRegion() {
        XCTAssertEqual(matchingSpeechLocale("ja", supported: [Locale(identifier: "en_US"), Locale(identifier: "ja_JP")])?.identifier, "ja_JP")
    }
    func testChineseScriptIsNotSilentlySwitched() {
        XCTAssertEqual(matchingSpeechLocale("zh-Hant", supported: [Locale(identifier: "zh_CN"), Locale(identifier: "zh_TW")])?.identifier, "zh_TW")
        XCTAssertNil(matchingSpeechLocale("zh-Hant", supported: [Locale(identifier: "zh_CN")]))
    }
    func testUnsupportedAndExactRegionalPreference() {
        XCTAssertNil(matchingSpeechLocale("ja", supported: []))
        XCTAssertEqual(matchingSpeechLocale("en-GB", supported: [Locale(identifier: "en_US"), Locale(identifier: "en_GB")])?.identifier, "en_GB")
    }
    func testRegionalFallbackPrefersCurrentRegionButHonorsExplicitRegion() {
        let supported = [Locale(identifier: "en_AU"), Locale(identifier: "en_GB")]
        XCTAssertEqual(matchingSpeechLocale("en", supported: supported, preferred: Locale(identifier: "en_GB"))?.identifier, "en_GB")
        XCTAssertEqual(matchingSpeechLocale("en-AU", supported: supported, preferred: Locale(identifier: "en_GB"))?.identifier, "en_AU")
    }
}

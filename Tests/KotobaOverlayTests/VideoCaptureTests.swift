import XCTest
@testable import KotobaOverlay

final class VideoCaptureTests: XCTestCase {
    func testWindowResizeScalesVideoSelection() {
        let region = CGRect(x: 0.1, y: 0.2, width: 0.8, height: 0.6)
        let crop = trackedVideoCrop(region: region, windowSize: CGSize(width: 1600, height: 1000), fullscreen: false, subtitlesOnly: false)
        XCTAssertEqual(crop, CGRect(x: 160, y: 200, width: 1280, height: 600))
    }
    func testFullscreenUsesWholePictureThenRestoresWindowRegion() {
        let region = CGRect(x: 0.1, y: 0.2, width: 0.6, height: 0.5)
        let size = CGSize(width: 1920, height: 1080)
        let full = trackedVideoCrop(region: region, windowSize: size, fullscreen: true, subtitlesOnly: true)
        XCTAssertEqual(full, CGRect(x: 0, y: 648, width: 1920, height: 432))
        let restored = trackedVideoCrop(region: region, windowSize: CGSize(width: 1000, height: 800), fullscreen: false, subtitlesOnly: false)
        XCTAssertEqual(restored, CGRect(x: 100, y: 160, width: 600, height: 400))
    }
    func testFullscreenOnSecondaryDisplay() {
        let display = CGRect(x: -1920, y: 200, width: 1920, height: 1080)
        XCTAssertTrue(isFullscreenVideoWindow(display, display: display))
        XCTAssertFalse(isFullscreenVideoWindow(CGRect(x: -1920, y: 200, width: 1800, height: 1000), display: display))
    }
    func testSubtitleBandUsesBottomOfVideoAndPreservesOffset() {
        let video = CGRect(x: 200, y: 150, width: 1000, height: 600)
        let band = videoCaptureRect(video, subtitlesOnly: true)
        XCTAssertEqual(band, CGRect(x: 200, y: 150, width: 1000, height: 240))
        XCTAssertEqual(captureCrop(band, screenHeight: 1080), CGRect(x: 200, y: 690, width: 1000, height: 240))
        XCTAssertTrue(video.contains(band))
    }
    func testFullVideoIncludesCaptionsAtTop() {
        let video = CGRect(x: 120, y: 80, width: 800, height: 450)
        XCTAssertEqual(videoCaptureRect(video, subtitlesOnly: false), video)
    }
}

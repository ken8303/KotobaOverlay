import XCTest
@testable import KotobaOverlay
final class RegionGeometryTests: XCTestCase {
    func testBottomAreaConvertsToCaptureTopOrigin() {
        XCTAssertEqual(captureCrop(CGRect(x: 120, y: 40, width: 800, height: 180), screenHeight: 1080), CGRect(x: 120, y: 860, width: 800, height: 180))
    }
    func testMoveClampsToDisplayAndKeepsSize() {
        let rect = CGRect(x: 100, y: 100, width: 400, height: 100)
        XCTAssertEqual(adjustedRegion(rect, dx: -500, dy: 1000, grip: .move, bounds: CGRect(x: 0, y: 0, width: 1920, height: 1080)), CGRect(x: 0, y: 980, width: 400, height: 100))
    }
    func testCornerResizeKeepsOppositeCornerAndMinimumSize() {
        let rect = CGRect(x: 100, y: 100, width: 400, height: 100)
        XCTAssertEqual(adjustedRegion(rect, dx: 1000, dy: 1000, grip: .bottomLeft, bounds: CGRect(x: 0, y: 0, width: 1920, height: 1080)), CGRect(x: 460, y: 160, width: 40, height: 40))
    }
    func testOCRBoxMapsToCaptureSize() {
        XCTAssertEqual(textBox(CGRect(x: 0.1, y: 0.2, width: 0.8, height: 0.1), in: CGSize(width: 1000, height: 500)), CGRect(x: 100, y: 100, width: 800, height: 50))
    }
    func testAreaAtTopOfDisplay() {
        XCTAssertEqual(captureCrop(CGRect(x: 0, y: 900, width: 600, height: 180), screenHeight: 1080), CGRect(x: 0, y: 0, width: 600, height: 180))
    }
}

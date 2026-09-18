import XCTest
@testable import KotobaOverlay

final class AudioShutdownTests: XCTestCase {
    @MainActor func testConcurrentStopsWaitForFinalDelivery() async {
        let shutdown = AudioShutdown()
        var release: CheckedContinuation<Void, Never>?
        var operations = 0
        var delivered = false
        var returned = 0
        let first = Task { @MainActor in
            await shutdown.run {
                operations += 1
                await withCheckedContinuation { release = $0 }
                delivered = true
            }
            XCTAssertTrue(delivered)
            returned += 1
        }
        while release == nil { await Task.yield() }
        let second = Task { @MainActor in
            await shutdown.run { operations += 1 }
            XCTAssertTrue(delivered)
            returned += 1
        }
        // Allow the second caller to reach the suspended shutdown.
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(operations, 1)
        XCTAssertEqual(returned, 0)
        release?.resume()
        await first.value
        await second.value
        XCTAssertEqual(operations, 1)
        XCTAssertEqual(returned, 2)
        await shutdown.run { operations += 1 }
        XCTAssertEqual(operations, 2)
    }
}

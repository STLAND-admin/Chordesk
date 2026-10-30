import XCTest
@testable import DuoWorkbench

final class RearRecoveryTests: XCTestCase {
    func testIdleHealthySessionNeverRestartsOrCancelsHeldContacts() {
        var state = RearCaptureRecovery()
        for _ in 0..<500 {
            XCTAssertEqual(state.sample(allowed: true, interrupted: false, running: true,
                                        enabled: true, available: true, presented: true), .none)
        }
        XCTAssertEqual(state.attempts, 0)
    }
    func testRecoveryRequiresRepeatedFailureAndHasRetryBudget() {
        var state = RearCaptureRecovery()
        for _ in 0..<3 {
            XCTAssertEqual(state.sample(allowed: true, interrupted: false, running: false,
                                        enabled: false, available: true, presented: false), .none)
            XCTAssertEqual(state.sample(allowed: true, interrupted: false, running: false,
                                        enabled: false, available: true, presented: false), .restartSession)
        }
        for _ in 0..<10 {
            XCTAssertEqual(state.sample(allowed: true, interrupted: false, running: false,
                                        enabled: false, available: true, presented: false), .none)
        }
    }
    func testAccessoryCanRebindWithoutRestartingCapture() {
        var state = RearCaptureRecovery()
        _ = state.sample(allowed: true, interrupted: false, running: true, enabled: false, available: true, presented: false)
        XCTAssertEqual(state.sample(allowed: true, interrupted: false, running: true,
                                    enabled: false, available: true, presented: false), .rebindAccessory)
    }
    func testNoRecoveryWhileUnavailableInterruptedOrUnauthorized() {
        var state = RearCaptureRecovery()
        for _ in 0..<10 {
            XCTAssertEqual(state.sample(allowed: false, interrupted: false, running: false,
                                        enabled: false, available: true, presented: false), .none)
            XCTAssertEqual(state.sample(allowed: true, interrupted: true, running: false,
                                        enabled: false, available: true, presented: false), .none)
            XCTAssertEqual(state.sample(allowed: true, interrupted: false, running: true,
                                        enabled: false, available: false, presented: false), .none)
        }
        XCTAssertEqual(state.attempts, 0)
    }
    func testBadgeUsesFreeTopSpaceAndAvoidsSystemOcclusions() {
        let bounds = CGRect(x: 0, y: 0, width: 800, height: 700)
        let ornament = CGRect(x: 700, y: 0, width: 100, height: 110)
        let result = RearStatusPlacement.frame(size: .init(width: 90, height: 28), in: bounds, avoiding: [ornament])
        XCTAssertEqual(result.minY, 0)
        XCTAssertEqual(result.maxX, ornament.minX)
        XCTAssertFalse(result.intersects(ornament))
        let island = CGRect(x: 0, y: 0, width: 800, height: 40)
        XCTAssertEqual(RearStatusPlacement.frame(size: result.size, in: bounds, avoiding: [island]).minY, 40)
    }
}

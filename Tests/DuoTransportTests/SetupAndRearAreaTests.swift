import XCTest
@testable import DuoWorkbench

final class SetupAndRearAreaTests: XCTestCase {
    func testPermissionRestartRequiresAllGrantsAndIdleSessionAndOnlyOnce() {
        var policy = PermissionRestartPolicy(needsRestart: true, attempted: false)
        let ready = HostPermissionSnapshot(screen: true, accessibility: true, input: true)
        for missing in [HostPermissionSnapshot(screen: false, accessibility: true, input: true),
                        .init(screen: true, accessibility: false, input: true), .init(screen: true, accessibility: true, input: false)] {
            XCTAssertFalse(policy.eligible(missing, automatic: true, sharing: false))
        }
        XCTAssertFalse(policy.eligible(ready, automatic: false, sharing: false))
        XCTAssertFalse(policy.eligible(ready, automatic: true, sharing: true))
        XCTAssertTrue(policy.eligible(ready, automatic: true, sharing: false))
        policy.claim()
        XCTAssertFalse(policy.eligible(ready, automatic: true, sharing: false))
        XCTAssertFalse(PermissionRestartPolicy(needsRestart: false, attempted: false).eligible(ready, automatic: true, sharing: false))
    }
    func testRearRegionCanReachAnEdgeAndRemainsWithinSafeBounds() {
        let centered = RearActiveRegion.centered(inset: 0.125)
        let edge = centered.translated(dx: -10, dy: 10)
        XCTAssertEqual(edge.x, 0); XCTAssertEqual(edge.y, 0.25)
        XCTAssertEqual(edge.width, 0.75); XCTAssertEqual(edge.height, 0.75)
        let bounds = CGRect(x: 15, y: 20, width: 600, height: 300)
        XCTAssertEqual(edge.rect(in: bounds), CGRect(x: 15, y: 95, width: 450, height: 225))
        XCTAssertEqual(RearActiveRegion.decode(edge.encoded, inset: 0), edge)
        XCTAssertEqual(RearActiveRegion.decode("broken", inset: 0.125), centered)
    }
    func testRearRegionResizeKeepsOppositeCornerAndMinimumExtent() {
        let start = RearActiveRegion(x: 0.2, y: 0.3, width: 0.6, height: 0.5)
        let resized = start.resized(.topLeft, dx: -0.3, dy: 0.8)
        XCTAssertEqual(resized.x, 0); XCTAssertEqual(resized.y, 0.65, accuracy: 0.0001)
        XCTAssertEqual(resized.x + resized.width, 0.8, accuracy: 0.0001)
        XCTAssertEqual(resized.y + resized.height, 0.8, accuracy: 0.0001)
        XCTAssertEqual(resized.height, 0.15, accuracy: 0.0001)
        let full = start.resized(.bottomRight, dx: 10, dy: 10)
        XCTAssertEqual(full.x, 0.2, accuracy: 0.0001); XCTAssertEqual(full.y, 0.3, accuracy: 0.0001)
        XCTAssertEqual(full.width, 0.8); XCTAssertEqual(full.height, 0.7)
    }
    func testRearRegionRejectsInvalidSavedGeometry() {
        let value = RearActiveRegion(x: .nan, y: -.infinity, width: -1, height: 8).normalized
        XCTAssertTrue(value.x.isFinite && value.y.isFinite)
        XCTAssertEqual(value.width, 0.15); XCTAssertEqual(value.height, 1); XCTAssertEqual(value.y, 0)
    }
    func testRearContactOutsideCustomBoxOrLeavingItRequiresLift() {
        let rect = RearActiveRegion(x: 0, y: 0.2, width: 0.4, height: 0.6).rect(in: CGRect(x: 0,y: 0,width: 100,height: 100))
        var gate = TouchContactGate<Int>()
        gate.begin(1, at: CGPoint(x: 60,y: 40), in: rect)
        gate.move(1, to: CGPoint(x: 20,y: 40), in: rect); XCTAssertFalse(gate.accepts(1))
        gate.end(1); gate.begin(1, at: CGPoint(x: 20,y: 40), in: rect); XCTAssertTrue(gate.accepts(1))
        gate.move(1, to: CGPoint(x: 60,y: 40), in: rect)
        gate.move(1, to: CGPoint(x: 20,y: 40), in: rect); XCTAssertFalse(gate.accepts(1))
        gate.cancel(); XCTAssertTrue(gate.waitingForLift)
        gate.end(1); XCTAssertFalse(gate.waitingForLift)
    }
}

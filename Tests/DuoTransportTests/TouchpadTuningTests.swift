import XCTest
@testable import DuoWorkbench

final class TouchpadTuningTests: XCTestCase {
    private let bounds = CGRect(x: 0, y: 0, width: 400, height: 800)

    func testKeyboardCancellationWithoutEndDoesNotRejectNextContactGroup() {
        var gate = TouchContactGate<Int>()
        gate.begin(1, at: CGPoint(x: 150, y: 400), in: bounds)
        gate.begin(2, at: CGPoint(x: 250, y: 400), in: bounds)
        gate.cancel()
        XCTAssertTrue(gate.waitingForLift)
        // No touchesEnded arrives for 1/2 during the keyboard transition.
        gate.synchronize(live: [3, 4], began: [3, 4])
        gate.begin(3, at: CGPoint(x: 150, y: 400), in: bounds)
        gate.begin(4, at: CGPoint(x: 250, y: 400), in: bounds)
        XCTAssertFalse(gate.waitingForLift)
        XCTAssertTrue(gate.accepts(3) && gate.accepts(4))
        var grip = GripInputState()
        _ = grip.outerContacts(2); grip.gesture(.longPress)
        XCTAssertEqual(grip.requestedFrontMode, .trackpad)
    }

    func testCancelledRestingFingerStillBlocksNewCombinationUntilLift() {
        var gate = TouchContactGate<Int>()
        gate.begin(1, at: CGPoint(x: 150, y: 400), in: bounds)
        gate.cancel()
        gate.synchronize(live: [1, 2], began: [2])
        gate.begin(2, at: CGPoint(x: 250, y: 400), in: bounds)
        XCTAssertTrue(gate.waitingForLift)
        XCTAssertFalse(gate.accepts(1))
        gate.synchronize(live: [])
        XCTAssertFalse(gate.waitingForLift)
    }

    func testFreshBeganWithReusedTouchIdentityDoesNotInheritCancellation() {
        var gate = TouchContactGate<Int>()
        gate.begin(1, at: CGPoint(x: 150, y: 400), in: bounds); gate.cancel()
        gate.synchronize(live: [1], began: [1])
        gate.begin(1, at: CGPoint(x: 150, y: 400), in: bounds)
        XCTAssertFalse(gate.waitingForLift)
        XCTAssertTrue(gate.accepts(1))
    }

    func testSensitivityScalesMotionAndDragButNotScrollingOrButtons() {
        XCTAssertEqual(TouchpadTuning.scale(.pointerMoved(dx: 0.2, dy: -0.4), by: 0.5), .pointerMoved(dx: 0.1, dy: -0.2))
        XCTAssertEqual(TouchpadTuning.scale(.dragMoved(dx: 0.2, dy: -0.4), by: 0.5), .dragMoved(dx: 0.1, dy: -0.2))
        for event: TouchpadEvent in [.leftClick, .rightClick, .dragBegan, .dragEnded, .scrolled(amount: 0.2)] {
            XCTAssertEqual(TouchpadTuning.scale(event, by: 0.1), event)
        }
    }

    func testInvalidSettingsAreClampedAndInsetUsesEachAvailableDimension() {
        XCTAssertEqual(TouchpadTuning.sensitivity(.nan), 0.5)
        XCTAssertEqual(TouchpadTuning.sensitivity(-10), 0.1)
        XCTAssertEqual(TouchpadTuning.sensitivity(20), 1.5)
        XCTAssertEqual(TouchpadTuning.edgeInset(.infinity), 0.125)
        XCTAssertEqual(TouchpadTuning.activeRect(in: bounds, inset: 0.125), CGRect(x: 50, y: 100, width: 300, height: 600))
    }

    func testEveryEdgeAndCornerRejectsNewTouches() {
        let rect = TouchpadTuning.activeRect(in: bounds, inset: 0.125)
        var gate = TouchContactGate<Int>()
        for (id, point) in [CGPoint(x: 20, y: 400), CGPoint(x: 380, y: 400), CGPoint(x: 200, y: 50),
                            CGPoint(x: 200, y: 750), CGPoint(x: 20, y: 50), CGPoint(x: 380, y: 750)].enumerated() {
            gate.begin(id, at: point, in: rect)
            XCTAssertFalse(gate.accepts(id))
        }
        gate.begin(99, at: CGPoint(x: 200, y: 400), in: rect)
        XCTAssertTrue(gate.accepts(99))
    }

    func testEdgeOriginCannotBecomeInputUntilLiftAndNewContact() {
        let rect = TouchpadTuning.activeRect(in: bounds, inset: 0.1)
        var gate = TouchContactGate<Int>()
        gate.begin(1, at: CGPoint(x: 5, y: 400), in: rect)
        gate.move(1, to: CGPoint(x: 200, y: 400), in: rect)
        XCTAssertFalse(gate.accepts(1))
        gate.end(1)
        gate.begin(1, at: CGPoint(x: 200, y: 400), in: rect)
        XCTAssertTrue(gate.accepts(1))
    }

    func testLeavingActiveRegionDoesNotCreateMouseInputOrRearmRejectedFinger() {
        let rect = TouchpadTuning.activeRect(in: bounds, inset: 0.125)
        var gate = TouchContactGate<Int>()
        var grip = GripInputState()
        gate.begin(1, at: CGPoint(x: 150, y: 400), in: rect)
        gate.begin(2, at: CGPoint(x: 250, y: 400), in: rect)
        XCTAssertEqual(grip.outerContacts([1, 2].filter(gate.accepts).count), [])
        gate.move(2, to: CGPoint(x: 390, y: 400), in: rect)
        XCTAssertEqual(grip.outerContacts([1, 2].filter(gate.accepts).count), [])
        gate.move(2, to: CGPoint(x: 250, y: 400), in: rect)
        XCTAssertEqual(grip.outerContacts([1, 2].filter(gate.accepts).count), [])
        XCTAssertFalse(grip.buttonHeld)
    }

    func testRestingEdgeFingerDoesNotTurnCentralSingleFingerIntoDrag() {
        let rect = TouchpadTuning.activeRect(in: bounds, inset: 0.125)
        var gate = TouchContactGate<Int>()
        var grip = GripInputState()
        gate.begin(1, at: CGPoint(x: 20, y: 400), in: rect)
        gate.begin(2, at: CGPoint(x: 200, y: 400), in: rect)
        XCTAssertEqual(grip.outerContacts([1, 2].filter(gate.accepts).count), [])
        XCTAssertEqual(grip.outerCount, 1)
        gate.cancel()
        gate.move(2, to: CGPoint(x: 210, y: 410), in: rect)
        XCTAssertFalse(gate.accepts(2))
    }
}

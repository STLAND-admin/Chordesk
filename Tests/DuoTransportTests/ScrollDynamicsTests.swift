import XCTest
@testable import DuoWorkbench

final class ScrollDynamicsTests: XCTestCase {
    @MainActor
    func testStaggeredTrackpadLiftPreservesMomentumButLeavingRegionCancels() throws {
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 800)
        for leavesRegion in [false, true] {
            var gate = TouchContactGate<Int>(), tracker = ScrollGestureTracker()
            var outputs: [ScrollWheelOutput] = []
            let driver = HostScrollDriver(automaticTimer: false, clock: { 0 }, allowed: { true }, emit: { outputs.append($0); return true })
            gate.begin(1, at: CGPoint(x: 150, y: 400), in: bounds)
            gate.begin(2, at: CGPoint(x: 250, y: 400), in: bounds)
            func send(_ value: ScrollGestureEvent?) {
                if let value { XCTAssertTrue(driver.receive(value, bounds: bounds, pointer: CGPoint(x: 200, y: 400))) }
            }
            send(tracker.begin(mode: .trackpad, at: 1))
            for i in 1...10 { send(tracker.move(delta: CGPoint(x: 0, y: 0.01), at: 1 + Double(i) * 0.01)) }
            // UIKit may deliver the remaining finger's move before the other
            // finger's ended callback from the same event. Both leave one accepted
            // finger, but only an ongoing contact outside the region is a cancel.
            let live: Set<Int> = leavesRegion ? [1, 2] : [1]
            gate.synchronize(live: live)
            if leavesRegion { gate.move(2, to: CGPoint(x: 450, y: 400), in: bounds) }
            let cancel = gate.shouldCancelMovement(previouslyAccepted: 2, live: live)
            XCTAssertEqual(cancel, leavesRegion)
            if cancel { send(tracker.cancel()) }
            send(tracker.end(at: 1.11))
            driver.tick(at: 0.016)
            XCTAssertEqual(outputs.contains { $0.momentum == .began && $0.y > 0 }, !leavesRegion)
            gate.end(1); gate.end(2); gate.synchronize(live: [])
            XCTAssertFalse(gate.shouldCancelMovement(previouslyAccepted: 1, live: []))
            XCTAssertNil(tracker.end(at: 1.12), "The last lift must neither cancel nor restart momentum")
            if !leavesRegion {
                send(tracker.begin(mode: .trackpad, at: 2))
                XCTAssertEqual(outputs.last?.momentum, .ended, "A genuinely new touch still stops momentum")
            }
        }
    }

    func testBothModesUseSameVelocityAndPauseBeforeLiftStopsFlick() throws {
        var endings: [ScrollGestureEvent] = []
        for mode: ScrollGestureEvent.Mode in [.direct, .trackpad] {
            var tracker = ScrollGestureTracker()
            _ = tracker.begin(mode: mode, at: 10)
            for i in 1...10 { _ = tracker.move(delta: CGPoint(x: 0, y: 0.01), at: 10 + Double(i) * 0.01) }
            let end = try XCTUnwrap(tracker.end(at: 10.1)); endings.append(end)
            XCTAssertGreaterThan(end.velocity.y, 0.9)
            XCTAssertNil(tracker.end(at: 10.2), "A staggered final lift must not start a second coast")
            XCTAssertEqual(tracker.cancel()?.id, end.id, "Layout cancellation must still stop a finished gesture's coast")
            XCTAssertNil(tracker.cancel())
            _ = tracker.begin(mode: mode, at: 11)
            _ = tracker.move(delta: CGPoint(x: 0, y: 0.02), at: 11.02)
            XCTAssertEqual(tracker.end(at: 11.3)?.velocity, .zero)
        }
        XCTAssertEqual(endings[0].velocity, endings[1].velocity)
    }
    func testFastFlickHasHigherVelocityAndSlowSubpixelsAccumulate() throws {
        func velocity(step: Double) throws -> CGFloat {
            var tracker = ScrollGestureTracker(); _ = tracker.begin(mode: .trackpad, at: 1)
            for i in 1...10 { _ = tracker.move(delta: CGPoint(x: 0, y: 0.005), at: 1 + Double(i) * step) }
            return try XCTUnwrap(tracker.end(at: 1 + step * 10)).velocity.y
        }
        XCTAssertGreaterThan(try velocity(step: 0.01), try velocity(step: 0.05) * 4)
        var pixels = ScrollPixelAccumulator(), total: Int32 = 0
        for _ in 0..<16 { total += pixels.take(CGPoint(x: 0, y: 0.25)).y }
        XCTAssertEqual(total, 4)
        for _ in 0..<16 { total += pixels.take(CGPoint(x: 0, y: -0.25)).y }
        XCTAssertEqual(total, 0)
    }
    func testCoefficientZeroAndFrameRateIndependentDecay() {
        func travel(_ coefficient: Double, hz: Double) -> Double {
            var coast = ScrollMomentum(velocity: CGPoint(x: 0, y: 1200), coefficient: coefficient), total = 0.0
            for _ in 0..<Int(hz * 3) { if !coast.active { break }; total += coast.advance(by: 1 / hz).y }
            XCTAssertFalse(coast.active)
            return total
        }
        XCTAssertEqual(travel(0, hz: 60), 0)
        XCTAssertGreaterThan(travel(2, hz: 60), travel(1, hz: 60) * 1.5)
        XCTAssertEqual(travel(1, hz: 60), travel(1, hz: 120), accuracy: 0.2)
        var stalled = ScrollMomentum(velocity: CGPoint(x: 0, y: 2000), coefficient: 1)
        XCTAssertEqual(stalled.advance(by: 0.8), .zero)
        XCTAssertFalse(stalled.active, "A stalled event loop must not replay a large scroll jump")
    }
    func testWireRoundTripValidationAndLegacyCapability() throws {
        let sample = ScrollGestureEvent(id: UUID(), phase: .changed, mode: .direct, timestamp: 1, delta: CGPoint(x: 0, y: 0.01))
        let value = LANInput(scroll: sample)
        XCTAssertEqual(try JSONDecoder().decode(LANInput.self, from: JSONEncoder().encode(value)).scrollGesture, sample)
        var invalid = sample; invalid.coefficient = .nan; XCTAssertFalse(invalid.isValid)
        invalid = sample; invalid.velocity.y = .infinity; XCTAssertFalse(invalid.isValid)
        invalid = sample; invalid.delta.y = 2; XCTAssertFalse(invalid.isValid)
        invalid = sample; invalid.timestamp = -1; XCTAssertFalse(invalid.isValid)
        let legacy = LANStatus(name: "Mac", width: 900, height: 600, canControl: true, message: "ready")
        XCTAssertNil(try JSONDecoder().decode(LANStatus.self, from: JSONEncoder().encode(legacy)).supportsScrollDynamics)
    }
    @MainActor
    func testHostPhasesSameForBothModesAndNewFingerCancelsMomentum() throws {
        for mode: ScrollGestureEvent.Mode in [.direct, .trackpad] {
            var outputs: [ScrollWheelOutput] = []
            let driver = HostScrollDriver(automaticTimer: false, clock: { 0 }, allowed: { true }, emit: { outputs.append($0); return true })
            let bounds = CGRect(x: 100, y: 200, width: 1200, height: 1200)
            var event = ScrollGestureEvent(id: UUID(), phase: .began, mode: mode, timestamp: 1)
            func receive() { XCTAssertTrue(driver.receive(event, bounds: bounds, pointer: CGPoint(x: 400, y: 400))) }
            receive(); XCTAssertTrue(outputs.isEmpty, "A simple tap must not inject a scroll")
            event.phase = .changed; event.timestamp = 1.02; event.delta.y = 0.01; receive()
            XCTAssertEqual(outputs.last?.phase, .began); XCTAssertEqual(outputs.last?.y, 12)
            event.phase = .ended; event.timestamp = 1.03; event.delta = .zero; event.velocity.y = 1; receive()
            XCTAssertEqual(outputs.last?.phase, .ended)
            driver.tick(at: 1.0 / 60); XCTAssertEqual(outputs.last?.momentum, .began)
            let first = try XCTUnwrap(outputs.last?.y)
            driver.tick(at: 2.0 / 60); XCTAssertEqual(outputs.last?.momentum, .changed)
            XCTAssertLessThanOrEqual(try XCTUnwrap(outputs.last?.y), first)
            let oldID = event.id
            event.id = UUID(); event.phase = .began; event.timestamp = 2; event.velocity = .zero; receive()
            XCTAssertEqual(outputs.last?.momentum, .ended)
            let count = outputs.count
            driver.tick(at: 3.0 / 60); XCTAssertEqual(outputs.count, count)
            event.id = oldID; event.phase = .ended
            XCTAssertFalse(driver.receive(event, bounds: bounds, pointer: .zero), "Late end cannot restart an old gesture")
            driver.cancel(); XCTAssertFalse(driver.isActive)
        }
    }
    @MainActor
    func testPermissionRevocationCancelAndDisabledInertia() {
        var allowed = true, outputs: [ScrollWheelOutput] = []
        let driver = HostScrollDriver(automaticTimer: false, clock: { 0 }, allowed: { allowed }, emit: { outputs.append($0); return true })
        let bounds = CGRect(x: 0, y: 0, width: 1200, height: 800)
        func flick(coefficient: Double) -> ScrollGestureEvent {
            var event = ScrollGestureEvent(id: UUID(), phase: .began, mode: .direct, timestamp: 1, coefficient: coefficient)
            XCTAssertTrue(driver.receive(event, bounds: bounds, pointer: .zero))
            event.phase = .changed; event.timestamp = 1.01; event.delta.y = 0.01
            XCTAssertTrue(driver.receive(event, bounds: bounds, pointer: .zero))
            event.phase = .ended; event.timestamp = 1.02; event.delta = .zero; event.velocity.y = 1
            XCTAssertTrue(driver.receive(event, bounds: bounds, pointer: .zero))
            return event
        }
        _ = flick(coefficient: 0); let count = outputs.count
        driver.tick(at: 0.02); XCTAssertEqual(outputs.count, count); XCTAssertFalse(driver.isActive)
        var ended = flick(coefficient: 1)
        driver.tick(at: 0.02); ended.phase = .cancelled
        XCTAssertTrue(driver.receive(ended, bounds: bounds, pointer: .zero)); XCTAssertFalse(driver.isActive)
        XCTAssertEqual(outputs.last?.momentum, .ended)
        _ = flick(coefficient: 1); allowed = false; let before = outputs.count
        driver.tick(at: 0.02); XCTAssertEqual(outputs.count, before); XCTAssertFalse(driver.isActive)
        allowed = true; driver.tick(at: 0.04); XCTAssertEqual(outputs.count, before, "Regrant must not replay old momentum")
    }
    @MainActor
    func testPublicCGEventsCarryScrollAndMomentumPhasesWithoutModifiers() throws {
        let factory = RemoteEventFactory()
        let event = try XCTUnwrap(factory.scroll(dy: 7, phase: .none, momentum: .began))
        XCTAssertEqual(event.getIntegerValueField(.scrollWheelEventMomentumPhase), 1)
        XCTAssertEqual(event.getIntegerValueField(.scrollWheelEventScrollPhase), 0)
        XCTAssertEqual(event.getIntegerValueField(.scrollWheelEventIsContinuous), 1)
        XCTAssertEqual(event.flags, [])
        let end = try XCTUnwrap(factory.scroll(dy: 0, phase: .ended))
        XCTAssertEqual(end.getIntegerValueField(.scrollWheelEventScrollPhase), 4)
        // Intentionally never call post(): construction is independent of TCC.
    }
}

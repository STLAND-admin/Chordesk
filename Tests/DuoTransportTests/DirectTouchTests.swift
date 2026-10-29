import XCTest
@testable import DuoWorkbench

final class DirectTouchTests: XCTestCase {
    func testOverviewUsesSemanticAllowlistedWireActionsAndOldStatusDefaultsToUnsupported() throws {
        for action: WindowOverviewAction in [.show, .hide, .previousDesktop, .nextDesktop] {
            let input = LANInput(overview: action)
            let decoded = try JSONDecoder().decode(LANInput.self, from: JSONEncoder().encode(input))
            XCTAssertEqual(decoded.windowOverview, action)
            XCTAssertEqual(decoded.key, "")
            XCTAssertEqual(decoded.modifiers, 0)
        }
        var invalid = LANInput(overview: .show); invalid.action = "window.launch"
        XCTAssertNil(invalid.windowOverview)
        let legacy = LANStatus(name: "Mac", width: 800, height: 600, canControl: true, message: "ready")
        let decoded = try JSONDecoder().decode(LANStatus.self, from: JSONEncoder().encode(legacy))
        XCTAssertNil(decoded.supportsWindowOverview)
        XCTAssertNil(decoded.supportsDesktopSwitch)
    }
    private let fingers = [CGPoint(x: 100, y: 200), CGPoint(x: 100, y: 300)]
    private func shifted(_ a: CGFloat, _ b: CGFloat, dx: CGFloat = 0) -> [CGPoint] {
        [CGPoint(x: 100 + dx, y: 200 + a), CGPoint(x: 100 + dx, y: 300 + b)]
    }
    func testWindowChordFiresOnceAndToleratesAsynchronousFingerMovement() {
        var swipe = WindowOverviewSwipe()
        swipe.begin(at: fingers)
        XCTAssertNil(swipe.move(to: shifted(-55, 0), rearContacts: 1))
        XCTAssertEqual(swipe.move(to: shifted(-55, -55), rearContacts: 1), .show)
        XCTAssertNil(swipe.move(to: shifted(-100, -100), rearContacts: 1))
        swipe.begin(at: fingers)
        XCTAssertEqual(swipe.move(to: shifted(60, 60), rearContacts: 1), .hide)
    }
    func testWindowChordRejectsPinchAndOneFingerMotion() {
        var swipe = WindowOverviewSwipe()
        swipe.begin(at: fingers)
        XCTAssertNil(swipe.move(to: shifted(-60, 60), rearContacts: 1))
        XCTAssertNil(swipe.move(to: shifted(-100, 0), rearContacts: 1))
        swipe.begin(at: fingers)
        XCTAssertEqual(swipe.move(to: shifted(-10, -10, dx: 70), rearContacts: 1), .previousDesktop)
        XCTAssertNil(swipe.move(to: shifted(-160, -160), rearContacts: 1))
    }
    func testHorizontalChordFiresOnceAndUsesNaturalDesktopDirection() {
        var swipe = WindowOverviewSwipe()
        swipe.begin(at: fingers)
        XCTAssertNil(swipe.move(to: [CGPoint(x: 30, y: 202), fingers[1]], rearContacts: 1))
        XCTAssertEqual(swipe.move(to: shifted(2, 3, dx: -70), rearContacts: 1), .nextDesktop)
        XCTAssertNil(swipe.move(to: shifted(80, 80, dx: -70), rearContacts: 1))
        swipe.begin(at: fingers)
        XCTAssertEqual(swipe.move(to: shifted(3, 2, dx: 70), rearContacts: 1), .previousDesktop)
    }
    func testPinchCannotTurnIntoADesktopSwitchAndDiagonalDoesNotFire() {
        var swipe = WindowOverviewSwipe()
        swipe.begin(at: fingers)
        XCTAssertNil(swipe.move(to: [CGPoint(x: 40, y: 200), CGPoint(x: 160, y: 300)], rearContacts: 1))
        XCTAssertNil(swipe.move(to: shifted(0, 0, dx: -100), rearContacts: 1))
        swipe.begin(at: fingers)
        XCTAssertNil(swipe.move(to: shifted(70, 70, dx: 70), rearContacts: 1))
        swipe.cancel()
        XCTAssertNil(swipe.move(to: shifted(0, 0, dx: 100), rearContacts: 1))
    }
    func testOrdinaryKeyboardShortcutBalancesControlAndDoesNotAffectNextPointer() throws {
        let factory = RemoteEventFactory()
        for key: CGKeyCode in [123, 124] {
            let events = try XCTUnwrap(factory.keyboard(code: key, modifiers: 8))
            XCTAssertEqual(events.count, 4)
            XCTAssertEqual(events[1].type, .keyDown)
            XCTAssertEqual(events[1].getIntegerValueField(.keyboardEventKeycode), Int64(key))
            XCTAssertEqual(events[1].flags, .maskControl)
            XCTAssertEqual(events.last?.flags, [])
            XCTAssertEqual(factory.mouse(.leftMouseDown, at: .zero)?.flags, [])
        }
    }
    func testWindowChordCannotResumeAfterRearLiftFrontLiftOrCancellation() {
        for rear in [0, 2, 3] {
            var swipe = WindowOverviewSwipe()
            swipe.begin(at: fingers)
            XCTAssertNil(swipe.move(to: shifted(-20, -20), rearContacts: rear))
            XCTAssertNil(swipe.move(to: shifted(-90, -90), rearContacts: 1))
        }
        var swipe = WindowOverviewSwipe()
        swipe.begin(at: fingers)
        XCTAssertNil(swipe.move(to: [fingers[0]], rearContacts: 1))
        XCTAssertNil(swipe.move(to: shifted(-90, -90), rearContacts: 1))
        swipe.begin(at: fingers); swipe.cancel()
        XCTAssertNil(swipe.move(to: shifted(-90, -90), rearContacts: 1))
    }
    func testModeChangeAndLateHoldCannotTurnNextQuickTapIntoContextClick() {
        var sequence = TouchSequence(), state = DirectTouchState()
        sequence.invalidate()
        let oldTimer = sequence.token
        _ = state.begin(at: CGPoint(x: 0.2, y: 0.3), viewPoint: .zero)
        _ = state.longPress()
        sequence.invalidate(); _ = state.cancel() // switch to trackpad
        sequence.invalidate(); _ = state.cancel() // back to direct
        sequence.invalidate()
        let currentTimer = sequence.token
        _ = state.begin(at: CGPoint(x: 0.6, y: 0.7), viewPoint: .zero)
        if sequence.accepts(oldTimer) { _ = state.longPress() }
        XCTAssertFalse(sequence.accepts(oldTimer))
        XCTAssertTrue(sequence.accepts(currentTimer))
        XCTAssertEqual(state.end(clicks: 1), [.init(action: .tap, point: CGPoint(x: 0.6, y: 0.7))])
        sequence.invalidate()
        XCTAssertFalse(sequence.accepts(currentTimer))
    }

    func testLetterboxIsNotInteractiveAndNegativeDisplayOriginMapsCorrectly() {
        let viewport = RemoteViewport(container: CGSize(width: 800, height: 800), content: CGSize(width: 1600, height: 900))
        XCTAssertNil(viewport.normalized(CGPoint(x: 400, y: 100)))
        XCTAssertEqual(viewport.normalized(CGPoint(x: 400, y: 400)), CGPoint(x: 0.5, y: 0.5))
        let edge = DirectTouchEvent(action: .tap, point: CGPoint(x: 1, y: 1))
        XCTAssertEqual(edge.displayPoint(in: CGRect(x: -1600, y: -900, width: 1600, height: 900)), CGPoint(x: -1, y: -1))
    }

    func testZoomKeepsFingerAnchorAndBoundsLocalPanning() {
        var viewport = RemoteViewport(container: CGSize(width: 800, height: 600), content: CGSize(width: 1600, height: 1200))
        let finger = CGPoint(x: 300, y: 220)
        let anchor = viewport.normalized(finger)!
        viewport.magnify(to: 2, anchor: anchor, centroid: finger)
        XCTAssertEqual(viewport.normalized(finger)!.x, anchor.x, accuracy: 0.00001)
        XCTAssertEqual(viewport.normalized(finger)!.y, anchor.y, accuracy: 0.00001)
        viewport.magnify(to: 8, anchor: anchor, centroid: CGPoint(x: 5000, y: 5000))
        XCTAssertEqual(viewport.zoom, 4)
        XCTAssertLessThanOrEqual(viewport.imageRect.minX, 0)
        XCTAssertLessThanOrEqual(viewport.imageRect.minY, 0)
    }

    func testTapIsCommittedOnlyOnLiftAndRetainsDoubleClickCount() {
        var state = DirectTouchState()
        XCTAssertEqual(state.begin(at: CGPoint(x: 0.2, y: 0.3), viewPoint: .zero), [])
        let result = state.end(clicks: 2)
        XCTAssertEqual(result, [.init(action: .tap, point: CGPoint(x: 0.2, y: 0.3), clicks: 2)])
    }

    func testSwipeScrollsAtInitialTargetWithoutPressingOrClicking() {
        var state = DirectTouchState()
        let anchor = CGPoint(x: 0.2, y: 0.3)
        _ = state.begin(at: anchor, viewPoint: .zero)
        let scroll = state.move(to: CGPoint(x: 0.2, y: 0.4), viewPoint: CGPoint(x: 0, y: 20), delta: CGPoint(x: 0, y: 0.1))
        XCTAssertEqual(scroll, [.init(action: .scroll, point: anchor, delta: CGPoint(x: 0, y: 0.1))])
        XCTAssertEqual(state.longPress(), [])
        XCTAssertEqual(state.end(clicks: 1), [])
    }

    func testLongPressOpensContextMenuWithoutTrailingClick() {
        var state = DirectTouchState()
        _ = state.begin(at: CGPoint(x: 0.5, y: 0.5), viewPoint: .zero)
        XCTAssertEqual(state.longPress(), [])
        XCTAssertEqual(state.longPress(), [])
        XCTAssertEqual(state.end(clicks: 1).first?.action, .context)
    }

    func testHoldThenDragSelectsAndReleasesWithoutMenuOrClick() {
        var state = DirectTouchState()
        let anchor = CGPoint(x: 0.2, y: 0.3)
        _ = state.begin(at: anchor, viewPoint: .zero)
        XCTAssertEqual(state.longPress(), [])
        let moved = CGPoint(x: 0.4, y: 0.3)
        XCTAssertEqual(state.move(to: moved, viewPoint: CGPoint(x: 20, y: 0), delta: .zero),
                       [.init(action: .down, point: anchor), .init(action: .move, point: moved)])
        XCTAssertEqual(state.end(clicks: 1), [.init(action: .up, point: moved)])
        XCTAssertEqual(state.cancel(), [])
    }

    func testRearClutchWaitsForFrontPositionAndReleasesExactlyOnce() {
        var state = DirectTouchState()
        XCTAssertEqual(state.setRearHeld(true), [], "No click at an unrelated old Mac cursor location.")
        XCTAssertEqual(state.begin(at: CGPoint(x: 0.4, y: 0.6), viewPoint: .zero).first?.action, .down)
        XCTAssertEqual(state.setRearHeld(true), [])
        XCTAssertEqual(state.end(clicks: 1), [])
        XCTAssertTrue(state.dragging, "Rear clutch remains down while thumb repositions.")
        XCTAssertEqual(state.begin(at: CGPoint(x: 0.45, y: 0.6), viewPoint: .zero).first?.action, .move)
        XCTAssertEqual(state.setRearHeld(false).first?.action, .up)
        XCTAssertEqual(state.end(clicks: 1), [], "No accidental click when rear fingers lift first.")
        XCTAssertEqual(state.cancel(), [])
    }

    func testCancelReleasesDragAndDoesNotProduceTerminalTap() {
        var state = DirectTouchState()
        _ = state.begin(at: CGPoint(x: 0.2, y: 0.4), viewPoint: .zero)
        XCTAssertEqual(state.setRearHeld(true).first?.action, .down)
        XCTAssertEqual(state.cancel().first?.action, .up)
        XCTAssertEqual(state.cancel(), [])
        XCTAssertEqual(state.end(clicks: 1), [])
    }

    func testWireRejectsInvalidCoordinatesAndRoundTripsSemanticScroll() throws {
        let event = DirectTouchEvent(action: .scroll, point: CGPoint(x: 0.5, y: 0.5), delta: CGPoint(x: -0.1, y: 0.2))
        let wire = try JSONDecoder().decode(LANInput.self, from: JSONEncoder().encode(LANInput(direct: event)))
        XCTAssertEqual(wire.directTouch, event)
        var bad = wire; bad.x = .nan; XCTAssertNil(bad.directTouch)
        bad = wire; bad.y = 1.1; XCTAssertNil(bad.directTouch)
        bad = wire; bad.scrollY = .infinity; XCTAssertNil(bad.directTouch)
        bad = wire; bad.clickCount = 3; XCTAssertNil(bad.directTouch)
        bad = wire; bad.action = "touch.exec"; XCTAssertNil(bad.directTouch)
    }
}

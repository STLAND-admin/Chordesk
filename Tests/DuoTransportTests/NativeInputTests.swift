import XCTest
@testable import DuoWorkbench

final class NativeInputTests: XCTestCase {
    func testFloatingCursorAccumulatesMovementAndMovesBothAxes() {
        var gesture = NativeCursorGesture()
        XCTAssertEqual(gesture.move(to: CGPoint(x: 100, y: 100)), [])
        gesture.begin(at: .zero)
        XCTAssertEqual(gesture.move(to: CGPoint(x: 5, y: 10)), [])
        XCTAssertEqual(gesture.move(to: CGPoint(x: 25, y: 29)), ["right", "right", "down"])
        XCTAssertEqual(gesture.move(to: CGPoint(x: 0, y: 0)), ["left", "left", "up"])
        gesture.end()
        XCTAssertEqual(gesture.move(to: CGPoint(x: 100, y: 100)), [])
    }
    func testFloatingCursorBoundsDiscontinuitiesAndRejectsInvalidPositions() {
        var gesture = NativeCursorGesture()
        gesture.begin(at: .zero)
        XCTAssertEqual(gesture.move(to: CGPoint(x: CGFloat.nan, y: 0)), [])
        XCTAssertEqual(gesture.move(to: CGPoint(x: 100_000, y: 100_000)).count, 24)
        gesture.end(); gesture.begin(at: CGPoint(x: 50, y: 50))
        XCTAssertEqual(gesture.move(to: CGPoint(x: 50, y: 50)), [])
        gesture.begin(at: CGPoint(x: CGFloat.infinity, y: 0))
        XCTAssertEqual(gesture.move(to: .zero), [])
    }
    func testKeyboardDoesNotAppearUnderRestingThumbOrHideOnMonitorTap() {
        var state = NativeKeyboardPresentation()
        state.update(wanted: true, frontContacts: 0)
        XCTAssertTrue(state.visible)
        state.update(wanted: true, frontContacts: 1)
        XCTAssertTrue(state.visible)
        state.update(wanted: false, frontContacts: 1)
        XCTAssertFalse(state.visible)
        state.update(wanted: true, frontContacts: 1)
        XCTAssertFalse(state.visible)
        state.update(wanted: true, frontContacts: 0)
        XCTAssertTrue(state.visible)
    }
    func testChineseCompositionNeverSendsPinyinCandidates() {
        var buffer = NativeTextBuffer()
        XCTAssertNil(buffer.update("ni", hasMarkedText: true))
        XCTAssertNil(buffer.update("nihao", hasMarkedText: true))
        let result = buffer.update("你好", hasMarkedText: false)
        XCTAssertEqual(result?.text, "你好")
        XCTAssertEqual(result?.deleteCount, 0)
        XCTAssertNil(buffer.update("你好", hasMarkedText: false))
    }
    func testAutocorrectionReplacesOnlyPreviouslyCommittedSuffix() {
        var buffer = NativeTextBuffer()
        _ = buffer.update("hello teh", hasMarkedText: false)
        let result = buffer.update("hello the ", hasMarkedText: false)
        XCTAssertEqual(result?.deleteCount, 2)
        XCTAssertEqual(result?.text, "he ")
    }
    func testEmojiBackspaceCountsComposedCharacters() {
        var buffer = NativeTextBuffer()
        _ = buffer.update("好👨‍👩‍👧‍👦", hasMarkedText: false)
        let result = buffer.update("好", hasMarkedText: false)
        XCTAssertEqual(result?.deleteCount, 1)
        XCTAssertEqual(result?.text, "")
    }
    func testFocusChangeDiscardsOldCompositionContext() {
        var buffer = NativeTextBuffer()
        _ = buffer.update("旧输入", hasMarkedText: false)
        XCTAssertNil(buffer.update("旧输入pin", hasMarkedText: true))
        buffer.reset()
        let result = buffer.update("新", hasMarkedText: false)
        XCTAssertEqual(result?.deleteCount, 0)
        XCTAssertEqual(result?.text, "新")
    }
    func testBufferAndWireLimits() {
        var buffer = NativeTextBuffer()
        _ = buffer.update(String(repeating: "a", count: 300), hasMarkedText: false)
        XCTAssertEqual(buffer.committed.count, 256)
        XCTAssertFalse(LANTextEdit(deleteCount: 257, text: "").isValid)
        XCTAssertFalse(LANTextEdit(deleteCount: -1, text: "").isValid)
        XCTAssertFalse(LANTextEdit(deleteCount: 0, text: "\0").isValid)
    }
    func testRearPressBetweenFrontMovesChangesScrollIntoDrag() {
        var state = DirectTouchState()
        _ = state.begin(at: CGPoint(x: 0.2, y: 0.3), viewPoint: .zero)
        _ = state.move(to: CGPoint(x: 0.3, y: 0.3), viewPoint: CGPoint(x: 10, y: 0), delta: CGPoint(x: 0.1, y: 0))
        let down = state.setRearHeld(true)
        XCTAssertEqual(down, [.init(action: .down, point: CGPoint(x: 0.3, y: 0.3))])
        XCTAssertEqual(state.move(to: CGPoint(x: 0.4, y: 0.3), viewPoint: CGPoint(x: 20, y: 0), delta: CGPoint(x: 0.1, y: 0)).first?.action, .move)
        XCTAssertEqual(state.setRearHeld(false).first?.action, .up)
        XCTAssertEqual(state.end(clicks: 1), [])
    }
}

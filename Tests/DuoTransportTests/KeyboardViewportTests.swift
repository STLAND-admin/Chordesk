import XCTest
@testable import DuoWorkbench

final class KeyboardViewportTests: XCTestCase {
    func testPortraitDesktopMovesUpWithoutCroppingAndCoordinatesStillMatch() {
        let content = CGSize(width: 1600, height: 900)
        let frame = RemoteKeyboardLayout.frame(container: CGSize(width: 400, height: 800), content: content, keyboardTop: 460)
        XCTAssertEqual(frame, CGRect(x: 0, y: 235, width: 400, height: 225))
        let viewport = RemoteViewport(container: frame.size, content: content)
        XCTAssertEqual(viewport.imageRect, CGRect(origin: .zero, size: frame.size))
        XCTAssertEqual(viewport.normalized(CGPoint(x: 200, y: 112.5)), CGPoint(x: 0.5, y: 0.5))
        XCTAssertEqual(viewport.normalized(CGPoint(x: 400, y: 225)), CGPoint(x: 1, y: 1))
    }
    func testLandscapeLeavesSideMarginsAndTouchesKeyboardTop() {
        let frame = RemoteKeyboardLayout.frame(container: CGSize(width: 900, height: 600), content: CGSize(width: 1600, height: 1000), keyboardTop: 300)
        XCTAssertEqual(frame, CGRect(x: 210, y: 0, width: 480, height: 300))
        XCTAssertEqual(frame.width / frame.height, 1.6)
        XCTAssertEqual(frame.maxY, 300)
    }
    func testHiddenOrDisabledKeyboardRestoresWorkspaceAndCustomFrameConverts() {
        let workspace = CGRect(x: 10, y: 70, width: 900, height: 600)
        XCTAssertEqual(RemoteKeyboardLayout.top(of: CGRect(x: 10, y: 500, width: 900, height: 170), in: workspace), 430)
        XCTAssertNil(RemoteKeyboardLayout.top(of: CGRect(x: 1000, y: 500, width: 200, height: 170), in: workspace))
        XCTAssertNil(RemoteKeyboardLayout.top(of: CGRect(x: 10, y: 670, width: 900, height: 0), in: workspace))
        let content = CGSize(width: 1600, height: 1000)
        XCTAssertEqual(RemoteKeyboardLayout.frame(container: workspace.size, content: content, keyboardTop: nil), CGRect(origin: .zero, size: workspace.size))
        XCTAssertEqual(RemoteKeyboardLayout.frame(container: workspace.size, content: content, keyboardTop: 700), CGRect(origin: .zero, size: workspace.size))
        XCTAssertEqual(RemoteKeyboardLayout.frame(container: workspace.size, content: content, keyboardTop: -100).height, 0)
    }
}

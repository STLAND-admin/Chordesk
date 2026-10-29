import XCTest
@testable import DuoWorkbench

final class ControlsTests: XCTestCase {
    func testMenuSelectionRunsOnceOnlyAfterDismissal() {
        var menu = MenuInteractionState()
        menu.begin()
        XCTAssertTrue(menu.presented)
        XCTAssertNil(menu.select("settings"))
        XCTAssertNil(menu.select("settings"))
        XCTAssertEqual(menu.end(), "settings")
        XCTAssertFalse(menu.presented)
        XCTAssertNil(menu.end())
        menu.begin()
        XCTAssertNil(menu.end(), "Cancelling does not replay the previous action.")
    }
    func testLateNativeActionAfterDismissalIsNotLost() {
        var menu = MenuInteractionState()
        menu.begin(); _ = menu.end()
        XCTAssertEqual(menu.select("guide"), "guide")
    }
    @MainActor
    func testMenuBlocksRearSwitchingUntilFreshContact() {
        let grip = GripInteraction()
        grip.configure(defaultMode: .touchpad, activation: .momentary, trigger: .touch)
        grip.outerContacts(2)
        XCTAssertEqual(grip.state.requestedFrontMode, .trackpad)
        grip.setControlsPresented(true)
        grip.outerContacts(2); grip.gesture(.longPress)
        XCTAssertEqual(grip.state.outerCount, 0)
        XCTAssertEqual(grip.state.requestedFrontMode, .direct)
        grip.setControlsPresented(false)
        XCTAssertEqual(grip.state.requestedFrontMode, .direct)
        grip.outerContacts(2)
        XCTAssertEqual(grip.state.requestedFrontMode, .trackpad)
    }
    func testRailSettingsStayWithinAvailableSpaceForInvalidPersistedValues() {
        XCTAssertEqual(ControlRailPosition.fraction(.nan, maximum: 0.18), 0)
        XCTAssertEqual(ControlRailPosition.fraction(-1, maximum: 0.18), 0)
        XCTAssertEqual(ControlRailPosition.fraction(1, maximum: 0.18), 0.18)
        XCTAssertEqual(ControlRailPosition.fraction(0.12, maximum: 0.18), 0.12)
    }
    func testRightDockCentersBelowSystemRegionWithoutContentSafeAreaInset() {
        XCTAssertEqual(ControlRailPosition.trailingInset(containerWidth: 1000, anchorX: 965, buttonWidth: 50), 10)
        XCTAssertEqual(ControlRailPosition.trailingInset(containerWidth: 600, anchorX: 570, buttonWidth: 60), 0)
        XCTAssertEqual(ControlRailPosition.trailingInset(containerWidth: 600, anchorX: nil, buttonWidth: 60), 0)
        XCTAssertEqual(ControlRailPosition.trailingInset(containerWidth: 600, anchorX: .nan, buttonWidth: 60), 0)
    }
}

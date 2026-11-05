import XCTest
@testable import ChordeskHost

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
    func testExplicitBarRegionWinsOverContentSafeAreaEstimate() {
        let bounds = CGRect(x: 0, y: 0, width: 951, height: 669)
        let systemBar = CGRect(x: 881, y: 124, width: 44, height: 511)
        let column = ControlRailPosition.column(in: bounds, barRegion: systemBar, margin: 0, preferredWidth: 44)
        XCTAssertEqual(column, systemBar)
        XCTAssertEqual(column.midX, 903)
        // The old midpoint of the 84-point content safe-area strip was 909.
        XCTAssertNotEqual(column.midX, (867 + bounds.maxX) / 2)
        let shifted = ControlRailPosition.column(in: bounds.offsetBy(dx: 100, dy: 20),
            barRegion: systemBar.offsetBy(dx: 100, dy: 20), margin: 0, preferredWidth: 44)
        XCTAssertEqual(shifted.midX, column.midX + 100)
        XCTAssertEqual(shifted.width, column.width)
    }
    func testHorizontalStatusBarUsesSystemMarginsRatherThanWindowMidpoint() {
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 800)
        let column = ControlRailPosition.column(in: bounds, barRegion: nil,
                                               margin: 16, preferredWidth: 44)
        XCTAssertEqual(column.midX, 362)
        XCTAssertEqual(column.width, 44)
    }

    func testNativeColumnCannotExtendIntoHorizontalSystemBars() {
        let usable = CGRect(x: 0, y: 62, width: 430, height: 836)
        let native = CGRect(x: 370, y: 0, width: 44, height: 932)
        let result = ControlRailPosition.column(in: usable, barRegion: native, margin: 16, preferredWidth: 44)
        XCTAssertEqual(result.minY, usable.minY)
        XCTAssertEqual(result.maxY, usable.maxY)
        XCTAssertEqual(result.midX, native.midX)
        XCTAssertEqual(result.width, native.width)
    }

    func testNativeColumnOutsideVisibleVerticalSpaceUsesFallback() {
        let usable = CGRect(x: 0, y: 62, width: 430, height: 836)
        let result = ControlRailPosition.column(in: usable,
            barRegion: CGRect(x: 370, y: -100, width: 44, height: 20), margin: 16, preferredWidth: 44)
        XCTAssertEqual(result.minY, usable.minY)
        XCTAssertEqual(result.maxY, usable.maxY)
        XCTAssertEqual(result.maxX, usable.maxX - 16)
    }

}

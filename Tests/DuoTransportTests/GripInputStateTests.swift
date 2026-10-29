import XCTest
@testable import DuoWorkbench

final class GripInputStateTests: XCTestCase {
    func testOneRearFingerIsReservedForWindowChordAndNeverSwitchesOrClicks() {
        var grip = GripInputState()
        _ = grip.configure(defaultMode: .touchpad, activation: .momentary, trigger: .touch)
        XCTAssertEqual(grip.outerContacts(1), [])
        XCTAssertEqual(grip.requestedFrontMode, .direct)
        grip.gesture(.longPress, fingers: 1)
        XCTAssertEqual(grip.requestedFrontMode, .direct)
        _ = grip.configure(defaultMode: .touchpad, activation: .toggle, trigger: .touch)
        grip.gesture(.tap, fingers: 1)
        XCTAssertEqual(grip.requestedFrontMode, .direct)
    }
    func testRearContactOnlySwitchesPointerModeAndNeverPressesMouse() {
        var grip = GripInputState()
        _ = grip.configure(defaultMode: .touchpad, activation: .momentary, trigger: .touch)
        XCTAssertEqual(grip.outerContacts(2), [])
        XCTAssertEqual(grip.requestedFrontMode, .trackpad)
        XCTAssertEqual(grip.requestedMode, .touchpad)
        XCTAssertEqual(grip.outerContacts(2), [])
        XCTAssertFalse(grip.buttonHeld)
        XCTAssertEqual(grip.outerContacts(0), [])
        XCTAssertEqual(grip.requestedFrontMode, .direct)
    }
    func testLongPressSwitchWaitsThenRestoresWithoutOpeningKeyboard() {
        var grip = GripInputState()
        _ = grip.outerContacts(2)
        XCTAssertEqual(grip.requestedFrontMode, .direct)
        grip.gesture(.longPress)
        XCTAssertEqual(grip.requestedFrontMode, .trackpad)
        _ = grip.outerContacts(0)
        XCTAssertEqual(grip.requestedFrontMode, .direct)
        XCTAssertEqual(grip.requestedMode, .touchpad)
    }
    func testTogglePersistsAfterLiftAndSecondTriggerRestores() {
        var grip = GripInputState()
        _ = grip.configure(defaultMode: .keyboard, activation: .toggle, trigger: .touch)
        _ = grip.outerContacts(2); grip.gesture(.tap); _ = grip.outerContacts(0)
        XCTAssertEqual(grip.requestedFrontMode, .trackpad)
        XCTAssertEqual(grip.requestedMode, .keyboard)
        _ = grip.outerContacts(2); grip.gesture(.tap); _ = grip.outerContacts(0)
        XCTAssertEqual(grip.requestedFrontMode, .direct)
    }
    func testAddingRearFingersDoesNotToggleOrGenerateMouseEvents() {
        var grip = GripInputState()
        _ = grip.configure(defaultMode: .touchpad, activation: .toggle, trigger: .longPress)
        XCTAssertEqual(grip.outerContacts(2), [])
        grip.gesture(.longPress)
        for count in [2, 3, 1, 0] { XCTAssertEqual(grip.outerContacts(count), []) }
        XCTAssertEqual(grip.requestedFrontMode, .trackpad)
        XCTAssertFalse(grip.buttonHeld)
    }
    func testFrontOwnsDragAndCancellationReleasesOnce() {
        var grip = GripInputState()
        XCTAssertEqual(grip.route(.dragBegan), [.dragBegan])
        XCTAssertEqual(grip.route(.dragMoved(dx: 0.1, dy: 0)), [.dragMoved(dx: 0.1, dy: 0)])
        XCTAssertEqual(grip.cancel(), [.dragEnded])
        XCTAssertEqual(grip.cancel(), [])
    }
    func testKeyboardDoesNotResetLatchedPointerMode() {
        var grip = GripInputState()
        _ = grip.configure(defaultMode: .touchpad, activation: .toggle, trigger: .touch)
        _ = grip.outerContacts(2); grip.gesture(.tap); _ = grip.outerContacts(0)
        _ = grip.configure(defaultMode: .keyboard, activation: .toggle, trigger: .touch)
        XCTAssertEqual(grip.requestedFrontMode, .trackpad)
        XCTAssertEqual(grip.requestedMode, .keyboard)
    }
    func testSwitchUnderRestingFrontFingerSuppressesClickUntilLift() {
        var grip = GripInputState()
        _ = grip.configure(defaultMode: .touchpad, activation: .momentary, trigger: .touch)
        grip.innerContacts(1); _ = grip.outerContacts(2)
        XCTAssertEqual(grip.route(.leftClick), [])
        grip.innerContacts(0); grip.innerContacts(1)
        XCTAssertEqual(grip.route(.leftClick), [.leftClick])
    }
}

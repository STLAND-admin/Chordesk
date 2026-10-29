import XCTest
@testable import DuoWorkbench

final class MobileKeyboardTests: XCTestCase {
    func testPageSwitchesAreLocalAndSpaceReturnsToAlphabet() {
        var state = MobileKeyboardState()
        XCTAssertNil(state.press("page-numbers"))
        XCTAssertEqual(state.press("3"), .text("3"))
        XCTAssertNil(state.press("page-symbols"))
        XCTAssertEqual(state.press("€"), .text("€"))
        XCTAssertEqual(state.press("space"), .text(" "))
        XCTAssertEqual(state.page, .alphabet)
        XCTAssertEqual(state.press("q"), .text("q"))
        XCTAssertNil(state.press("not-a-key"))
    }
    func testShiftIsOneShotAndQuickDoubleTapLocksUntilToggled() {
        var state = MobileKeyboardState()
        XCTAssertNil(state.press("shift", now: 1))
        XCTAssertEqual(state.press("a", now: 2), .text("A"))
        XCTAssertEqual(state.press("b", now: 3), .text("b"))
        _ = state.press("shift", now: 4); _ = state.press("shift", now: 4.2)
        XCTAssertEqual(state.shift, .locked)
        XCTAssertEqual(state.press("c"), .text("C"))
        XCTAssertEqual(state.press("d"), .text("D"))
        _ = state.press("shift", now: 6)
        XCTAssertEqual(state.press("e"), .text("e"))
    }
    func testAllDisplayedSymbolsSendExactTextWithoutMacKeyMapping() {
        for page in ["page-numbers", "page-symbols"] {
            var state = MobileKeyboardState(); _ = state.press(page)
            let keys = state.rows.flatMap { $0 }.filter { $0.id.count == 1 }
            for key in keys { XCTAssertEqual(state.press(key.id), .text(key.title)) }
            XCTAssertEqual(state.press("delete"), .key("delete"))
            XCTAssertEqual(state.press("return"), .key("return"))
            XCTAssertEqual(state.page, .alphabet)
        }
    }
    func testModifierShortcutUsesShiftForDisplayedPunctuation() {
        var modifiers = ShortcutModifiers(); modifiers.toggle(2)
        let shortcut = modifiers.shortcut(for: "+")
        XCTAssertEqual(shortcut?.key, "=")
        XCTAssertEqual(shortcut?.flags, 3)
        XCTAssertEqual(modifiers.flags, 0)
    }
    func testLegacyCustomPreferenceKeepsWorkingWithNewMobileLayout() {
        XCTAssertEqual(PhoneKeyboardStyle(rawValue: "desktop"), .mobile)
    }
}

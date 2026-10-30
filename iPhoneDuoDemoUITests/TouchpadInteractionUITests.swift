import XCTest

final class TouchpadInteractionUITests: XCTestCase {
    @MainActor
    private func launchFixture() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["DUO_UI_FIXTURE"] = "1"
        app.launchArguments += ["-phoneKeyboardStyle", "system", "-controlRailTopV1", "0", "-controlRailBottomV1", "0"]
        app.launchEnvironment["DUO_UI_LIVE_FRAMES"] = "1"
        app.launch()
        return app
    }

    @MainActor
    func testPointerButtonSwitchesWithShortTapAndCanBeHidden() {
        let app = launchFixture()
        shortPress(app.buttons["remote-options"]); shortPressMenuItem("键盘、画质与触控设置", in: app)
        let option = app.switches["show-pointer-mode-button"]
        reveal(option, in: app.collectionViews.firstMatch)
        if option.value as? String != "1" { option.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).press(forDuration: 0.05) }
        XCTAssertEqual(option.value as? String, "1")
        shortPress(app.buttons["完成"])
        let toggle = app.buttons["pointer-mode-toggle"], display = app.buttons["display-dock-button"], menu = app.buttons["remote-options"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.frame.midX, menu.frame.midX, accuracy: 2)
        XCTAssertEqual(display.frame.midX, menu.frame.midX, accuracy: 2)
        XCTAssertEqual(app.buttons["keyboard-dock-toggle"].frame.midX, menu.frame.midX, accuracy: 2)
        XCTAssertGreaterThan(toggle.frame.minY, menu.frame.maxY)
        XCTAssertGreaterThan(display.frame.minY, toggle.frame.maxY)
        let original = toggle.label
        shortPress(toggle)
        XCTAssertNotEqual(toggle.label, original)
        shortPress(toggle)
        XCTAssertEqual(toggle.label, original)
        shortPress(display)
        XCTAssertTrue(app.buttons["完成"].waitForExistence(timeout: 5))
        shortPress(app.buttons["完成"])
        shortPress(menu); shortPressMenuItem("键盘、画质与触控设置", in: app)
        reveal(option, in: app.collectionViews.firstMatch)
        option.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).press(forDuration: 0.05)
        XCTAssertEqual(option.value as? String, "0")
        shortPress(app.buttons["完成"])
        XCTAssertTrue(toggle.waitForNonExistence(timeout: 5))
        XCTAssertTrue(display.exists && menu.exists)
    }

    @MainActor
    func testMultiplePairedMacsAreListedSeparately() {
        let app = XCUIApplication()
        app.launchEnvironment["DUO_UI_FIXTURE"] = "1"
        app.launchEnvironment["DUO_UI_PAIRED_MACS"] = "1"
        app.launchEnvironment["DUO_UI_LIVE_FRAMES"] = "1"
        app.launch()
        shortPress(app.buttons["remote-options"]); shortPressMenuItem("连接 Mac", in: app)
        XCTAssertTrue(app.buttons["我的 Mac"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["同学的 Mac"].exists)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "lan-reconnect-")).count, 2)
        // The UI fixture never authenticates or writes credentials to a real host.
    }

    @MainActor
    func testForgetMacDoesNotConnectAndOnlyDeletesConfirmedHost() {
        let app = XCUIApplication()
        app.launchEnvironment["DUO_UI_FIXTURE"] = "1"
        app.launchEnvironment["DUO_UI_PAIRED_MACS"] = "1"
        app.launchEnvironment["DUO_UI_LIVE_FRAMES"] = "1"
        app.launch()
        shortPress(app.buttons["remote-options"]); shortPressMenuItem("连接 Mac", in: app)
        let forget = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "lan-forget-")).firstMatch
        XCTAssertTrue(forget.waitForExistence(timeout: 5))
        shortPress(forget)
        XCTAssertTrue(app.buttons["忘记"].waitForExistence(timeout: 5))
        shortPress(app.buttons["取消"])
        XCTAssertTrue(app.navigationBars["连接 Mac"].exists, "Forget must not invoke connect/dismiss.")
        XCTAssertTrue(app.buttons["我的 Mac"].exists && app.buttons["同学的 Mac"].exists)
        shortPress(forget); shortPress(app.buttons["忘记"])
        XCTAssertTrue(app.buttons["我的 Mac"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["同学的 Mac"].exists)
        XCTAssertTrue(app.navigationBars["连接 Mac"].exists)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "lan-reconnect-")).count, 1)
    }

    @MainActor
    func testRearRegionEditorMovesResizesAndSticksToEdge() {
        let app = launchFixture()
        shortPress(app.buttons["remote-options"]); shortPressMenuItem("相机背面切换", in: app)
        XCTAssertTrue(app.buttons["camera-control-done"].waitForExistence(timeout: 5))
        let link = app.buttons["rear-area-editor-link"]
        reveal(link, in: app.collectionViews.firstMatch)
        shortPress(link)
        let canvas = app.otherElements["rear-area-canvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        let centerPreset = app.buttons["居中"]
        reveal(centerPreset, in: app.collectionViews.firstMatch); shortPress(centerPreset)
        for _ in 0..<8 where !canvas.exists { app.collectionViews.firstMatch.swipeDown() }
        reveal(canvas, in: app.collectionViews.firstMatch)
        let box = app.descendants(matching: .any).matching(identifier: "rear-area-move").firstMatch
        XCTAssertTrue(box.exists)
        let originalBox = box.frame, originalValue = box.value as? String
        let origin = box.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        origin.press(forDuration: 0.1, thenDragTo: origin.withOffset(CGVector(dx: -25, dy: -15)))
        XCTAssertNotEqual(box.value as? String, originalValue)
        XCTAssertEqual(box.frame.width, originalBox.width, accuracy: 2)
        XCTAssertEqual(box.frame.height, originalBox.height, accuracy: 2)
        let corner = app.images["rear-area-bottomRight"]
        XCTAssertTrue(corner.isHittable)
        let beforeResize = box.frame
        let cornerPoint = corner.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        cornerPoint.press(forDuration: 0.1, thenDragTo: cornerPoint.withOffset(CGVector(dx: -30, dy: -20)))
        XCTAssertLessThan(box.frame.width, beforeResize.width - 10)
        XCTAssertLessThan(box.frame.height, beforeResize.height - 10)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Chordesk adjustable rear region"; shot.lifetime = .keepAlways; add(shot)
        let edgePreset = app.buttons["rear-area-left"]
        reveal(edgePreset, in: app.collectionViews.firstMatch)
        shortPress(edgePreset)
        let summary = app.staticTexts["rear-area-summary"]
        XCTAssertTrue(summary.label.contains("X 0%")); XCTAssertTrue(summary.label.contains("宽 50%"))
        XCTAssertTrue(summary.label.contains("高 100%"))
    }

    @MainActor
    private func shortPress(_ item: XCUIElement) {
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        XCTAssertTrue(item.isHittable)
        // Deliberately below every long-press threshold; do not rely on accessibility activation.
        item.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.05)
    }

    @MainActor
    private func reveal(_ item: XCUIElement, in scroll: XCUIElement) {
        XCTAssertTrue(scroll.waitForExistence(timeout: 5))
        for _ in 0..<12 {
            if item.exists {
                let rect = scroll.frame, middle = item.frame.midY
                if middle > rect.minY + rect.height * 0.2 && middle < rect.maxY - rect.height * 0.2 && item.isHittable { return }
                let delta = max(-0.3, min(0.3, (middle - rect.midY) / max(1, rect.height)))
                scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                    .press(forDuration: 0.05, thenDragTo: scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5 - delta)))
            } else { scroll.swipeUp() }
        }
    }

    @MainActor
    private func shortPressMenuItem(_ title: String, in app: XCUIApplication) {
        let list = app.tables["remote-action-list"]
        XCTAssertTrue(list.waitForExistence(timeout: 5))
        let item = list.descendants(matching: .any).matching(NSPredicate(format: "label == %@", title)).firstMatch
        reveal(item, in: list)
        if !item.exists { print(app.debugDescription) }
        shortPress(item)
    }

    @MainActor
    func testMicrophoneDefaultsOffAndLegacyHostCannotStartIt() {
        let app = launchFixture()
        XCTAssertFalse(app.buttons["remote-microphone-live"].exists)
        shortPress(app.buttons["remote-options"])
        shortPressMenuItem("键盘、画质与触控设置", in: app)
        XCTAssertTrue(app.sliders["control-rail-top"].waitForExistence(timeout: 5))
        let automatic = app.switches["remote-microphone-autostart"]
        for _ in 0..<12 where !automatic.isHittable { app.collectionViews.firstMatch.swipeUp() }
        XCTAssertTrue(automatic.exists)
        XCTAssertEqual(automatic.value as? String, "0")
        let current = app.switches["remote-microphone-toggle"]
        if !current.exists {
            let form = app.collectionViews.firstMatch
            form.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
                .press(forDuration: 0.1, thenDragTo: form.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.65)))
        }
        XCTAssertEqual(current.value as? String, "0")
        XCTAssertFalse(current.isEnabled)
        XCTAssertFalse(app.buttons["remote-microphone-live"].exists)
    }

    @MainActor
    func testFullscreenControlsAndRearSwitchGuide() {
        let app = launchFixture()
        XCTAssertTrue(app.buttons["remote-options"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars.element.exists, "Desktop is no longer inset by a title/menu bar.")
        app.buttons["remote-options"].tap()
        shortPressMenuItem("相机背面切换", in: app)
        XCTAssertTrue(app.buttons["camera-mode-front-touch"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["camera-mode-direct"].exists)
        app.buttons["camera-control-done"].tap()
        app.buttons["remote-options"].tap()
        shortPressMenuItem("Duo 操作手册", in: app)
        XCTAssertTrue(app.navigationBars["Duo 操作手册"].waitForExistence(timeout: 5))
        let rearGuide = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "背面不直接移动")).firstMatch
        reveal(rearGuide, in: app.collectionViews.firstMatch)
        if !rearGuide.exists { print(app.debugDescription) }
        XCTAssertTrue(rearGuide.exists)
    }

    @MainActor
    func testNativeModifierBarIsVisibleAndOneShot() {
        let app = launchFixture()
        let keyboard = app.buttons["keyboard-dock-toggle"]
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5))
        keyboard.tap()
        let command = app.buttons["native-modifier-2"]
        XCTAssertTrue(command.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["native-modifier-8"].exists)
        XCTAssertTrue(app.buttons["native-modifier-4"].exists)
        XCTAssertFalse(app.textViews["native-remote-input"].exists)
        command.tap()
        XCTAssertTrue((command.value as? String)?.contains("已按下") == true)
        app.keys["a"].tap()
        expectation(for: NSPredicate(format: "value == %@", "未按下"), evaluatedWith: command)
        waitForExpectations(timeout: 3)
        keyboard.press(forDuration: 0.8)
        shortPressMenuItem("收起键盘", in: app)
        XCTAssertFalse(command.exists)
    }

    @MainActor
    func testMagnifierPreferenceAndPointerModePersist() {
        let app = launchFixture()
        app.buttons["remote-options"].tap(); shortPressMenuItem("键盘、画质与触控设置", in: app)
        let picker = app.segmentedControls["front-touch-mode"]
        for _ in 0..<6 where !picker.buttons["直接触屏"].isHittable { app.swipeUp() }
        picker.buttons["直接触屏"].tap()
        let magnifier = app.switches["touch-magnifier-toggle"]
        for _ in 0..<5 where !magnifier.isHittable { app.swipeUp() }
        XCTAssertTrue(magnifier.exists)
        let before = magnifier.value as? String
        magnifier.tap()
        let after = magnifier.value as? String
        XCTAssertNotEqual(before, after)
        app.terminate(); app.launch()
        app.buttons["remote-options"].tap(); shortPressMenuItem("键盘、画质与触控设置", in: app)
        for _ in 0..<6 where !magnifier.isHittable { app.swipeUp() }
        XCTAssertEqual(magnifier.value as? String, after)
        magnifier.tap()
    }

    @MainActor
    func testMenuActionsOpenOnFirstSelectionAndControlsStayAligned() {
        let app = launchFixture()
        let menu = app.buttons["remote-options"], keyboard = app.buttons["keyboard-dock-toggle"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        XCTAssertEqual(menu.frame.maxX, keyboard.frame.maxX, accuracy: 2)
        XCTAssertEqual(menu.frame.width, menu.frame.height, accuracy: 1)
        XCTAssertEqual(keyboard.frame.width, keyboard.frame.height, accuracy: 1)
        for attempt in 0..<3 {
            shortPress(menu)
            if attempt == 0 {
                XCTAssertTrue(app.tables["remote-action-list"].waitForExistence(timeout: 5))
                let glass = XCTAttachment(screenshot: app.screenshot())
                glass.name = "Glass menu with short-tap rows"; glass.lifetime = .keepAlways; add(glass)
            }
            XCTAssertFalse(app.buttons["显示键盘"].exists)
            shortPressMenuItem("键盘、画质与触控设置", in: app)
            XCTAssertTrue(app.sliders["control-rail-top"].waitForExistence(timeout: 5))
            app.buttons["完成"].tap()
        }
        keyboard.tap()
        XCTAssertTrue(app.buttons["native-modifier-2"].waitForExistence(timeout: 8))
        XCTAssertEqual(menu.frame.maxX, keyboard.frame.maxX, accuracy: 2)
        XCTAssertLessThanOrEqual(app.buttons["native-modifier-2"].frame.maxX, keyboard.frame.minX)
        shortPress(menu)
        shortPressMenuItem("Duo 操作手册", in: app)
        XCTAssertTrue(app.navigationBars["Duo 操作手册"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testPhoneKeyboardPagesAndRightDockDoNotOverlap() {
        let app = launchFixture()
        let keyboard = app.buttons["keyboard-dock-toggle"]
        shortPress(keyboard)
        keyboard.press(forDuration: 0.8)
        shortPressMenuItem("手机布局 · 可调", in: app)
        let q = app.buttons["mobile-key-q"]
        XCTAssertTrue(q.waitForExistence(timeout: 5))
        XCTAssertFalse(app.keyboards.element.exists)
        let menu = app.buttons["remote-options"]
        XCTAssertEqual(menu.frame.maxX, keyboard.frame.maxX, accuracy: 2)
        XCTAssertGreaterThan(keyboard.frame.midX, app.windows.firstMatch.frame.width * 0.9)
        XCTAssertLessThanOrEqual(app.buttons["mobile-key-return"].frame.maxX, app.buttons["native-modifier-2"].frame.minX + 2)
        shortPress(app.buttons["native-modifier-2"])
        shortPress(app.buttons["mobile-key-a"])
        XCTAssertEqual(app.buttons["native-modifier-2"].value as? String, "未按下")
        shortPress(app.buttons["mobile-key-page-numbers"])
        shortPress(app.buttons["mobile-key-3"])
        shortPress(app.buttons["mobile-key-page-symbols"])
        XCTAssertTrue(app.buttons["mobile-key-€"].exists)
        shortPress(app.buttons["mobile-key-€"])
        shortPress(app.buttons["mobile-key-page-alphabet"])
        XCTAssertTrue(q.exists)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "ChordRemote phone keyboard and edge dock"; shot.lifetime = .keepAlways; add(shot)
        shortPress(keyboard)
        XCTAssertTrue(q.waitForNonExistence(timeout: 5))
    }

    @MainActor
    func testShortMenuSelectionAfterCancelAndKeyboardShortcut() {
        let app = launchFixture()
        let menu = app.buttons["remote-options"], keyboard = app.buttons["keyboard-dock-toggle"]
        shortPress(menu)
        shortPress(app.buttons["完成"])
        XCTAssertTrue(app.tables["remote-action-list"].waitForNonExistence(timeout: 5))
        shortPress(menu)
        shortPressMenuItem("选字放大镜", in: app)
        XCTAssertTrue(app.tables["remote-action-list"].waitForNonExistence(timeout: 5))
        shortPress(keyboard)
        XCTAssertTrue(app.buttons["native-modifier-2"].waitForExistence(timeout: 8))
        keyboard.press(forDuration: 0.8)
        shortPressMenuItem("Esc", in: app)
        XCTAssertTrue(app.tables["remote-action-list"].waitForNonExistence(timeout: 5))
        shortPress(menu)
        shortPressMenuItem("诊断信息", in: app)
        XCTAssertTrue(app.navigationBars["诊断信息"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testEdgeDockAndIndependentRearBadgeAfterKeyboardInput() {
        let app = launchFixture()
        let menu = app.buttons["remote-options"], keyboard = app.buttons["keyboard-dock-toggle"]
        let badge = app.buttons["rear-status-badge"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        let originalBadge = badge.frame
        XCTAssertLessThanOrEqual(badge.frame.maxY, app.images["lan-remote-monitor"].frame.minY + 1,
                                 "The rear lights must not cover desktop pixels.")
        XCTAssertGreaterThan(menu.frame.midX, app.windows.firstMatch.frame.width * 0.9)
        XCTAssertEqual(menu.frame.midX, keyboard.frame.midX, accuracy: 2)
        XCTAssertLessThan(badge.frame.midX, menu.frame.midX)
        shortPress(keyboard)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 8))
        app.typeText("duo")
        shortPress(keyboard)
        shortPress(menu)
        shortPressMenuItem("键盘、画质与触控设置", in: app)
        app.sliders["control-rail-top"].adjust(toNormalizedSliderPosition: 1)
        shortPress(app.buttons["完成"])
        XCTAssertEqual(badge.frame.minX, originalBadge.minX, accuracy: 2)
        XCTAssertEqual(badge.frame.minY, originalBadge.minY, accuracy: 2)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Chordesk edge Dock and stationary rear badge"; shot.lifetime = .keepAlways; add(shot)
        shortPress(menu)
        shortPressMenuItem("Duo 操作手册", in: app)
        XCTAssertTrue(app.navigationBars["Duo 操作手册"].waitForExistence(timeout: 5))
    }
}

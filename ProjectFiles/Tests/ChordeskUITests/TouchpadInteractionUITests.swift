import XCTest

final class TouchpadInteractionUITests: XCTestCase {
    @MainActor
    func testIndependentStreamSettings() {
        let app = XCUIApplication()
        app.launchEnvironment["DUO_UI_FIXTURE"] = "1"
        app.launchEnvironment["DUO_UI_STREAM_SETTINGS"] = "1"
        app.launch()
        shortPress(app.buttons["remote-options"])
        shortPressMenuItem("远程传输画质设置", in: app)
        let resolution = app.buttons["stream-resolution"], fps = app.buttons["stream-fps"]
        reveal(resolution, in: app.collectionViews.firstMatch)
        shortPress(resolution)
        shortPress(app.buttons["1080p"])
        XCTAssertTrue(resolution.label.contains("1080p") || (resolution.value as? String)?.contains("1080p") == true)
        reveal(fps, in: app.collectionViews.firstMatch)
        shortPress(fps); shortPress(app.buttons["60 fps"])
        XCTAssertTrue(fps.label.contains("60 fps") || (fps.value as? String)?.contains("60 fps") == true)
        XCTAssertTrue(resolution.label.contains("1080p") || (resolution.value as? String)?.contains("1080p") == true)
        let bitrate = app.sliders["stream-bitrate"]
        reveal(bitrate, in: app.collectionViews.firstMatch)
        XCTAssertTrue(bitrate.exists)
        bitrate.adjust(toNormalizedSliderPosition: 0.05)
        reveal(fps, in: app.collectionViews.firstMatch)
        XCTAssertTrue(fps.label.contains("60 fps") || (fps.value as? String)?.contains("60 fps") == true)
        XCTAssertTrue(resolution.label.contains("1080p") || (resolution.value as? String)?.contains("1080p") == true)
    }
    @MainActor
    func testKeyboardLetterboxAcceptsRelativeInputButRailDoesNot() {
        let app = XCUIApplication()
        app.launchEnvironment["DUO_UI_FIXTURE"] = "1"
        app.launchEnvironment["DUO_UI_KEYBOARD_LAYOUT"] = "1"
        app.launchEnvironment["DUO_UI_TALL_REMOTE"] = "1"
        app.launchArguments += ["-phoneKeyboardStyle", "system", "-keyboardInvocationV1", "manual", "-primaryPointerMode", "trackpad", "-showStreamMetadataV1", "YES", "-controlRailTopV1", "0", "-showPointerModeButtonV1", "YES"]
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        app.launch()
        shortPress(app.buttons["keyboard-dock-toggle"])
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 8))
        let surface = app.otherElements["grip-front-touchpad"], monitor = app.images["lan-remote-monitor"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            surface.exists && monitor.exists && surface.frame.minX + 20 < monitor.frame.minX
                && surface.frame.maxY <= app.keyboards.firstMatch.frame.minY + 2
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 8), .completed,
            "surface=\(surface.frame) picture=\(monitor.frame)")
        let counter = app.staticTexts["stream-metadata"]
        let before = counter.value as? String
        let origin = surface.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
            .withOffset(CGVector(dx: 12, dy: surface.frame.height * 0.4))
        origin.press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: 20, dy: 45)))
        let sent = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in (counter.value as? String) != before }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [sent], timeout: 3), .completed)
        let rail = app.buttons["remote-options"]
        XCTAssertLessThanOrEqual(surface.frame.maxX, rail.frame.minX + 2)
        // Use the gap between shortcuts, not a button that intentionally sends input.
        let mode = app.segmentedControls["pointer-mode-toggle"]
        let gap = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: rail.frame.midX, dy: mode.frame.maxY + 12))
        let after = counter.value as? String
        gap.press(forDuration: 0.05)
        XCTAssertEqual(counter.value as? String, after)
        XCTAssertTrue(app.keyboards.firstMatch.exists)
    }

    @MainActor
    func testNativeRailStaysRightAndModeFollowsShortTapAcrossOrientations() {
        let app = XCUIApplication()
        app.launchEnvironment["DUO_UI_FIXTURE"] = "1"
        app.launchEnvironment["DUO_UI_RESET_CONTROLS"] = "1"
        app.launchArguments = ["-primaryPointerMode", "direct", "-phoneKeyboardStyle", "system", "-keyboardInvocationV1", "manual"]
        app.launch()
        defer { XCUIDevice.shared.orientation = .portrait }
        for orientation in [UIDeviceOrientation.landscapeLeft, .portrait] {
            XCUIDevice.shared.orientation = orientation
            let menu = app.buttons["remote-options"], keyboard = app.buttons["keyboard-dock-toggle"]
            let mode = app.segmentedControls["pointer-mode-toggle"]
            XCTAssertTrue(menu.waitForExistence(timeout: 5))
            XCTAssertTrue(mode.exists)
            XCTAssertGreaterThan(menu.frame.midX, app.frame.midX)
            XCTAssertEqual(menu.frame.midX, keyboard.frame.midX, accuracy: 2)
            XCTAssertEqual(menu.frame.midX, mode.frame.midX, accuracy: 2)
            let metrics = app.otherElements["rail-layout-metrics"].value as? String ?? ""
            let fields = Dictionary(uniqueKeysWithValues: metrics.split(separator: ";").compactMap { part -> (String, Double)? in
                let pair = part.split(separator: "=")
                guard pair.count == 2, let value = Double(pair[1]) else { return nil }
                return (String(pair[0]), value)
            })
            XCTAssertEqual(menu.frame.midX, fields["barX"] ?? -1, accuracy: 1)
            XCTAssertEqual(menu.frame.width, fields["barWidth"] ?? -1, accuracy: 1)
            XCTAssertGreaterThan(mode.frame.minY, app.buttons["overview-dock-button"].frame.maxY)
            XCTAssertEqual(menu.frame.width, keyboard.frame.width, accuracy: 1)
            XCTAssertEqual(menu.frame.width, mode.frame.width, accuracy: 1)
            let upper = mode.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
            upper.press(forDuration: 0.05)
            XCTAssertTrue(app.otherElements["grip-front-touchpad"].waitForExistence(timeout: 3))
            mode.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)).press(forDuration: 0.3,
                thenDragTo: mode.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75)))
            XCTAssertTrue(app.otherElements["direct-remote-touch"].waitForExistence(timeout: 3))
        }
    }

    @MainActor
    func testFourCategoriesShortcutEditingAndDiagnosticVisibility() {
        let app = XCUIApplication()
        app.launchEnvironment["DUO_UI_FIXTURE"] = "1"
        app.launchEnvironment["DUO_UI_RESET_CONTROLS"] = "1"
        app.launch()
        app.launchEnvironment.removeValue(forKey: "DUO_UI_RESET_CONTROLS")
        XCTAssertTrue(app.segmentedControls["pointer-mode-toggle"].waitForExistence(timeout: 5))
        for id in ["display-dock-button", "overview-dock-button"] {
            XCTAssertTrue(app.buttons[id].waitForExistence(timeout: 5))
        }
        shortPress(app.buttons["remote-options"])
        for title in ["快捷键设置", "背屏控制设置", "远程传输画质设置", "辅助功能设置"] {
            XCTAssertTrue(app.tables["remote-action-list"].staticTexts[title].exists)
        }
        shortPressMenuItem("快捷键设置", in: app)
        for id in ["show-display-button", "show-pointer-mode-button", "show-overview-button"] {
            let toggle = app.switches[id]
            XCTAssertEqual(toggle.value as? String, "1")
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()
        }
        shortPress(app.buttons["完成"])
        XCTAssertFalse(app.segmentedControls["pointer-mode-toggle"].exists)
        for id in ["display-dock-button", "overview-dock-button"] { XCTAssertFalse(app.buttons[id].exists) }
        shortPress(app.buttons["remote-options"]); shortPressMenuItem("诊断信息", in: app)
        let metadata = app.switches["show-stream-metadata"]
        if metadata.value as? String == "1" { metadata.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap() }
        XCTAssertEqual(metadata.value as? String, "0")
        shortPress(app.buttons["完成"])
        XCTAssertFalse(app.staticTexts["stream-metadata"].exists)
        app.terminate(); app.launch()
        XCTAssertFalse(app.buttons["overview-dock-button"].exists)
        XCTAssertFalse(app.staticTexts["stream-metadata"].exists)
        shortPress(app.buttons["remote-options"]); shortPressMenuItem("Duo 操作手册", in: app)
        XCTAssertTrue(app.staticTexts["0 指背屏（直接触控 · 默认）"].exists)
        XCTAssertTrue(app.staticTexts["1 指按住背屏（直接触控）"].exists)
    }

    @MainActor
    func testVideoCodecChoicesUseShortTapsAndPersist() {
        let app = launchFixture()
        func openCodecChoices() {
            shortPress(app.buttons["remote-options"])
            shortPressMenuItem("远程传输画质设置", in: app)
            let picker = app.buttons["video-codec-picker"]
            reveal(picker, in: app.collectionViews.firstMatch)
            XCTAssertTrue(picker.isHittable)
            shortPress(picker)
        }
        openCodecChoices()
        if !app.buttons["H.264"].waitForExistence(timeout: 3) { print(app.debugDescription) }
        XCTAssertTrue(app.buttons["H.264"].exists)
        XCTAssertTrue(app.buttons["JPEG（兼容）"].exists)
        shortPress(app.buttons["H.265 / HEVC"])
        app.terminate(); app.launch()
        shortPress(app.buttons["remote-options"])
        shortPressMenuItem("远程传输画质设置", in: app)
        let picker = app.buttons["video-codec-picker"]
        reveal(picker, in: app.collectionViews.firstMatch)
        XCTAssertTrue(picker.label.contains("H.265") || (picker.value as? String)?.contains("H.265") == true, picker.debugDescription)
    }

    @MainActor
    func testDesktopFitsAboveNativeKeyboardInBothOrientations() {
        let app = XCUIApplication()
        app.launchEnvironment["DUO_UI_FIXTURE"] = "1"
        app.launchEnvironment["DUO_UI_KEYBOARD_LAYOUT"] = "1"
        app.launchArguments += ["-phoneKeyboardStyle", "system", "-keyboardInvocationV1", "manual", "-primaryPointerMode", "direct"]
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        app.launch()
        let desktop = app.otherElements["direct-remote-touch"]
        XCTAssertTrue(desktop.waitForExistence(timeout: 8))
        let original = desktop.frame
        shortPress(app.buttons["keyboard-dock-toggle"])
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 8))
        for orientation: UIDeviceOrientation in [.portrait, .landscapeLeft] {
            XCUIDevice.shared.orientation = orientation
            let fitted = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                guard desktop.exists, keyboard.exists, desktop.frame.height > 0 else { return false }
                // Keyboard AX frame excludes the Chinese candidate bar. The
                // zero-height IME bridge follows SwiftUI's full keyboard inset.
                let keyboardTop = app.textViews.firstMatch.frame.minY
                return abs(desktop.frame.maxY - keyboardTop) < 3
                    && abs(desktop.frame.width / desktop.frame.height - 1.6) < 0.02
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [fitted], timeout: 8), .completed,
                           "desktop=\(desktop.frame), keyboard=\(keyboard.frame), bridge=\(app.textViews.firstMatch.frame)")
            XCTAssertLessThanOrEqual(desktop.frame.maxY, keyboard.frame.minY + 3)
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "Desktop above native keyboard \(orientation.rawValue)"; shot.lifetime = .keepAlways; add(shot)
        }
        shortPress(app.buttons["keyboard-dock-toggle"])
        XCTAssertTrue(keyboard.waitForNonExistence(timeout: 8))
        XCUIDevice.shared.orientation = .portrait
        let restored = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            desktop.exists && abs(desktop.frame.height - original.height) < 3
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 8), .completed)
        shortPress(app.buttons["remote-options"])
        shortPressMenuItem("快捷键设置", in: app)
        let fit = app.switches["fit-desktop-above-keyboard"]
        reveal(fit, in: app.collectionViews.firstMatch)
        fit.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        let off = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "0"), object: fit)
        XCTAssertEqual(XCTWaiter.wait(for: [off], timeout: 3), .completed, fit.debugDescription)
        shortPress(app.buttons["完成"])
        shortPress(app.buttons["keyboard-dock-toggle"])
        XCTAssertTrue(keyboard.waitForExistence(timeout: 8))
        XCTAssertGreaterThan(desktop.frame.maxY, app.textViews.firstMatch.frame.minY + desktop.frame.height * 0.2)
        shortPress(app.buttons["keyboard-dock-toggle"])
    }

    @MainActor
    func testKeyboardKeepsBothPointerModesInteractiveAndDockNextToKeyboard() {
        for mode in ["direct", "trackpad"] {
            let app = XCUIApplication()
            app.launchEnvironment["DUO_UI_FIXTURE"] = "1"
            app.launchEnvironment["DUO_UI_KEYBOARD_LAYOUT"] = "1"
            app.launchEnvironment["DUO_UI_RESET_CONTROLS"] = "1"
            app.launchArguments += ["-controlRailTopV1", "0", "-controlRailBottomV1", "0", "-phoneKeyboardStyle", "system", "-keyboardInvocationV1", "manual", "-primaryPointerMode", mode, "-showStreamMetadataV1", "YES"]
            app.launch()
            let surface = app.otherElements[mode == "direct" ? "direct-remote-touch" : "grip-front-touchpad"]
            XCTAssertTrue(surface.waitForExistence(timeout: 8))
            let toggle = app.buttons["keyboard-dock-toggle"]
            shortPress(toggle)
            let keyboard = app.keyboards.firstMatch
            XCTAssertTrue(keyboard.waitForExistence(timeout: 8))
            let fitted = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                surface.frame.height > 0 && surface.frame.maxY <= keyboard.frame.minY + 2
                    && toggle.frame.maxY <= keyboard.frame.minY + 2
                    && abs(toggle.frame.maxY - app.textViews.firstMatch.frame.minY) < 30
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [fitted], timeout: 8), .completed, "surface=\(surface.frame), dock=\(toggle.frame), keyboard=\(keyboard.frame)")
            for flag in [8, 4, 2] {
                let modifier = app.buttons["native-modifier-\(flag)"]
                XCTAssertTrue(modifier.exists)
                XCTAssertLessThan(modifier.frame.maxX, toggle.frame.minX)
                XCTAssertEqual(modifier.frame.midY, toggle.frame.midY, accuracy: 5)
            }
            let counter = app.staticTexts["stream-metadata"]
            let before = counter.value as? String
            surface.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.4)).press(forDuration: 0.1,
                thenDragTo: surface.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.7)))
            let sent = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in (counter.value as? String) != before }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [sent], timeout: 3), .completed, "\(mode) must emit input with keyboard visible")
            XCTAssertTrue(keyboard.exists)
            shortPress(toggle); XCTAssertTrue(keyboard.waitForNonExistence(timeout: 5))
            app.terminate()
        }
    }

    @MainActor
    func testSharedScrollInertiaSettingPersistsAndCanBeDisabled() {
        let app = launchFixture()
        func openSettings() {
            shortPress(app.buttons["remote-options"]); shortPressMenuItem("辅助功能设置", in: app)
        }
        openSettings()
        let slider = app.sliders["scroll-inertia-slider"]
        reveal(slider, in: app.collectionViews.firstMatch)
        XCTAssertTrue(slider.isHittable)
        slider.adjust(toNormalizedSliderPosition: 0)
        XCTAssertTrue(app.staticTexts["统一滚动惯性 · 0.0"].exists)
        shortPress(app.buttons["完成"])
        app.terminate(); app.launch()
        openSettings(); reveal(slider, in: app.collectionViews.firstMatch)
        XCTAssertTrue(app.staticTexts["统一滚动惯性 · 0.0"].exists)
        shortPress(app.buttons["恢复惯性系数 1"])
        XCTAssertTrue(app.staticTexts["统一滚动惯性 · 1.0"].exists)
        shortPress(app.buttons["完成"])
    }

    @MainActor
    private func launchFixture() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["DUO_UI_FIXTURE"] = "1"
        app.launchEnvironment["DUO_UI_RESET_CONTROLS"] = "1"
        app.launchArguments += ["-phoneKeyboardStyle", "system", "-keyboardDefaultModeV2", "touchpad", "-primaryPointerMode", "direct", "-controlRailTopV1", "0", "-controlRailBottomV1", "0"]
        app.launchEnvironment["DUO_UI_LIVE_FRAMES"] = "1"
        app.launch()
        app.launchEnvironment.removeValue(forKey: "DUO_UI_RESET_CONTROLS")
        return app
    }

    @MainActor
    func testPointerButtonSwitchesWithShortTapAndCanBeHidden() {
        let app = launchFixture()
        shortPress(app.buttons["remote-options"]); shortPressMenuItem("快捷键设置", in: app)
        let option = app.switches["show-pointer-mode-button"]
        reveal(option, in: app.collectionViews.firstMatch)
        if option.value as? String != "1" { option.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).press(forDuration: 0.05) }
        XCTAssertEqual(option.value as? String, "1")
        shortPress(app.buttons["完成"])
        let toggle = app.segmentedControls["pointer-mode-toggle"], display = app.buttons["display-dock-button"], menu = app.buttons["remote-options"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.frame.midX, menu.frame.midX, accuracy: 2)
        XCTAssertEqual(display.frame.midX, menu.frame.midX, accuracy: 2)
        XCTAssertEqual(app.buttons["keyboard-dock-toggle"].frame.midX, menu.frame.midX, accuracy: 2)
        XCTAssertGreaterThan(toggle.frame.minY, menu.frame.maxY)
        XCTAssertGreaterThan(toggle.frame.minY, display.frame.maxY)
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)).press(forDuration: 0.05)
        XCTAssertEqual(toggle.value as? String, "触控板")
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75)).press(forDuration: 0.05)
        XCTAssertEqual(toggle.value as? String, "直接触屏")
        shortPress(display)
        XCTAssertTrue(app.buttons["完成"].waitForExistence(timeout: 5))
        shortPress(app.buttons["完成"])
        shortPress(menu); shortPressMenuItem("快捷键设置", in: app)
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
        let statuses = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "lan-presence-"))
        XCTAssertEqual(statuses.count, 2)
        XCTAssertTrue(statuses.element(boundBy: 0).label.contains("在线"))
        let refresh = app.buttons["lan-refresh-presence"]
        reveal(refresh, in: app.collectionViews.firstMatch)
        shortPress(refresh)
        XCTAssertEqual(statuses.count, 2)
        XCTAssertTrue(app.navigationBars["连接 Mac"].exists, "Refreshing status must not connect or dismiss the pairing screen.")
        // The UI fixture never authenticates or writes credentials to a real host.
    }

    @MainActor
    func testLANRemainsLoginFreeAndEmbeddedModeDoesNotConnectWithoutLogin() {
        let app = XCUIApplication()
        app.launchEnvironment["DUO_UI_FIXTURE"] = "1"
        app.launchEnvironment["DUO_UI_PAIRED_MACS"] = "1"
        app.launch()
        shortPress(app.buttons["remote-options"]); shortPressMenuItem("连接 Mac", in: app)
        let picker = app.segmentedControls["connection-network-mode"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["我的 Mac"].isEnabled)
        shortPress(picker.buttons["仅局域网"])
        XCTAssertFalse(app.buttons["tailscale-connect"].exists)
        shortPress(picker.buttons["仅 Tailscale"])
        XCTAssertTrue(app.buttons["tailscale-connect"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["我的 Mac"].isEnabled)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "无需额外安装 App")).firstMatch.exists)
        shortPress(picker.buttons["仅局域网"])
        XCTAssertTrue(app.buttons["我的 Mac"].isEnabled)
        XCTAssertFalse(app.buttons["tailscale-connect"].exists)
    }

    @MainActor
    func testTailnetFormButtonsDoNotActivateNeighborActionsOrWebsiteLinks() {
        let app = XCUIApplication()
        app.launchEnvironment["DUO_UI_FIXTURE"] = "1"
        app.launchEnvironment["DUO_UI_TAILNET_TAPS"] = "1"
        app.launch()
        shortPress(app.buttons["remote-options"]); shortPressMenuItem("连接 Mac", in: app)
        let picker = app.segmentedControls["connection-network-mode"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        shortPress(picker.buttons["仅 Tailscale"])
        let trace = app.staticTexts["tailscale-fixture-actions"]
        var expected: [String] = []
        for (identifier, action) in [
            ("tailscale-connect", "connect"),
            ("tailscale-authorize", "authorize"),
            ("tailscale-check-status", "status"),
            ("tailscale-disconnect", "disconnect"),
            ("tailscale-logout", "logout-prompt")
        ] {
            // Actual coordinate presses: accessibility activation can bypass
            // SwiftUI Form's automatic whole-row button handling.
            let button = app.buttons[identifier]
            XCTAssertTrue(button.waitForExistence(timeout: 5))
            reveal(button, in: app.collectionViews.firstMatch)
            button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.05)
            expected.append(action)
            XCTAssertEqual(trace.label, expected.joined(separator: ","), identifier)
        }
        let policy = app.buttons["tailscale-own-privacy"]
        reveal(policy, in: app.collectionViews.firstMatch)
        shortPress(policy)
        XCTAssertTrue(app.navigationBars["隐私政策"].waitForExistence(timeout: 5))
        shortPress(app.navigationBars["隐私政策"].buttons["完成"])
        XCTAssertEqual(trace.label, expected.joined(separator: ","), "Reading privacy must not log in, disconnect, log out or open a website.")
        let plan = app.links["tailscale-plan-link"]
        XCTAssertTrue(plan.exists)
        plan.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.05)
        expected.append("link-pricing")
        XCTAssertEqual(trace.label, expected.joined(separator: ","))
        // Fixture intercepts actions/links before any account, network or
        // credential change; it is compiled out on physical devices/Release.
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
        shortPress(app.buttons["remote-options"]); shortPressMenuItem("背屏控制设置", in: app)
        XCTAssertTrue(app.buttons["完成"].waitForExistence(timeout: 5))
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
        if !item.exists {
            let form = XCUIApplication().collectionViews.firstMatch
            for _ in 0..<10 {
                if item.exists || !form.exists { break }
                form.swipeDown()
            }
        }
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
        if ["Duo 操作手册", "诊断信息", "关于 Chordesk"].contains(title) {
            shortPressMenuItem("辅助功能设置", in: app)
            shortPress(app.buttons[title]); return
        }
        if title == "选字放大镜" {
            shortPressMenuItem("辅助功能设置", in: app)
            let toggle = app.switches["touch-magnifier-toggle"]
            reveal(toggle, in: app.collectionViews.firstMatch)
            shortPress(toggle); shortPress(app.buttons["完成"]); return
        }
        let list = app.tables["remote-action-list"]
        XCTAssertTrue(list.waitForExistence(timeout: 5))
        let item = list.descendants(matching: .any).matching(NSPredicate(format: "label == %@", title)).firstMatch
        reveal(item, in: list)
        if !item.exists { print(app.debugDescription) }
        shortPress(item)
    }

    @MainActor
    func testRetiredMicrophoneHasNoCaptureEntryEvenWithOldAutoStartPreference() {
        let app = XCUIApplication()
        app.launchEnvironment["DUO_UI_FIXTURE"] = "1"
        app.launchArguments += ["-ChordeskMicrophoneAutoStart", "YES"]
        app.launch()
        XCTAssertFalse(app.buttons["remote-microphone-live"].exists)
        shortPress(app.buttons["remote-options"])
        XCTAssertFalse(app.tables["remote-action-list"].staticTexts["开启 Duo 麦克风"].exists)
        shortPressMenuItem("辅助功能设置", in: app)
        XCTAssertFalse(app.switches["remote-microphone-toggle"].exists)
        XCTAssertFalse(app.switches["remote-microphone-autostart"].exists)
    }

    @MainActor
    func testFullscreenControlsAndRearSwitchGuide() {
        let app = launchFixture()
        XCTAssertTrue(app.buttons["remote-options"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars.element.exists, "Desktop is no longer inset by a title/menu bar.")
        app.buttons["remote-options"].tap()
        shortPressMenuItem("背屏控制设置", in: app)
        XCTAssertTrue(app.buttons["camera-mode-front-touch"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["camera-mode-direct"].exists)
        app.buttons["完成"].tap()
        app.buttons["remote-options"].tap()
        shortPressMenuItem("Duo 操作手册", in: app)
        XCTAssertTrue(app.navigationBars["Duo 操作手册"].waitForExistence(timeout: 5))
        let rearGuide = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "2 指长按背屏")).firstMatch
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
        app.buttons["remote-options"].tap(); shortPressMenuItem("辅助功能设置", in: app)
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
        app.buttons["remote-options"].tap(); shortPressMenuItem("辅助功能设置", in: app)
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
            shortPressMenuItem("快捷键设置", in: app)
            reveal(app.sliders["control-rail-top"], in: app.collectionViews.firstMatch)
            XCTAssertTrue(app.sliders["control-rail-top"].exists)
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
        XCTAssertLessThan(badge.frame.maxY, menu.frame.minY,
                          "Rear lights stay at the top, independently of the rail and full-bleed desktop.")
        XCTAssertGreaterThan(menu.frame.midX, app.windows.firstMatch.frame.width * 0.9)
        XCTAssertEqual(menu.frame.midX, keyboard.frame.midX, accuracy: 2)
        XCTAssertLessThan(badge.frame.midX, menu.frame.midX)
        shortPress(keyboard)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 8))
        app.typeText("duo")
        shortPress(keyboard)
        shortPress(menu)
        shortPressMenuItem("快捷键设置", in: app)
        reveal(app.sliders["control-rail-top"], in: app.collectionViews.firstMatch)
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

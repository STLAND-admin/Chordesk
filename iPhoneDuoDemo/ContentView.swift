import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var session = DemoSession()
    @StateObject private var client = LANClient()
    @StateObject private var camera = CameraAccessory()
    @StateObject private var grip = GripInteraction()
    @StateObject private var keyboardController = NativeKeyboardController()
    @AppStorage("keyboardHeightFraction") private var keyboardFraction = 0.25
    @AppStorage("clickFeedbackEnabled") private var clickFeedback = true
    @AppStorage("innerPointerSensitivity") private var innerSensitivity = TouchpadTuning.defaultSensitivity
    @AppStorage("outerTouchEdgeInset") private var outerEdgeInset = TouchpadTuning.defaultEdgeInset
    @AppStorage("keyboardDefaultModeV2") private var innerDefaultMode = InnerInputMode.touchpad.rawValue
    @AppStorage("rearActivation") private var rearActivation = RearActivation.momentary.rawValue
    @AppStorage("rearTriggerV2") private var rearTrigger = RearTrigger.touch.rawValue
    @AppStorage("keyboardTransparency") private var keyboardTransparency = 0.45
    @AppStorage("primaryPointerMode") private var frontTouchMode = FrontTouchMode.direct.rawValue
    @AppStorage("showPointerModeButtonV1") private var showPointerModeButton = true
    @AppStorage("showDisplayButtonV1") private var showDisplayButton = true
    @AppStorage("showOverviewButtonV1") private var showOverviewButton = true
    @AppStorage("metadataCornerV1") private var metadataCorner = MetadataCorner.topLeft.rawValue
    @State private var settingsCategory = ControlSettingsCategory.shortcuts
    @State private var railFrame = CGRect.zero
    @AppStorage("touchMagnifierEnabled") private var magnifierEnabled = true
    @State private var showingGuide = false
    @State private var showingAbout = false
    @AppStorage("phoneKeyboardStyle") private var keyboardStyle = PhoneKeyboardStyle.system.rawValue
    @AppStorage("keyboardInvocationV1") private var keyboardInvocation = KeyboardInvocation.automatic.rawValue
    @AppStorage("showStreamMetadataV1") private var showStreamMetadata = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var keyboardResizeDuration = 0.25
    @State private var keyboardResizeCurve = 0
    @State private var viewportAnimating = false
    @State private var viewportAnimationID = UUID()
    @AppStorage("fitDesktopAboveKeyboardV1") private var fitDesktopAboveKeyboard = true
    @AppStorage("rearControlAutoStartV1") private var rearAutoStart = true
    @AppStorage("rearWindowGesturesV1") private var rearWindowGestures = true
    @AppStorage("controlRailTopV1") private var controlRailTop = 0.0
    @AppStorage("controlRailBottomV1") private var controlRailBottom = 0.0
    @State private var menuPresented = false
    @State private var statusAreaBottom: CGFloat = 0
    @State private var edgeBarBottom: CGFloat = 0
    @State private var edgeBarWidth: CGFloat = 0
    @State private var edgeAnchorX: CGFloat?
    @State private var workspaceFrame = CGRect.zero
    @State private var workspaceHeight: CGFloat = 0
    @State private var nativeKeyboardTop: CGFloat?
    @State private var customKeyboardFrame = CGRect.zero
    @State private var rearBadgeSize = CGSize.zero
    @State private var rearBadgeFrame = CGRect.zero
    @State private var previousIdleTimer: Bool?
    @State private var nativeKeyboard = NativeKeyboardPresentation()
    @State private var keyboardPolicy = AutomaticKeyboardPolicy()
    @State private var automaticInnerMode: InnerInputMode?
    @State private var directResetToken = 0
    @State private var inputEpoch = 0
    @State private var overviewMessage = "尚未触发窗口总览"
    @State private var overviewSequence: UInt64 = 0
    @State private var showingDisplays = false
    @State private var resizeStart: Double?
    @State private var showingInputSettings = false
    @State private var showingCameraControls = false
    @State private var pendingCameraMode: OuterControlMode?
    @State private var showingConnect = false
    @State private var showingLog = false
    @State private var showingDemoLog = false
    @State private var localDemo = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .topTrailing) {
                presentedWorkspace
                    .padding(.top, rearBadgeFrame.maxY)
                    .ignoresSafeArea(.container).ignoresSafeArea(.keyboard)
            }
            .background(.black)
            .overlay(alignment: .bottom) {
                if nativeKeyboardVisible {
                    NativeKeyboardInput(active: !menuPresented, contextID: nativeTextContext, secure: client.textFocus?.secure ?? false,
                        onEdit: { client.nativeText($0) }, onKey: { client.nativeKey($0, modifiers: $1) },
                        onCursorKey: { client.nativeCursorKey($0) }, controller: keyboardController)
                        .frame(height: 0).allowsHitTesting(false).accessibilityHidden(true)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                if keyboardInvocation == KeyboardInvocation.manual.rawValue { automaticInnerMode = .touchpad }
                configureGrip()
                configureInputRouting()
                updateNativeKeyboardVisibility(); updateRearCapture()
            }
            .onChange(of: innerDefaultMode) { _, _ in automaticInnerMode = nil; configureGrip() }
            .onChange(of: automaticInnerMode) { _, _ in configureGrip() }
            .onChange(of: rearActivation) { _, _ in configureGrip() }
            .onChange(of: rearAutoStart) { _, enabled in if enabled { updateRearCapture() } else { camera.stop() } }
            .onChange(of: keyboardInvocation) { _, mode in
                keyboardPolicy.suppress(through: client.sentEvents)
                if mode == KeyboardInvocation.manual.rawValue { chooseInnerMode(.touchpad) }
            }
            .onChange(of: rearTrigger) { _, _ in configureGrip() }
            .onChange(of: frontTouchMode) { _, _ in releaseInteractions(); configureGrip(); configureInputRouting() }
            .onChange(of: grip.state.requestedFrontMode) { _, _ in
                inputEpoch += 1; grip.releaseFront(); grip.innerContacts(0)
                client.release(); configureInputRouting()
            }
            .onChange(of: localDemo) { _, _ in configureInputRouting() }
            .onChange(of: keyboardStyle) { _, _ in releaseInteractions() }
            .onChange(of: nativeKeyboardWanted) { _, _ in updateNativeKeyboardVisibility() }
            .onChange(of: grip.state.innerCount) { _, _ in updateNativeKeyboardVisibility(); updateAutomaticKeyboard() }
            .onChange(of: grip.state.outerCount) { _, _ in keyboardPolicy.suppress(through: client.sentEvents) }
            .onChange(of: client.textFocus) { _, _ in updateAutomaticKeyboard() }
            .onChange(of: client.connected) { _, value in
                if !value { keyboardPolicy = AutomaticKeyboardPolicy(); automaticInnerMode = nil; keyboardController.reset(); camera.stop() }
                else {
                    if keyboardInvocation == KeyboardInvocation.manual.rawValue { automaticInnerMode = .touchpad }
                    updateRearCapture()
                }
                updateRearCapture()
            }
            .onChange(of: client.selectedDisplayID) { _, _ in releaseInteractions() }
            .onChange(of: camera.mode) { _, _ in releaseInteractions() }
            .onChange(of: camera.enabled) { _, value in if !value { releaseInteractions() } }
            .onChange(of: camera.running) { _, value in if !value { releaseInteractions() } }
            .onChange(of: camera.surfaceEpoch) { _, _ in releaseInteractions() }
            .onChange(of: client.controlAllowed) { _, value in if !value { releaseInteractions() }; updateRearCapture() }
            .onChange(of: client.inputSuspended) { _, _ in updateRearCapture() }
            .onChange(of: modalVisible) { _, value in
                client.inputSuspended = value
                if value { releaseInteractions(); if showingConnect { camera.stop() } }
                updateRearCapture()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in client.inputSuspended = true; releaseInteractions(); updateRearCapture() }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                if ProcessInfo.processInfo.environment["DUO_UI_FIXTURE"] != "1" { EmbeddedTailnet.shared.resumeIfNeeded() }
                client.inputSuspended = modalVisible; updateRearCapture(); camera.resumeInput()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in releaseInteractions(); camera.stop(); client.disconnect(); EmbeddedTailnet.shared.suspend() }
            .onDisappear { releaseInteractions(); camera.stop(); client.disconnect(); restoreIdleTimer() }
        }
        // Attach outside NavigationStack's inset content proposal. Ignoring the
        // safe area on the old child alone did not recover the window's width.
        .overlay { controlRail }
        .overlay(alignment: (MetadataCorner(rawValue: metadataCorner) ?? .topLeft).alignment) {
            if showStreamMetadata && client.connected && !modalVisible {
                streamMetadata.padding(8)
                    .padding(.trailing, MetadataCorner(rawValue: metadataCorner)?.isTrailing == true ? edgeBarWidth : 0)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .topLeading) {
            // A dedicated top strip prevents any contact light covering the
            // desktop. Its position never inherits Dock or keyboard offsets.
            GeometryReader { _ in
                rearStatusBadge.fixedSize()
                    .onGeometryChange(for: CGSize.self) { $0.size } action: { rearBadgeSize = $0 }
                    .position(x: rearBadgeFrame.midX, y: rearBadgeFrame.midY)
                    .opacity(modalVisible ? 0 : 1).allowsHitTesting(!modalVisible)
            }
            .background { RearStatusPositionReader(size: rearBadgeSize) { rearBadgeFrame = $0 }.allowsHitTesting(false) }
            .ignoresSafeArea(.container).ignoresSafeArea(.keyboard)
        }
        .overlay(alignment: .bottom) {
            if customKeyboardShown && !modalVisible {
                GeometryReader { geometry in
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        keyboardOverlay(availableHeight: geometry.size.height)
                            .padding(.trailing, ControlRailPosition.trailingInset(containerWidth: geometry.size.width,
                                anchorX: edgeAnchorX, buttonWidth: edgeBarWidth))
                    }
                }.ignoresSafeArea(.container)
            }
        }
    }

    private var presentedWorkspace: some View {
        Group {
            if #available(iOS 27.1, *) {
                CameraAccessoryWorkspace(camera: camera, client: client, grip: grip, content: workspace)
            } else { workspace }
        }
        .sheet(isPresented: $showingConnect) { LANConnectView(client: client) }
        .sheet(isPresented: $showingDisplays) { LANDisplaySettings(client: client) }
        .sheet(isPresented: $showingInputSettings) { inputSettings }
        .sheet(isPresented: $showingCameraControls, onDismiss: applyPendingCameraMode) {
            CameraControlSettings(camera: camera) { mode in
                pendingCameraMode = mode
                showingCameraControls = false
            } stop: {
                rearAutoStart = false; releaseInteractions(); camera.stop()
                showingCameraControls = false
            }
        }
        .sheet(isPresented: $showingGuide) { NavigationStack { operationGuide } }
        .sheet(isPresented: $showingAbout) { ChordAboutView() }
        .sheet(isPresented: $showingLog) { NavigationStack { diagnosticsView } }
        .sheet(isPresented: $showingDemoLog) {
            NavigationStack {
                InteractionLog(session: session).navigationTitle("交互记录")
                    .toolbar { ToolbarItem { Button("完成") { showingDemoLog = false } } }
            }
        }
    }

    private var controlMenu: some View {
        StableMenuButton(symbol: "slider.horizontal.3", title: "远程控制菜单", identifier: "remote-options",
            sections: controlMenuSections, onPresentation: setMenuPresented, onSelect: selectControl)
            .modifier(EdgeDockGlass())
    }
    private var controlMenuSections: [SystemMenuSection] {
        var sections = [SystemMenuSection(title: client.connected ? client.sourceName : "Chordesk", items: [
            .init(id: "connect", title: "连接 Mac", symbol: "network")
        ]), SystemMenuSection(items: ControlSettingsCategory.allCases.map {
            .init(id: $0.rawValue, title: $0.title, symbol: $0.symbol)
        })]
        if client.connected { sections.append(.init(items: [.init(id: "disconnect", title: "断开 Mac", symbol: "network.slash", destructive: true)])) }
        return sections
    }
    private func selectControl(_ id: String) {
        if let category = ControlSettingsCategory(rawValue: id) {
            releaseInteractions(); settingsCategory = category; showingInputSettings = true; return
        }
        switch id {
        case "connect": releaseInteractions(); showingConnect = true
        case "trackpad", "direct": releaseInteractions(); frontTouchMode = id
        case "displays": releaseInteractions(); showingDisplays = true; client.requestDisplays()
        case "magnifier": magnifierEnabled.toggle()
        case "overview-show": sendWindowOverview(.show)
        case "overview-hide": sendWindowOverview(.hide)
        case "desktop-previous": sendWindowOverview(.previousDesktop)
        case "desktop-next": sendWindowOverview(.nextDesktop)
        case "zoom-reset": releaseInteractions(); directResetToken += 1
        case "camera": openCameraControls()
        case "settings": releaseInteractions(); showingInputSettings = true
        case "guide": releaseInteractions(); showingGuide = true
        case "about": releaseInteractions(); showingAbout = true
        case "diagnostics": releaseInteractions(); showingLog = true
        case "demo-log": showingDemoLog = true
        case "demo": releaseInteractions(); camera.stop(); client.disconnect(); localDemo.toggle()
        case "disconnect": releaseInteractions(); camera.stop(); client.disconnect()
        default: break
        }
    }
    private func switchPointerMode() {
        let next: FrontTouchMode = directTouchSelected ? .trackpad : .direct
        releaseInteractions(); frontTouchMode = next.rawValue
    }
    private func setMenuPresented(_ value: Bool) {
        menuPresented = value
        grip.setControlsPresented(value)
        inputEpoch += 1; client.release()
        keyboardPolicy.suppress(through: client.sentEvents)
        updateRearCapture()
    }
    private var controlRail: some View {
        GeometryReader { geometry in
            let keyboardBottomInset = nativeKeyboardVisible && nativeKeyboardTop != nil
                ? max(0, geometry.frame(in: .global).maxY - (workspaceFrame.minY + (nativeKeyboardTop ?? 0))) : edgeBarBottom
            if !modalVisible {
                VStack(alignment: .trailing) {
                    ScrollView(.vertical) {
                      VStack(spacing: 8) {
                        controlMenu
                            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { edgeBarWidth = $0 }
                        if showPointerModeButton {
                            StableMenuButton(symbol: directTouchSelected ? "hand.tap" : "hand.draw", title: directTouchSelected ? "切换为触控板" : "切换为直接触控",
                                identifier: "pointer-mode-toggle", sections: [], primaryAction: switchPointerMode,
                                onPresentation: { _ in }, onSelect: { _ in })
                                .modifier(EdgeDockGlass())
                                .accessibilityValue(directTouchSelected ? "直接触控" : "触控板")
                        }
                        if showDisplayButton {
                            StableMenuButton(symbol: "display", title: "显示器与文字大小", identifier: "display-dock-button", sections: [],
                                primaryAction: { releaseInteractions(); showingDisplays = true; client.requestDisplays() },
                                onPresentation: { _ in }, onSelect: { _ in }).modifier(EdgeDockGlass())
                        }
                        if showOverviewButton {
                            StableMenuButton(symbol: "rectangle.3.group", title: "窗口总览", identifier: "overview-dock-button",
                                sections: [.init(items: [
                                    .init(id: "overview-show", title: "打开窗口总览", symbol: "rectangle.3.group", enabled: client.acceptsInput),
                                    .init(id: "overview-hide", title: "退出窗口总览", symbol: "rectangle", enabled: client.acceptsInput)
                                ])], primaryAction: { sendWindowOverview(.show) },
                                onPresentation: setMenuPresented, onSelect: selectControl)
                                .modifier(EdgeDockGlass()).accessibilityHint("轻点打开总览；长按可选择退出")
                        }
                      }
                    }.scrollIndicators(.hidden)
                        .frame(maxWidth: edgeBarWidth > 0 ? edgeBarWidth : nil, alignment: .trailing)
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { railFrame = $0 }
                        .padding(.top, geometry.size.height * ControlRailPosition.fraction(controlRailTop, maximum: 0.25))
                    Spacer(minLength: 0)
                    if !customKeyboardShown { keyboardDock
                        .padding(.bottom, nativeKeyboardVisible ? 0 : geometry.size.height * ControlRailPosition.fraction(controlRailBottom, maximum: 0.30))
                    }
                }
                .padding(.top, 8).padding(.bottom, nativeKeyboardVisible ? 4 : 8)
                .padding(.top, statusAreaBottom)
                .padding(.bottom, keyboardBottomInset)
                .animation(keyboardResizeAnimation, value: keyboardBottomInset)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                .padding(.trailing, ControlRailPosition.trailingInset(containerWidth: geometry.size.width,
                    anchorX: edgeAnchorX, buttonWidth: edgeBarWidth))
            }
        }
        .background { SystemStatusBoundaryReader(extent: edgeBarWidth) { top, bottom, anchor in
            statusAreaBottom = top; edgeBarBottom = bottom; edgeAnchorX = anchor
        }.allowsHitTesting(false) }
        .ignoresSafeArea(.container).ignoresSafeArea(.keyboard)
    }

    private var rearStatusBadge: some View {
        let ready = camera.running && camera.enabled && camera.presented
        let contacts = ready ? grip.state.outerCount : 0
        return Button(action: openCameraControls) {
            HStack(spacing: 5) {
                ForEach(0..<3) { index in
                    Image(systemName: index < contacts ? "circle.fill" : "circle")
                        .foregroundStyle(ready && index < contacts ? Color.primary : Color.secondary.opacity(0.55))
                }
                if !ready { Image(systemName: "pause.fill").foregroundStyle(.secondary) }
            }
            .font(.caption2).padding(.horizontal).padding(.vertical, 6)
            .accessibilityHidden(true)
        }
        .buttonStyle(.plain).background(.ultraThinMaterial, in: Capsule())
        .accessibilityIdentifier("rear-status-badge")
        .accessibilityLabel("背面接触指示灯")
        .accessibilityValue("\(ready ? "就绪" : "未就绪")，\(contacts) 指，\(grip.state.requestedFrontMode.title)")
        .accessibilityHint("打开背面控制设置。三盏灯分别表示一指、两指、三指及以上。")
        .overlay(alignment: .leading) {
            if ready && !directTouchSelected {
                Image(systemName: "hand.draw").font(.caption2).foregroundStyle(.secondary)
                    .offset(x: -18).allowsHitTesting(false).accessibilityHidden(true)
            }
        }
    }

    private var keyboardShown: Bool { useNativeKeyboard ? nativeKeyboardVisible : grip.state.requestedMode == .keyboard }
    private var customKeyboardShown: Bool { !useNativeKeyboard && grip.state.requestedMode == .keyboard }
    private func modifierSelected(_ flag: UInt) -> Bool {
        if useNativeKeyboard { return keyboardController.flags & flag != 0 }
        switch flag { case 8: return session.control; case 2: return session.command; default: return session.option }
    }
    private func toggleModifier(_ flag: UInt) {
        if useNativeKeyboard { keyboardController.toggle(flag) }
        else { session.key(flag == 8 ? "ctrl" : flag == 2 ? "cmd" : "opt") }
    }
    private func sendKeyboardKey(_ key: String, flags: UInt = 0) {
        if localDemo { session.key(key); return }
        if useNativeKeyboard { keyboardController.sendKey(key, flags: flags) }
        else { client.nativeKey(key, modifiers: flags | customModifierFlags); clearCustomModifiers() }
    }
    private var customModifierFlags: UInt { (session.control ? 8 : 0) | (session.command ? 2 : 0) | (session.option ? 4 : 0) }
    private func clearCustomModifiers() { session.command = false; session.option = false; session.control = false; session.shift = false }
    private func sendMobileInput(_ action: MobileKeyboardAction) {
        guard customKeyboardShown, !menuPresented, !modalVisible else { return }
        defer { clearCustomModifiers() }
        if localDemo {
            switch action {
            case .text(let text):
                if customModifierFlags != 0 { session.key(text) }
                else { session.insert(text); session.record(text == " " ? "空格" : "输入 \(text)") }
            case .key(let key): session.key(key)
            }
            return
        }
        guard client.acceptsInput else { return }
        switch action {
        case .text(let text):
            var modifiers = ShortcutModifiers()
            modifiers.toggle(customModifierFlags)
            if let shortcut = modifiers.shortcut(for: text) { client.nativeKey(shortcut.key, modifiers: shortcut.flags) }
            else { client.nativeText(LANTextEdit(deleteCount: 0, text: text)) }
        case .key(let key): client.nativeKey(key, modifiers: customModifierFlags)
        }
    }
    @ViewBuilder private var keyboardDockItems: some View {
        Group {
            if keyboardShown {
                ForEach([UInt(8), UInt(2), UInt(4)], id: \.self) { flag in
                    Button { toggleModifier(flag) } label: {
                        Text(flag == 8 ? "Ctrl" : flag == 2 ? "⌘" : "⌥").font(.title3)
                            .padding(.horizontal, 12).padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    .modifier(EdgeDockGlass())
                    .foregroundStyle(modifierSelected(flag) ? Color.primary : Color.secondary)
                    .accessibilityLabel(flag == 8 ? "Ctrl" : flag == 2 ? "Command" : "Option")
                    .accessibilityValue(modifierSelected(flag) ? "已按下，下一次快捷键后释放" : "未按下")
                    .accessibilityIdentifier("native-modifier-\(flag)")
                }
            }
            StableMenuButton(symbol: keyboardShown ? "keyboard.chevron.compact.down" : "keyboard",
                title: keyboardShown ? "收起键盘／快捷菜单" : "显示键盘／快捷菜单", identifier: "keyboard-dock-toggle",
                sections: keyboardMenuSections, primaryAction: { chooseInnerMode(keyboardShown ? .touchpad : .keyboard) },
                onPresentation: setMenuPresented, onSelect: selectKeyboardMenu)
            .modifier(EdgeDockGlass())
            .accessibilityHint("轻点显示或收起键盘，长按打开快捷菜单")
        }
    }
    private var keyboardDock: some View {
        Group {
            if customKeyboardShown {
                VStack(alignment: .trailing, spacing: 4) { keyboardDockItems }
            } else {
                // Stable hierarchy while the system keyboard hides for a menu.
                HStack(spacing: 4) { keyboardDockItems }
            }
        }
    }
    private var keyboardMenuSections: [SystemMenuSection] {
        let shortcuts: [(String, String)] = [("esc", "Esc"), ("tab", "Tab"), ("cmd-a", "全选 ⌘A"),
            ("cmd-c", "复制 ⌘C"), ("cmd-v", "粘贴 ⌘V"), ("left", "← 向左"), ("right", "→ 向右"), ("up", "↑ 向上"), ("down", "↓ 向下")]
        return [
            .init(items: [.init(id: keyboardShown ? "hide" : "show", title: keyboardShown ? "收起键盘" : "显示键盘", symbol: "keyboard")]),
            .init(title: "键盘布局", items: PhoneKeyboardStyle.allCases.map {
                .init(id: "style-" + $0.rawValue, title: $0.title, selected: keyboardStyle == $0.rawValue)
            }),
            .init(title: "键盘唤起", items: KeyboardInvocation.allCases.map {
                .init(id: "invocation-" + $0.rawValue, title: $0.title, selected: keyboardInvocation == $0.rawValue)
            }),
            .init(title: "快捷键", items: shortcuts.map { .init(id: $0.0, title: $0.1, enabled: keyboardShown) }),
            .init(title: "功能键", submenu: true, items: (1...12).map { .init(id: "f\($0)", title: "F\($0)", enabled: keyboardShown) })
        ]
    }
    private func selectKeyboardMenu(_ id: String) {
        if id == "show" || id == "hide" { chooseInnerMode(id == "show" ? .keyboard : .touchpad) }
        else if id.hasPrefix("invocation-") { keyboardInvocation = String(id.dropFirst(11)) }
        else if id.hasPrefix("style-") { keyboardStyle = String(id.dropFirst(6)) }
        else if id.hasPrefix("cmd-") { sendKeyboardKey(String(id.dropFirst(4)), flags: 2) }
        else { sendKeyboardKey(id) }
    }

    private func updateRearCapture() {
        let foreground = UIApplication.shared.applicationState == .active
        let sessionActive = client.connected && client.controlAllowed && !localDemo && foreground
        if sessionActive {
            if previousIdleTimer == nil { previousIdleTimer = UIApplication.shared.isIdleTimerDisabled }
            UIApplication.shared.isIdleTimerDisabled = true
        } else { restoreIdleTimer() }
        camera.recoveryAllowed = client.acceptsInput && !modalVisible && !menuPresented && !localDemo && foreground
#if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.environment["DUO_UI_FIXTURE"] == "1" { return }
#endif
        guard #available(iOS 27.1, *), rearAutoStart, camera.recoveryAllowed else { return }
        camera.start()
    }
    private func restoreIdleTimer() {
        if let previousIdleTimer { UIApplication.shared.isIdleTimerDisabled = previousIdleTimer }
        previousIdleTimer = nil
    }
    private func sendWindowOverview(_ action: WindowOverviewAction) {
        guard client.acceptsInput else { return }
        keyboardPolicy.suppress(through: client.sentEvents)
        keyboardController.reset(); client.release()
        guard client.windowOverview(action) else {
            overviewMessage = action.isDesktopSwitch ? "切换桌面需要 Mac 主机 0.18.1 或更新版本" : "窗口总览需要 Mac 主机 0.10.2 或更新版本"
            overviewSequence = 0
            return
        }
        overviewSequence = client.sentEvents
        overviewMessage = "已请求 Mac：" + action.title
    }

    private var videoSettings: some View {
        Section("远程画质") {
            Picker("视频编码", selection: $client.preferredVideoCodec) {
                ForEach(LANVideoCodec.allCases) { Text($0.title).tag($0) }
            }.pickerStyle(.navigationLink).accessibilityIdentifier("video-codec-picker")
            Text("H.264 兼容性好；H.265 通常更省带宽，也适用于弱网。硬件或旧主机不支持时自动回退，左上角显示实际编码。切换不会改变画质档位。")
                .font(.caption).foregroundStyle(.secondary)
            Text(client.streamMetadata).font(.caption.monospaced())
            Text("延迟为应用层往返 RTT，包含处理和排队时间，不是触控到显示的端到端延迟；fps 为接收画面帧率。")
                .font(.caption).foregroundStyle(.secondary)
            if let settings = client.streamSettings {
                StreamSettingsControls(settings: settings, onChange: client.setStreamSettings)
                    .disabled(!client.canSwitchDisplays || client.switchingDisplay || client.testingBandwidth)
                if client.supportsBandwidthProbe {
                    Button { client.testBandwidth() } label: {
                        Label(client.testingBandwidth ? "正在检测…" : "检测连接并推荐设置", systemImage: "speedometer")
                    }.buttonStyle(.borderedProminent).tint(.gray)
                        .disabled(client.testingBandwidth || client.switchingDisplay)
                        .accessibilityIdentifier("stream-bandwidth-test")
                    Text(client.bandwidthMessage).font(.caption)
                    if client.streamRecommendation != nil {
                        Button("应用推荐码率与帧率") { client.applyStreamRecommendation() }
                            .buttonStyle(.bordered).disabled(!client.canSwitchDisplays || client.switchingDisplay)
                            .accessibilityIdentifier("stream-apply-recommendation")
                    }
                    Text("检测载荷不超过 512 KiB，另有少量协议开销；不连接外部测速服务器。结果包含当前路径、往返与排队影响，仅作保守建议；不会自动改动你的设置。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else if let quality = client.videoQuality {
                Picker("旧版画质", selection: Binding(get: { quality }, set: { client.setVideoQuality($0) })) {
                    ForEach(client.availableVideoQualities.filter { $0.framesPerSecond <= 120 }) { Text($0.title).tag($0) }
                }.disabled(!client.canSwitchDisplays || client.switchingDisplay)
                Text("升级 Mac 主机到 0.26.0 可分别设置分辨率、帧率和码率。").font(.caption)
            } else { Text("连接 Mac 后可调整传输画质") }
            Text("实际视频载荷 \(client.videoMbps, specifier: "%.1f") Mbps · \(client.videoFPS, specifier: "%.0f") fps")
            if let rate = client.sourceRefreshRate {
                Text("Mac 显示模式标称刷新率 \(rate, specifier: "%.0f") Hz").font(.caption)
            }
            Text("默认 720p、15 fps、H.265；硬件不支持时自动回退 H.264／JPEG。H.265 的压缩效率不代表更低编码延迟，可按实际连接效果选择。")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private var operationGuide: some View {
        List {
            Section("0 指背屏（直接触控 · 默认）") {
                LabeledContent("正面轻点／双击", value: "左键／双击")
                LabeledContent("单指滑动", value: "滚动页面")
                LabeledContent("长按约半秒后拖动", value: "按住左键拖选；抬手释放")
                LabeledContent("长按不动，松手", value: "右键菜单")
                LabeledContent("双指捏合／平移", value: "放大／移动手机上的画面")
            }
            Section("1 指按住背屏（直接触控）") {
                LabeledContent("正面双指上滑", value: "打开窗口总览")
                LabeledContent("正面双指下滑", value: "退出窗口总览")
                LabeledContent("正面双指左滑／右滑", value: "下一个／上一个桌面")
                Text("左右切桌面需要 Mac 开启 System Events 权限和 Control＋方向键快捷键，并有至少两个桌面。").font(.footnote).foregroundStyle(.secondary)
            }
            Section("2 指接触背屏（临时触控板 · 默认）") {
                LabeledContent("正面单指滑动", value: "移动鼠标")
                LabeledContent("单指轻点／双击", value: "左键／双击")
                LabeledContent("单指长按后拖动", value: "按住左键拖选")
                LabeledContent("双指滑动／轻点", value: "滚轮／右键")
                LabeledContent("松开背面手指", value: "回到直接触控")
                Text("键盘上方的黑边也可作为触控板，右侧快捷栏除外。也可用右侧操控模式按钮固定切换；背屏设置可改为触发一次切换，再触发一次恢复。").font(.footnote).foregroundStyle(.secondary)
            }
            Section("iPhone 键盘与快捷键") {
                Text("默认 iPhone 输入法、自动唤起。点 Mac 输入位置后抬起手指，键盘会弹出；无法识别时点右下键盘按钮。快捷键设置可改为手动唤起。")
                Text("输入结果直接看远程桌面。画面默认等比例放到键盘上方，可在快捷键设置关闭。长按空格后滑动调整 Mac 文字光标；第三方输入法需支持系统光标回调。")
                Text("键盘上方 Ctrl／⌘／⌥ 可组合，下次快捷键后释放，再点可取消。长按键盘按钮打开 Esc、Tab、复制粘贴、方向键和 F1–F12。")
                Text("快捷键设置中可编辑右侧三个入口：显示器、操控模式、窗口总览。右侧栏可上下滑动。")
            }
            Section("显示与画质") {
                Text("文字太小：显示器 → 更大文字。画面模糊：远程传输画质设置 → 清晰／超清。分辨率会影响实体 Mac，断连后尝试恢复。")
                Text("默认省流 15 fps、H.264；可选 H.265 或 JPEG。120／144 fps 为实验上限。辅助功能设置 → 诊断信息，可开关画面信息并选择位置。")
                Text("滚动惯性、指针灵敏度、长按放大镜在辅助功能设置。惯性 0 关闭、1 默认、2 更强；重新落指停止续滚。")
            }
            Section("连接与背屏") {
                Text("Mac 首次按提示开启屏幕录制和控制权限；每次系统要求重启时照做，权限齐全后开启服务。手机首次扫码，之后点已配对 Mac。公网需两端登录同一 Tailscale 私人网络。")
                Text("Duo 展开并保持 App 前台。三盏灯表示有效区域内接触数，暂停表示未就绪。正常背屏纯黑；仅调整区域时显示边框。菜单关闭后抬起背面手指再落下。")
                Text("Mac 关闭窗口仍在后台服务；退出才停止。息屏与睡眠不同，真正睡眠／合盖不保证连接。")
            }
        }.navigationTitle("Duo 操作手册")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { showingInputSettings = false; showingGuide = false } } }
    }

    private var keyboardResizeAnimation: Animation? {
        guard !reduceMotion, keyboardResizeDuration > 0 else { return nil }
        switch keyboardResizeCurve {
        case 1: return .easeIn(duration: keyboardResizeDuration)
        case 2: return .easeOut(duration: keyboardResizeDuration)
        case 3: return .linear(duration: keyboardResizeDuration)
        default: return .easeInOut(duration: keyboardResizeDuration)
        }
    }
    private var streamMetadata: some View {
        Text(client.streamMetadata)
            .font(.system(.caption2, design: .monospaced)).foregroundStyle(.primary)
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
            .accessibilityIdentifier("stream-metadata")
#if DEBUG && targetEnvironment(simulator)
            .accessibilityValue(ProcessInfo.processInfo.environment["DUO_UI_FIXTURE"] == "1" ? "events=\(client.sentEvents)" : "")
#endif
    }

    private var workspace: some View {
        GeometryReader { geometry in
            let customTop = customKeyboardShown ? RemoteKeyboardLayout.top(of: customKeyboardFrame, in: geometry.frame(in: .global)) : nil
            let inputTop = nativeKeyboardVisible && !menuPresented ? nativeKeyboardTop : customTop
            let top = fitDesktopAboveKeyboard ? inputTop : nil
            let contentSize = client.image.map { CGSize(width: $0.width, height: $0.height) } ?? geometry.size
            let desktop = RemoteKeyboardLayout.frame(container: geometry.size, content: contentSize, keyboardTop: top)
            let relativeInput = RemoteKeyboardLayout.trackpadFrame(container: geometry.size, keyboardTop: inputTop,
                railLeading: railFrame.isEmpty ? nil : railFrame.minX - geometry.frame(in: .global).minX)
            ZStack(alignment: .topLeading) {
                Color.black
                ZStack {
                    Group {
                        if localDemo { MonitorView(session: session) }
                        else { LANMonitor(client: client) { releaseInteractions(); camera.stop(); showingConnect = true } }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    if directTouchSelected && !localDemo { workspaceInput.allowsHitTesting(!viewportAnimating) }
                }
                .frame(width: desktop.width, height: desktop.height)
                .clipped()
                .position(x: desktop.midX, y: desktop.midY)
                .animation(keyboardResizeAnimation, value: desktop)
                if !directTouchSelected || localDemo {
                    workspaceInput
                        .frame(width: relativeInput.width, height: relativeInput.height)
                        .clipped().position(x: relativeInput.midX, y: relativeInput.midY)
                        .allowsHitTesting(!viewportAnimating && !modalVisible)
                }
            }
            .onChange(of: relativeInput) { _, _ in inputEpoch += 1; client.release() }
            .background(KeyboardOcclusionReader { top, duration, curve in
                keyboardResizeDuration = duration; keyboardResizeCurve = curve
                nativeKeyboardTop = top
            }.allowsHitTesting(false))
            .onChange(of: desktop) { _, _ in
                // Old contacts must not continue using coordinates from before
                // the keyboard resize. Keep the rear chord and IME state intact.
                inputEpoch += 1; client.release()
                let token = UUID(); viewportAnimationID = token
                viewportAnimating = !reduceMotion && keyboardResizeDuration > 0
                Task {
                    try? await Task.sleep(for: .seconds(keyboardResizeDuration))
                    if viewportAnimationID == token { viewportAnimating = false }
                }
            }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { workspaceFrame = $0 }
            .onAppear { workspaceHeight = geometry.size.height }
            .onChange(of: geometry.size) { _, _ in
                workspaceHeight = geometry.size.height
                // Native keyboard safe-area changes must not reset the rear clutch and reopen it.
                inputEpoch += 1; client.release(); resizeStart = nil
                if !useNativeKeyboard { grip.cancel() }
            }
        }
        .coordinateSpace(name: "workspace")
    }

    @ViewBuilder private var workspaceInput: some View {
        let epoch = inputEpoch
        if directTouchSelected && !localDemo {
            if client.supportsDirectTouch, let image = client.image {
                DirectTouchSurface(image: image,
                    enabled: client.acceptsInput && !modalVisible && !menuPresented && !viewportAnimating,
                    rearHeld: false, magnifierEnabled: magnifierEnabled,
                    windowGesturesEnabled: rearWindowGestures,
                    readRearContacts: { camera.running && camera.enabled ? grip.state.outerCount : 0 },
                    onWindowOverview: { action in
                        guard frontInputIsCurrent(.direct, epoch: epoch) else { return }
                        sendWindowOverview(action)
                    }, revision: client.captureRevision,
                    resetToken: directResetToken, inputEpoch: inputEpoch,
                    readRearHeld: { false },
                    inputIsCurrent: { frontInputIsCurrent(.direct, epoch: epoch) },
                    onContacts: { if frontInputIsCurrent(.direct, epoch: epoch) { grip.innerContacts($0) } },
                    onScroll: { if frontInputIsCurrent(.direct, epoch: epoch) { client.scroll($0) } },
                    onEvent: { if frontInputIsCurrent(.direct, epoch: epoch) { client.directTouch($0) } })
            } else if client.connected && !client.supportsDirectTouch {
                Text("直接触屏需要 Mac 主机 0.7 或更新版本")
                    .padding().background(.bar).allowsHitTesting(false)
            }
        } else {
            TouchpadSurface(behavior: .standard, inputEpoch: epoch,
                inputIsCurrent: { frontInputIsCurrent(.trackpad, epoch: epoch) }, onContactCount: { count in
                guard frontInputIsCurrent(.trackpad, epoch: epoch) else { return }
                grip.innerContacts(count)
                if count > 0 { TouchFeedback.shared.prepare() }
            }, onScroll: localDemo ? nil : { sample in
                if frontInputIsCurrent(.trackpad, epoch: epoch) { client.scroll(sample) }
            }) { event in
                guard frontInputIsCurrent(.trackpad, epoch: epoch) else { return }
                grip.handle(TouchpadTuning.scale(event, by: innerSensitivity))
            }
            .accessibilityLabel("正面拇指触控板")
            .accessibilityIdentifier("grip-front-touchpad")
            .allowsHitTesting(!menuPresented && (localDemo || client.acceptsInput))
        }
    }

    @ViewBuilder private func keyboardOverlay(availableHeight: CGFloat) -> some View {
        if customKeyboardShown {
            let height = min(max(availableHeight * clampedKeyboardFraction, 4 * 44 + 24), availableHeight * 0.7)
            HStack(alignment: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    resizeHandle(availableHeight: availableHeight)
                    MobileTouchKeyboard(onAction: sendMobileInput)
                        .frame(height: height).clipped()
                }
                keyboardDock.frame(height: height)
            }
            .background(InputGlass(transparency: keyboardTransparency))
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { customKeyboardFrame = $0 }
            .disabled(menuPresented)
        }
    }

    private var modalVisible: Bool { showingDisplays || showingConnect || showingInputSettings || showingCameraControls || showingLog || showingDemoLog || showingGuide || showingAbout }
    private var directTouchSelected: Bool { grip.state.requestedFrontMode == .direct }
    private func frontInputIsCurrent(_ mode: FrontTouchMode, epoch: Int) -> Bool {
        inputEpoch == epoch && !modalVisible && !menuPresented && (localDemo || client.acceptsInput)
            && (localDemo ? mode == .trackpad : grip.state.requestedFrontMode == mode)
    }
    private var useNativeKeyboard: Bool { keyboardStyle == PhoneKeyboardStyle.system.rawValue && !localDemo && client.connected && client.supportsTextInput }
    private var nativeKeyboardWanted: Bool { useNativeKeyboard && grip.state.requestedMode == .keyboard && !modalVisible && client.acceptsInput }
    private var nativeKeyboardVisible: Bool { nativeKeyboardWanted && nativeKeyboard.visible }
    private func updateNativeKeyboardVisibility() {
        nativeKeyboard.update(wanted: nativeKeyboardWanted, frontContacts: grip.state.innerCount)
    }
    private var nativeTextContext: String { "\(client.textFocus?.id ?? "manual")/\(client.textFocus?.requestID ?? 0)/\(client.textInputEpoch)" }

    private func configureInputRouting() {
        // Rebind after mode changes so the accessory never uses an old SwiftUI view's routing.
        let direct = directTouchSelected && !localDemo
        let simulated = localDemo
        grip.onEvent = { event in
            if client.acceptsInput { TouchFeedback.shared.play(event) }
            if direct { if event == .dragEnded { client.release() }; return }
            if simulated { session.touchpad(event) } else { client.touchpad(event, origin: "inner-grip") }
        }
    }

    private func chooseInnerMode(_ mode: InnerInputMode) {
        keyboardPolicy.suppress(through: client.sentEvents)
        inputEpoch += 1; grip.releaseFront(); client.release(); keyboardController.reset()
        automaticInnerMode = mode
        configureGrip()
    }

    private func updateAutomaticKeyboard() {
        guard useNativeKeyboard, !menuPresented, keyboardInvocation == KeyboardInvocation.automatic.rawValue, let focus = client.textFocus else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000)
            guard keyboardInvocation == KeyboardInvocation.automatic.rawValue,
                  client.textFocus == focus, client.acceptsInput, !modalVisible, !menuPresented,
                  let mode = keyboardPolicy.mode(for: focus, frontContacts: grip.state.innerCount,
                                                 rearContacts: grip.state.outerCount) else { return }
            // Runtime focus behavior must never overwrite the user's saved default.
            automaticInnerMode = mode
        }
    }

    private func openCameraControls() {
        releaseInteractions()
        pendingCameraMode = nil
        showingCameraControls = true
    }

    private func applyPendingCameraMode() {
        guard let mode = pendingCameraMode else { return }
        pendingCameraMode = nil
        // Start only after the system sheet has dismissed and the main scene is full screen.
        releaseInteractions()
        rearAutoStart = true; camera.mode = mode
        camera.enabled = true
        updateRearCapture()
        camera.start()
    }

    private var clampedKeyboardFraction: Double { min(max(keyboardFraction, 0.20), 0.45) }

    private func resizeHandle(availableHeight: CGFloat) -> some View {
        Label("覆盖层 \(Int((clampedKeyboardFraction * 100).rounded()))% · 拖动调整", systemImage: "arrow.up.and.down")
            .font(.caption2).foregroundStyle(.secondary)
            .padding(.vertical, 8).frame(maxWidth: .infinity).background(.bar)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 4, coordinateSpace: .named("workspace"))
                .onChanged { value in
                    guard grip.state.innerCount == 0 else { return }
                    if resizeStart == nil { resizeStart = clampedKeyboardFraction }
                    keyboardFraction = min(max((resizeStart ?? 0.25) - value.translation.height / max(availableHeight, 1), 0.20), 0.45)
                }
                .onEnded { _ in resizeStart = nil })
            .accessibilityLabel("键盘高度")
            .accessibilityValue("\(Int((clampedKeyboardFraction * 100).rounded()))%")
            .accessibilityAdjustableAction { direction in
                guard grip.state.innerCount == 0 else { return }
                keyboardFraction = min(max(clampedKeyboardFraction + (direction == .increment ? 0.01 : -0.01), 0.20), 0.45)
            }
            .accessibilityIdentifier("keyboard-resize-handle")
    }

    private func configureGrip() {
        client.release()
        grip.configure(defaultMode: automaticInnerMode ?? InnerInputMode(rawValue: innerDefaultMode) ?? .keyboard,
                       activation: RearActivation(rawValue: rearActivation) ?? .momentary,
                       trigger: RearTrigger(rawValue: rearTrigger) ?? .touch,
                       frontMode: FrontTouchMode(rawValue: frontTouchMode) ?? .direct)
    }

    private var inputSettings: some View {
        NavigationStack {
            Form {
                switch settingsCategory {
                case .shortcuts: shortcutSettings
                case .rear: rearSettings
                case .streaming: streamingSettings
                case .assistance: assistanceSettings
                }
            }
            .navigationTitle(settingsCategory.title)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { showingInputSettings = false } } }
        }.presentationDetents([.large])
    }

    @ViewBuilder private var shortcutSettings: some View {
        Section("编辑右侧快捷键") {
            Toggle("切换显示器", isOn: $showDisplayButton).accessibilityIdentifier("show-display-button")
            Toggle("切换操控模式", isOn: $showPointerModeButton).accessibilityIdentifier("show-pointer-mode-button")
            Toggle("窗口总览", isOn: $showOverviewButton).accessibilityIdentifier("show-overview-button")
            Text("三个快捷键默认显示。右侧栏可上下滑动；菜单和键盘按钮始终保留。窗口总览轻点打开、长按选择退出。").font(.footnote).foregroundStyle(.secondary)
        }
                Section("右侧按钮位置") {
                    Text("菜单与键盘按钮越过内容安全区，沿右侧系统状态区下方对齐。上下位置可调整；背面手指数提示固定在原位置，不随菜单移动。")
                        .font(.footnote).foregroundStyle(.secondary)
                    LabeledContent("菜单向下", value: "\(Int(controlRailTop * 100))%")
                    Slider(value: $controlRailTop, in: 0...0.25, step: 0.01) { Text("菜单垂直位置") }.accessibilityIdentifier("control-rail-top")
                    LabeledContent("键盘按钮向上", value: "\(Int(controlRailBottom * 100))%")
                    Slider(value: $controlRailBottom, in: 0...0.30, step: 0.01) { Text("键盘按钮垂直位置") }
                    Button("恢复默认按钮位置") { controlRailTop = 0; controlRailBottom = 0 }
                    Text("iPhone／微信键盘由系统管理，快捷键放在其上方靠右。选择“手机布局 · 可调”可将四个快捷入口放在键盘右侧，并调整键盘高度与玻璃透明度。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("文字输入") {
                    Toggle("键盘弹出时适配远程画面", isOn: $fitDesktopAboveKeyboard)
                        .accessibilityIdentifier("fit-desktop-above-keyboard")
                    Text("默认开启：画面保持宽高比，完整显示在键盘上方，底边贴住键盘；横屏可左右留边。关闭则保持原来的键盘覆盖方式，不改变 Mac 分辨率。")
                        .font(.footnote).foregroundStyle(.secondary)
                    Picker("键盘", selection: $keyboardStyle) {
                        ForEach(PhoneKeyboardStyle.allCases) { Text($0.title).tag($0.rawValue) }
                    }.accessibilityIdentifier("phone-keyboard-style")
                    Picker("键盘唤起", selection: $keyboardInvocation) {
                        ForEach(KeyboardInvocation.allCases) { Text($0.title).tag($0.rawValue) }
                    }.pickerStyle(.segmented).accessibilityIdentifier("keyboard-invocation")
                    Text("默认自动：点击识别出的 Mac 输入框后唤起；可切为手动。右下玻璃按钮轻点显示／收起，长按打开快捷菜单。仅远程桌面显示输入结果，不显示本地输入栏。")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("iPhone 输入法使用你已启用的系统或微信输入法，通过键盘上的切换键选择。拼音候选确认后发送到 Mac；右下 Dock 提供 Ctrl、Cmd、Option 和键盘菜单。")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("手机布局支持 ABC／123／#+= 切换，Shift 单次大写、连续双击锁定大写。它不提供拼音候选，中文输入请切回 iPhone 输入法。按键发送所显示的符号，不依赖 Mac 的物理键盘布局。")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("键盘由右下独立按钮或可编辑输入框唤出。背面不再控制键盘；只切换直接触控／触控板。自动弹出依赖 Mac 应用的辅助功能信息，无法识别时点右下键盘按钮。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("手机布局键盘 · 玻璃透明度") {
                    LabeledContent("键盘", value: "\(Int(keyboardTransparency * 100))%")
                    Slider(value: $keyboardTransparency, in: 0...0.95, step: 0.05) { Text("键盘透明度") }
                        .accessibilityIdentifier("keyboard-transparency")
                    Text("只在唤出键盘时显示玻璃覆盖层和高度分隔条。全屏触控不显示边界，直接保留完整桌面。透明度仅调整键盘背景；系统开启“降低透明度”时使用不透明背景。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("手机布局键盘占比 · \(Int((clampedKeyboardFraction * 100).rounded()))%") {
                    Slider(value: $keyboardFraction, in: 0.20...0.45, step: 0.01) { Text("键盘高度") }
                        .accessibilityIdentifier("keyboard-height-slider")
                    Text("也可以拖动桌面与键盘之间的分隔条。调节范围为可用空间的 20%–45%，设置会自动保存。")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("恢复 25%") { keyboardFraction = 0.25 }
                }
    }
    @ViewBuilder private var rearSettings: some View {
        Section("背屏控制") {
            Toggle("连接后自动启用背面", isOn: $rearAutoStart)
            Button("启用背面模式切换") {
                rearAutoStart = true; camera.start(); showingInputSettings = false
            }.accessibilityIdentifier("camera-mode-front-touch")
            if camera.running || camera.starting {
                Button("停止背屏控制", role: .destructive) {
                    rearAutoStart = false; releaseInteractions(); camera.stop()
                }
            }
            Text("相机辅助接口保持运行；画面不显示、不保存、不传输。").font(.footnote).foregroundStyle(.secondary)
        }
        RearControlSettings()
                Section("窗口与桌面组合手势") {
                    Toggle("背面一指＋正面双指上下／左右滑", isOn: $rearWindowGestures)
                    Text("仅直接触控：先按住背面一指，再用正面双指上滑打开 Mission Control，下滑发送 Esc 退出。一次手势仅触发一次；抬手后可再次操作。无背面一指时仍为本机缩放。主机通过系统 Mission Control 应用打开；左滑下一个桌面、右滑上一个桌面，需 Mac 0.18+ 及系统 Control＋左右方向键快捷键。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
        RearAreaSettings(camera: camera)
    }
    @ViewBuilder private var streamingSettings: some View {
        Section("显示器") {
            NavigationLink("显示器与文字大小") { LANDisplaySettings(client: client).onAppear { client.requestDisplays() } }
        }
        videoSettings
    }
    @ViewBuilder private var assistanceSettings: some View {
        Section("帮助与信息") {
            NavigationLink("Duo 操作手册") { operationGuide }
            NavigationLink("诊断信息") { diagnosticsView }
            NavigationLink("关于 Chordesk") { ChordAboutView() }
        }
                Section("全屏触控方式") {
                    Picker("操作方式", selection: $frontTouchMode) {
                        ForEach(FrontTouchMode.allCases) { Text($0.title).tag($0.rawValue) }
                    }.pickerStyle(.segmented).accessibilityIdentifier("front-touch-mode")
                    Text("点按目标；快速单指滑动滚动；按住约半秒再拖动选择，抬手释放；按住不移动、松手打开右键。双指捏合／平移只放大查看画面。背面仅切换直接触控与触控板。")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("捏合只改变手机查看比例，不修改 Mac 分辨率或文档缩放。触控板灵敏度不影响直接触屏的位置；本地模拟仍使用触控板。")
                        .font(.footnote).foregroundStyle(.secondary)
                    if directTouchSelected {
                        Button { directResetToken += 1 } label: { Label("还原画面缩放", systemImage: "arrow.down.right.and.arrow.up.left") }
                    }
                }
                Section("选字放大镜") {
                    Toggle("长按时显示放大镜", isOn: $magnifierEnabled).accessibilityIdentifier("touch-magnifier-toggle")
                    Text("放大镜浮在手指上方，显示实际落点和选字位置；只改变本机查看，不修改 Mac 缩放。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("内屏指针灵敏度 · \(Int((TouchpadTuning.sensitivity(innerSensitivity) * 100).rounded()))%") {
                    Slider(value: $innerSensitivity, in: 0.1...1.5, step: 0.05) { Text("内屏指针灵敏度") }
                        .accessibilityIdentifier("inner-sensitivity-slider")
                        .accessibilityValue("\(Int((TouchpadTuning.sensitivity(innerSensitivity) * 100).rounded()))%")
                    Text("默认 50%，100% 为原来的速度。移动和拖选同时生效，双指滚动保持原速度。设置自动保存。")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("恢复 50%") { innerSensitivity = TouchpadTuning.defaultSensitivity }
                }
                Section("统一滚动惯性 · \(client.scrollInertia, specifier: "%.1f")") {
                    Slider(value: $client.scrollInertia, in: 0...2, step: 0.1) { Text("惯性系数") }
                        .accessibilityIdentifier("scroll-inertia-slider")
                    Text("直接触屏单指、触控板双指共用。0 为关闭，1 为默认；系数越大，抬手后减速越慢、滚动越远。重新落指即停止惯性，不改变接触时的跟随速度。")
                        .font(.footnote).foregroundStyle(.secondary)
                    if client.connected && !client.supportsScrollDynamics {
                        Text("当前 Mac 主机不支持惯性，请更新主机；普通滚动仍可用。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Button("恢复惯性系数 1") { client.scrollInertia = ScrollTuning.defaultCoefficient }
                }
                Section("触感") {
                    Toggle("点击震动反馈", isOn: $clickFeedback)
                    Text("点击、右键、按住及松开左键时给出短促反馈；移动时不震动。实际强度受设备和系统触感设置影响。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
        Section("本地演练") {
            Button(localDemo ? "返回远控" : "本地模拟") {
                releaseInteractions(); camera.stop(); client.disconnect(); localDemo.toggle(); showingInputSettings = false
            }
            if localDemo { NavigationLink("交互记录") { InteractionLog(session: session).navigationTitle("交互记录") } }
        }
    }
    private var diagnosticsView: some View {
        List {
            Section("画面上的连接信息") {
                Toggle("显示连接信息", isOn: $showStreamMetadata).accessibilityIdentifier("show-stream-metadata")
                Picker("展示位置", selection: $metadataCorner) {
                    ForEach(MetadataCorner.allCases) { Text($0.title).tag($0.rawValue) }
                }.disabled(!showStreamMetadata).accessibilityIdentifier("metadata-position")
                Text("分辨率、接收 fps、视频 Mbps、往返 RTT。RTT 不等于从触控到画面的完整延迟。").font(.footnote).foregroundStyle(.secondary)
            }

                    Section(client.connectionNetwork.title) {
                        Text(client.status)
                        Text(client.connectionTiming)
                        Text("收到画面 \(client.receivedFrames) 帧 · \(client.videoMbps, specifier: "%.1f") Mbps · \(client.videoFPS, specifier: "%.0f") fps")
                        Text("发送操作 \(client.sentEvents) · Mac 确认 \(client.acknowledged)")
                        Text(client.lastScrollEnd)
                        Text(overviewMessage)
                        if overviewSequence > 0 {
                            Text("总览请求 #\(overviewSequence) · 最近 Mac 确认 #\(client.acknowledged)；确认仅代表事件投递，效果以桌面为准")
                        }
                    }
                    Section("相机辅助接口") {
                        Text(camera.status)
                        Text(camera.recoveryMessage)
                        Text("控制模式：\(camera.mode.title)")
                        Text("背面 \(grip.state.outerCount) 指 · 正面 \(grip.state.innerCount) 指 · \(grip.state.requestedFrontMode.title)")
                        Text("背面接收：\(grip.controlsPresented ? "菜单期间暂停" : "已启用") · 远控输入：\(client.acceptsInput ? "允许" : "暂停")")
                        Text("系统可用：\(camera.available ? "是" : "否")")
                        Text("外屏场景出现：\(camera.presented ? "是" : "否")")
                        Text("外屏触摸 \(camera.touchCount) · \(camera.lastTouch)")
                    }

        }.navigationTitle("诊断信息")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { showingInputSettings = false; showingLog = false } } }
    }

    private func releaseInteractions() { keyboardPolicy.suppress(through: client.sentEvents); inputEpoch += 1; grip.cancel(); keyboardController.reset(); client.release() }
}

private struct InputGlass: View {
    var transparency: Double
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        let opacity = 1 - min(max(transparency.isFinite ? transparency : 0.45, 0), 1)
        Group {
            if reduceTransparency { RoundedRectangle(cornerRadius: 18).fill(Color(uiColor: .secondarySystemBackground)) }
            else if #available(iOS 26.0, *) {
                Color.clear
                    .glassEffect(.regular, in: .rect(cornerRadius: 18))
                    .opacity(opacity)
            } else {
                RoundedRectangle(cornerRadius: 18).fill(.ultraThinMaterial).opacity(opacity)
            }
        }.allowsHitTesting(false)
    }
}

private struct EdgeDockGlass: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func body(content: Content) -> some View {
        let shape = Circle()
        if reduceTransparency { content.background(Color(uiColor: .secondarySystemBackground), in: shape) }
        else if #available(iOS 26.0, *) { content.background { shape.fill(.clear).glassEffect(.regular, in: shape).allowsHitTesting(false) } }
        else { content.background(.ultraThinMaterial, in: shape) }
    }
}

private enum ControlSettingsCategory: String, CaseIterable {
    case shortcuts = "shortcut-settings", rear = "rear-settings", streaming = "stream-settings", assistance = "assistance-settings"
    var title: String {
        switch self {
        case .shortcuts: "快捷键设置"
        case .rear: "背屏控制设置"
        case .streaming: "远程传输画质设置"
        case .assistance: "辅助功能设置"
        }
    }
    var symbol: String {
        switch self {
        case .shortcuts: "keyboard"
        case .rear: "hand.point.up.left"
        case .streaming: "display"
        case .assistance: "accessibility"
        }
    }
}
private enum MetadataCorner: String, CaseIterable, Identifiable {
    case topLeft, topRight, bottomLeft, bottomRight
    var id: String { rawValue }
    var isTrailing: Bool { self == .topRight || self == .bottomRight }
    var title: String {
        switch self { case .topLeft: "左上"; case .topRight: "右上"; case .bottomLeft: "左下"; case .bottomRight: "右下" }
    }
    var alignment: Alignment {
        switch self { case .topLeft: .topLeading; case .topRight: .topTrailing; case .bottomLeft: .bottomLeading; case .bottomRight: .bottomTrailing }
    }
}

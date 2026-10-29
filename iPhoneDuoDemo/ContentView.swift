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
    @AppStorage("rearTriggerV2") private var rearTrigger = RearTrigger.longPress.rawValue
    @AppStorage("keyboardTransparency") private var keyboardTransparency = 0.45
    @AppStorage("primaryPointerMode") private var frontTouchMode = FrontTouchMode.direct.rawValue
    @AppStorage("showPointerModeButtonV1") private var showPointerModeButton = true
    @AppStorage("touchMagnifierEnabled") private var magnifierEnabled = true
    @State private var showingGuide = false
    @State private var showingAbout = false
    @AppStorage("phoneKeyboardStyle") private var keyboardStyle = PhoneKeyboardStyle.system.rawValue
    @AppStorage("keyboardInvocationV1") private var keyboardInvocation = KeyboardInvocation.manual.rawValue
    @AppStorage("rearControlAutoStartV1") private var rearAutoStart = true
    @AppStorage("rearWindowGesturesV1") private var rearWindowGestures = true
    @AppStorage("controlRailTopV1") private var controlRailTop = 0.0
    @AppStorage("controlRailBottomV1") private var controlRailBottom = 0.0
    @State private var menuPresented = false
    @State private var statusAreaBottom: CGFloat = 0
    @State private var edgeBarBottom: CGFloat = 0
    @State private var edgeBarWidth: CGFloat = 0
    @State private var edgeAnchorX: CGFloat?
    @State private var workspaceHeight: CGFloat = 0
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
                presentedWorkspace.ignoresSafeArea(.container).ignoresSafeArea(.keyboard)
            }
            .overlay(alignment: .bottom) {
                if nativeKeyboardVisible {
                    NativeKeyboardInput(active: !menuPresented, contextID: nativeTextContext, secure: client.textFocus?.secure ?? false,
                        onEdit: { client.nativeText($0) }, onKey: { client.nativeKey($0, modifiers: $1) },
                        onCursorKey: { client.nativeCursorKey($0) }, controller: keyboardController)
                        .frame(height: 0).allowsHitTesting(false).accessibilityHidden(true)
                }
            }
            // The contact badge keeps its original content-relative position.
            // It does not inherit the edge Dock offsets or keyboard avoidance.
            .overlay(alignment: .topTrailing) {
                if !modalVisible { rearStatusBadge.padding(.vertical).padding(.trailing) }
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
            }
            .onChange(of: client.selectedDisplayID) { _, _ in releaseInteractions() }
            .onChange(of: camera.mode) { _, _ in releaseInteractions() }
            .onChange(of: camera.enabled) { _, value in if !value { releaseInteractions() } }
            .onChange(of: camera.running) { _, value in if !value { releaseInteractions() } }
            .onChange(of: client.controlAllowed) { _, value in if !value { releaseInteractions() } else { updateRearCapture() } }
            .onChange(of: modalVisible) { _, value in
                client.inputSuspended = value
                if value { releaseInteractions(); if showingConnect { camera.stop() } }
                else { updateRearCapture() }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in client.inputSuspended = true; releaseInteractions() }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in client.inputSuspended = modalVisible; updateRearCapture() }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in releaseInteractions(); camera.stop(); client.disconnect() }
            .onDisappear { releaseInteractions(); camera.stop(); client.disconnect() }
        }
        // Attach outside NavigationStack's inset content proposal. Ignoring the
        // safe area on the old child alone did not recover the window's width.
        .overlay { controlRail }
        .overlay(alignment: .bottomLeading) {
            if client.microphoneEnabled {
                Button { client.setMicrophone(false) } label: {
                    Label("麦克风传输中 · 关闭", systemImage: "mic.fill").font(.caption).padding(10)
                }.buttonStyle(.plain).background(.ultraThinMaterial, in: Capsule()).padding()
                    .accessibilityIdentifier("remote-microphone-live")
            }
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
        .sheet(isPresented: $showingGuide) { operationGuide }
        .sheet(isPresented: $showingAbout) { ChordAboutView() }
        .sheet(isPresented: $showingLog) {
            NavigationStack {
                List {
                    Section("局域网") {
                        Text(client.status)
                        Text("收到画面 \(client.receivedFrames) 帧 · \(client.videoMbps, specifier: "%.1f") Mbps · \(client.videoFPS, specifier: "%.0f") fps")
                        Text("发送操作 \(client.sentEvents) · Mac 确认 \(client.acknowledged)")
                        Text(overviewMessage)
                        if overviewSequence > 0 {
                            Text("总览请求 #\(overviewSequence) · 最近 Mac 确认 #\(client.acknowledged)；确认仅代表事件投递，效果以桌面为准")
                        }
                    }
                    Section("相机辅助接口") {
                        Text(camera.status)
                        Text("控制模式：\(camera.mode.title)")
                        Text("背面 \(grip.state.outerCount) 指 · 正面 \(grip.state.innerCount) 指 · \(grip.state.requestedFrontMode.title)")
                        Text("背面接收：\(grip.controlsPresented ? "菜单期间暂停" : "已启用") · 远控输入：\(client.acceptsInput ? "允许" : "暂停")")
                        Text("系统可用：\(camera.available ? "是" : "否")")
                        Text("外屏场景出现：\(camera.presented ? "是" : "否")")
                        Text("外屏触摸 \(camera.touchCount) · \(camera.lastTouch)")
                    }
                }
                .navigationTitle("诊断信息")
                .toolbar { ToolbarItem { Button("完成") { showingLog = false } } }
            }
        }
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
            .init(id: "connect", title: "连接 Mac", symbol: "network"),
            .init(id: directTouchSelected ? "trackpad" : "direct", title: directTouchSelected ? "切为触控板" : "切为直接触控", symbol: "hand.tap"),
            .init(id: "displays", title: "显示器与文字大小", symbol: "display"),
            .init(id: "magnifier", title: "选字放大镜", symbol: "magnifyingglass", selected: magnifierEnabled),
            .init(id: "overview-show", title: "打开窗口总览", symbol: "rectangle.3.group", enabled: client.acceptsInput),
            .init(id: "overview-hide", title: "退出窗口总览", symbol: "rectangle", enabled: client.acceptsInput),
            .init(id: "desktop-previous", title: "上一个桌面", symbol: "arrow.left.square", enabled: client.acceptsInput && client.supportsDesktopSwitch),
            .init(id: "desktop-next", title: "下一个桌面", symbol: "arrow.right.square", enabled: client.acceptsInput && client.supportsDesktopSwitch),
            .init(id: "zoom-reset", title: "还原查看缩放", symbol: "arrow.down.right.and.arrow.up.left")
        ]), SystemMenuSection(items: [
            .init(id: "camera", title: "相机背面切换", symbol: "camera"),
            .init(id: "microphone", title: client.microphoneEnabled || client.microphoneStarting ? "关闭 Duo 麦克风" : "开启 Duo 麦克风", symbol: client.microphoneEnabled ? "mic.fill" : "mic.slash", enabled: client.microphoneAvailable),
            .init(id: "settings", title: "键盘、画质与触控设置", symbol: "slider.horizontal.3"),
            .init(id: "guide", title: "操作指南", symbol: "questionmark.circle"),
            .init(id: "about", title: "关于 Chordesk", symbol: "info.circle"),
            .init(id: "diagnostics", title: "诊断信息", symbol: "list.bullet.rectangle"),
            .init(id: "demo", title: localDemo ? "返回远控" : "本地模拟", symbol: "rectangle.on.rectangle")
        ])]
        if localDemo { sections.append(.init(items: [.init(id: "demo-log", title: "交互记录", symbol: "text.badge.checkmark")])) }
        if client.connected { sections.append(.init(items: [.init(id: "disconnect", title: "断开 Mac", symbol: "network.slash", destructive: true)])) }
        return sections
    }
    private func selectControl(_ id: String) {
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
        case "microphone": client.setMicrophone(!(client.microphoneEnabled || client.microphoneStarting))
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
    }
    private var controlRail: some View {
        GeometryReader { geometry in
            if !modalVisible {
                VStack(alignment: .trailing) {
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
                        StableMenuButton(symbol: "display", title: "显示器与文字大小", identifier: "display-dock-button", sections: [],
                            primaryAction: { releaseInteractions(); showingDisplays = true; client.requestDisplays() },
                            onPresentation: { _ in }, onSelect: { _ in }).modifier(EdgeDockGlass())
                    }
                        .padding(.top, geometry.size.height * ControlRailPosition.fraction(controlRailTop, maximum: 0.25))
                    Spacer(minLength: 0)
                    if !customKeyboardShown { keyboardDock
                        .padding(.bottom, geometry.size.height * ControlRailPosition.fraction(controlRailBottom, maximum: 0.30))
                    }
                }
                .padding(.vertical)
                .padding(.top, statusAreaBottom)
                .padding(.bottom, edgeBarBottom)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                .padding(.trailing, ControlRailPosition.trailingInset(containerWidth: geometry.size.width,
                    anchorX: edgeAnchorX, buttonWidth: edgeBarWidth))
            }
        }
        .background { SystemStatusBoundaryReader(extent: edgeBarWidth) { top, bottom, anchor in
            statusAreaBottom = top; edgeBarBottom = bottom; edgeAnchorX = anchor
        }.allowsHitTesting(false) }
        .ignoresSafeArea(.container)
    }

    private var rearStatusBadge: some View {
        Button(action: openCameraControls) {
            Label(camera.running && camera.presented ? "\(grip.state.outerCount)" : "—",
                  systemImage: camera.running && camera.presented ? "camera.fill" : "camera")
                .font(.caption2).padding(.horizontal).padding(.vertical, 6)
        }
        .buttonStyle(.plain).background(.ultraThinMaterial, in: Capsule())
        .foregroundStyle(camera.running && camera.presented ? Color.secondary : Color.secondary)
        .accessibilityIdentifier("rear-status-badge")
        .accessibilityLabel("背面状态：\(camera.status)，\(grip.state.outerCount) 指，\(grip.state.requestedFrontMode.title)")
        .overlay(alignment: .leading) {
            if camera.running && camera.presented && !directTouchSelected {
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
#if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.environment["DUO_UI_FIXTURE"] == "1" { return }
#endif
        guard #available(iOS 27.1, *), rearAutoStart, client.acceptsInput,
              !modalVisible, !localDemo, UIApplication.shared.applicationState == .active else { return }
        camera.start()
    }
    private func sendWindowOverview(_ action: WindowOverviewAction) {
        guard client.acceptsInput else { return }
        keyboardPolicy.suppress(through: client.sentEvents)
        keyboardController.reset(); client.release()
        guard client.windowOverview(action) else {
            overviewMessage = action.isDesktopSwitch ? "切换桌面需要 Mac 主机 0.18 或更新版本" : "窗口总览需要 Mac 主机 0.10.2 或更新版本"
            overviewSequence = 0
            return
        }
        overviewSequence = client.sentEvents
        overviewMessage = "已请求 Mac：" + action.title
    }

    private var videoSettings: some View {
        Section("远程画质") {
            if let quality = client.videoQuality {
                Picker("画质", selection: Binding(get: { quality }, set: { client.setVideoQuality($0) })) {
                    ForEach(client.availableVideoQualities) { Text($0.title).tag($0) }
                }.disabled(!client.canSwitchDisplays || client.switchingDisplay)
                Text(quality.detail).font(.caption)
            } else { Text("连接新版主机后可调整画质") }
            Text("实际视频载荷 \(client.videoMbps, specifier: "%.1f") Mbps · \(client.videoFPS, specifier: "%.0f") fps")
            if let rate = client.sourceRefreshRate {
                Text("Mac 显示模式标称刷新率 \(rate, specifier: "%.0f") Hz").font(.caption)
            }
            Text("清晰为默认。60 fps 降低传输分辨率；120／144 fps 为实验上限，实际受源屏刷新率、编码、网络和手机显示能力限制，静止画面会减少帧数。这里统计收到的视频帧，不等于屏幕实际刷新率。低分辨率不改变文字大小；文字过小请使用显示器菜单。")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private var operationGuide: some View {
        NavigationStack {
            List {
                Section("连接与显示") {
                    Text("首次扫码绑定，之后从已配对 Mac 一键连接。右上手指按钮切换直接触控／触控板，显示器按钮调整屏幕与文字大小，菜单包含全部操作。手指按钮可在设置的“全屏触控方式”中隐藏。")
                    Text("看不清文字：先选清晰／超清；目标太小：显示器与文字大小 → 适合触屏／更大文字／最大文字。")
                }
                Section("直接触控 · 默认") {
                    Text("点按：点击；双击：沿用 Mac 双击。快速单指滑动：滚动。")
                    Text("按住约半秒后拖动：选择文字／拖动，抬手释放。按住后不移动、松手：右键菜单。")
                    Text("长按显示可关闭的放大镜；双指捏合／平移用于查看局部，不改变 Mac 文档或分辨率。")
                }
                Section("触控板") {
                    Text("单指移动光标，轻点点击；按住后拖动选择；双指滚动，双指轻点右键。手指不必压在目标上。")
                }
                Section("背面只切换模式") {
                    Text("连接成功并允许控制后默认启用背面（仍需相机权限）。背面双指长按临时切换触控板，少于两指时恢复；也可设触发一次切换。右上标志显示背面状态与指针模式。")
                    Text("背面不再移动、点击、滚动、拖选，也不呼出键盘。相机背面切换 → 可视化调整区域：拖动绿色矩形移动、拖四角缩放，可贴边，修改自动保存。关闭自定义区域后恢复简易边缘禁触。")
                    Text("直接触控时：先保持背面一指，再用正面双指上滑打开窗口总览，下滑发送 Esc 退出。每次抬手后可重新触发。无背面一指时仍是捏合／平移。主机通过系统 Mission Control 应用打开；右侧菜单也可触发。")
                    Text("背面一指＋正面双指左滑：下一个桌面；右滑：上一个桌面。需 Mac 主机 0.18 或更新、至少两个桌面，并在系统键盘快捷键 → Mission Control 中启用 Control＋左右方向键。到达边缘不会循环；多显示器时由 macOS 的当前活动屏幕决定。")
                }
                Section("键盘与快捷键") {
                    Text("默认手动唤起：右下玻璃键盘按钮轻点显示／收起，长按打开快捷菜单；设置可改为点击输入框自动唤起。没有本地输入栏，文字结果直接看远程桌面。")
                    Text("键盘显示时右侧 Dock 为 Ctrl、Cmd、Option 和键盘菜单四个按钮。修饰键可组合锁存，下一次快捷键后释放；再次点已点亮的键可取消。")
                    Text("手机布局提供 ABC／123／#+= 切换和键盘右侧快捷键；中文请使用 iPhone 输入法。")
                    Text("长按系统键盘空格后滑动可移动 Mac 文字光标；第三方键盘需要支持系统浮动光标回调。键盘长按菜单保留四向键回退。")
                }
                Section("结束") { Text("断开会释放输入，并恢复连接前分辨率和显示器排列。失败记录保留供主机重试；强制退出需等下次启动恢复。") }
            }.navigationTitle("操作指南")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { showingGuide = false } } }
        }
    }

    private var workspace: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                Group {
                    if localDemo { MonitorView(session: session) }
                    else { LANMonitor(client: client) { releaseInteractions(); camera.stop(); showingConnect = true } }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                workspaceInput
            }
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
        if (grip.state.overlayVisible || useNativeKeyboard) && directTouchSelected && !localDemo {
            if client.supportsDirectTouch, let image = client.image {
                DirectTouchSurface(image: image,
                    enabled: client.acceptsInput && !modalVisible && !menuPresented && (useNativeKeyboard || grip.state.requestedMode == .touchpad),
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
                    onEvent: { if frontInputIsCurrent(.direct, epoch: epoch) { client.directTouch($0) } })
            } else if client.connected && !client.supportsDirectTouch {
                Text("直接触屏需要 Mac 主机 0.7 或更新版本")
                    .padding().background(.bar).allowsHitTesting(false)
            }
        } else if grip.state.overlayVisible || useNativeKeyboard {
            TouchpadSurface(behavior: .standard, inputEpoch: epoch,
                inputIsCurrent: { frontInputIsCurrent(.trackpad, epoch: epoch) }, onContactCount: { count in
                guard frontInputIsCurrent(.trackpad, epoch: epoch) else { return }
                grip.innerContacts(count)
                if count > 0 { TouchFeedback.shared.prepare() }
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
                       trigger: RearTrigger(rawValue: rearTrigger) ?? .longPress,
                       frontMode: FrontTouchMode(rawValue: frontTouchMode) ?? .direct)
    }

    private var inputSettings: some View {
        NavigationStack {
            Form {
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
                    Picker("键盘", selection: $keyboardStyle) {
                        ForEach(PhoneKeyboardStyle.allCases) { Text($0.title).tag($0.rawValue) }
                    }.accessibilityIdentifier("phone-keyboard-style")
                    Picker("键盘唤起", selection: $keyboardInvocation) {
                        ForEach(KeyboardInvocation.allCases) { Text($0.title).tag($0.rawValue) }
                    }.pickerStyle(.segmented).accessibilityIdentifier("keyboard-invocation")
                    Text("默认手动：右下玻璃按钮轻点显示／收起，长按打开快捷菜单。自动：点击识别出的 Mac 输入框后唤起。仅远程桌面显示输入结果，不显示本地输入栏。")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("iPhone 输入法使用你已启用的系统或微信输入法，通过键盘上的切换键选择。拼音候选确认后发送到 Mac；右下 Dock 提供 Ctrl、Cmd、Option 和键盘菜单。")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("手机布局支持 ABC／123／#+= 切换，Shift 单次大写、连续双击锁定大写。它不提供拼音候选，中文输入请切回 iPhone 输入法。按键发送所显示的符号，不依赖 Mac 的物理键盘布局。")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("键盘由右下独立按钮或可编辑输入框唤出。背面不再控制键盘；只切换直接触控／触控板。自动弹出依赖 Mac 应用的辅助功能信息，无法识别时点右下键盘按钮。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("全屏触控方式") {
                    Toggle("显示独立触控模式按钮", isOn: $showPointerModeButton).accessibilityIdentifier("show-pointer-mode-button")
                    Text("按钮与显示器、菜单在右侧同一列，轻点切换直接触控／触控板。不依赖背面能力；使用背面和弦时可关闭此按钮。").font(.footnote).foregroundStyle(.secondary)
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
                Section("窗口与桌面组合手势") {
                    Toggle("背面一指＋正面双指上下／左右滑", isOn: $rearWindowGestures)
                    Text("仅直接触控：先按住背面一指，再用正面双指上滑打开 Mission Control，下滑发送 Esc 退出。一次手势仅触发一次；抬手后可再次操作。无背面一指时仍为本机缩放。主机通过系统 Mission Control 应用打开；左滑下一个桌面、右滑上一个桌面，需 Mac 0.18+ 及系统 Control＋左右方向键快捷键。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                videoSettings
                Section("Duo 麦克风 → Mac") {
                    Toggle("本次连接开启麦克风", isOn: Binding(get: { client.microphoneEnabled || client.microphoneStarting }, set: { client.setMicrophone($0) }))
                        .disabled(!client.microphoneAvailable).accessibilityIdentifier("remote-microphone-toggle")
                    Toggle("连接后自动开启（默认关闭）", isOn: $client.autoStartMicrophone)
                        .accessibilityIdentifier("remote-microphone-autostart")
                    Text(client.microphoneMessage).font(.caption)
                    Text("Mac 主机需选择 BlackHole 等虚拟音频设备并允许接收；会议应用选择同名麦克风。仅在 App 前台传输，不保存录音。退到后台、断连或音频中断后停止。开启自动连接也不会绕过系统麦克风权限。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                RearControlSettings()
                Section("手机布局键盘 · 玻璃透明度") {
                    LabeledContent("键盘", value: "\(Int(keyboardTransparency * 100))%")
                    Slider(value: $keyboardTransparency, in: 0...0.95, step: 0.05) { Text("键盘透明度") }
                        .accessibilityIdentifier("keyboard-transparency")
                    Text("只在唤出键盘时显示玻璃覆盖层和高度分隔条。全屏触控不显示边界，直接保留完整桌面。透明度仅调整键盘背景；系统开启“降低透明度”时使用不透明背景。")
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
                RearAreaSettings(camera: camera)
                Section("手机布局键盘占比 · \(Int((clampedKeyboardFraction * 100).rounded()))%") {
                    Slider(value: $keyboardFraction, in: 0.20...0.45, step: 0.01) { Text("键盘高度") }
                        .accessibilityIdentifier("keyboard-height-slider")
                    Text("也可以拖动桌面与键盘之间的分隔条。调节范围为可用空间的 20%–45%，设置会自动保存。")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("恢复 25%") { keyboardFraction = 0.25 }
                }
                Section("触感") {
                    Toggle("点击震动反馈", isOn: $clickFeedback)
                    Text("点击、右键、按住及松开左键时给出短促反馈；移动时不震动。实际强度受设备和系统触感设置影响。")
                        .font(.footnote).foregroundStyle(.secondary)
                }

            }
            .navigationTitle("键盘与触控设置")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { showingInputSettings = false } } }
        }
        .presentationDetents([.large])
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

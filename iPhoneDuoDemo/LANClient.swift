#if os(iOS)
import SwiftUI
import UIKit
import Network
import ImageIO

@MainActor
final class LANClient: ObservableObject {
    @Published private(set) var rememberedMacs: [RememberedMac] = []
    @Published private(set) var rememberedPairingSaveFailed = false
    @Published private(set) var connected = false
    @Published private(set) var connecting = false
    @Published private(set) var controlAllowed = false
    @Published var inputSuspended = false {
        didSet { if inputSuspended { release() } }
    }
    var acceptsInput: Bool { connected && controlAllowed && !inputSuspended }
    @Published private(set) var image: CGImage?
    @Published private(set) var status = "通过局域网或 Tailscale 连接 Mac"
    @Published private(set) var connectionNetwork: RemoteNetwork = .lan
    @Published private(set) var sourceName = "Mac"
    @Published private(set) var receivedFrames = 0
    @Published private(set) var sentEvents: UInt64 = 0
    @Published private(set) var acknowledged: UInt64 = 0
    @Published private(set) var displays: [LANDisplay] = []
    @Published private(set) var selectedDisplayID: UInt32?
    @Published private(set) var displayName = ""
    @Published private(set) var canSwitchDisplays = false
    @Published private(set) var switchingDisplay = false
    @Published private(set) var displayMessage = "连接新版 Mac 主机后显示可用显示器"
    @Published private(set) var scaleState: LANScaleState?
    private var supportsDisplaySelection = false
    @Published private(set) var captureRevision: String?
    @Published private(set) var supportsDirectTouch = false
    @Published private(set) var supportsTextInput = false
    @Published private(set) var supportsWindowOverview = false
    @Published private(set) var supportsDesktopSwitch = false
    @Published private(set) var textFocus: LANTextFocus?
    @Published private(set) var mouseButtonDown = false
    @Published private(set) var textInputEpoch = 0
    @Published private(set) var videoQuality: LANVideoQuality?
    @Published private(set) var availableVideoQualities = LANVideoQuality.legacy
    @Published private(set) var sourceRefreshRate: Double?
    @Published private(set) var videoMbps = 0.0
    @Published private(set) var videoFPS = 0.0
    @Published private(set) var supportsMicrophone = false
    @Published private(set) var microphoneAvailable = false
    @Published private(set) var microphoneEnabled = false
    @Published private(set) var microphoneStarting = false
    @Published private(set) var microphoneMessage = "麦克风关闭；连接新版主机后可开启"
    @Published var autoStartMicrophone = UserDefaults.standard.bool(forKey: "ChordeskMicrophoneAutoStart") {
        didSet { UserDefaults.standard.set(autoStartMicrophone, forKey: "ChordeskMicrophoneAutoStart") }
    }
    private let microphone = PhoneMicrophone()
    private var microphoneRequestID: UUID?
    private var microphoneAutoStartAttempted = false
    private var microphoneTimeout: Task<Void, Never>?

    func setMicrophone(_ enabled: Bool) {
        if !enabled { stopMicrophone("麦克风已关闭"); return }
        guard connected, supportsMicrophone, microphoneAvailable, !microphoneEnabled, !microphoneStarting,
              UIApplication.shared.applicationState == .active else { return }
        let token = generation, id = UUID()
        microphoneRequestID = id; microphoneStarting = true; microphoneMessage = "等待麦克风权限与 Mac 音频设备"
        Task { [weak self] in
            let allowed = await PhoneMicrophone.permission()
            guard let self, generation == token, microphoneRequestID == id, connected else { return }
            guard allowed, UIApplication.shared.applicationState == .active else {
                stopMicrophone(allowed ? "请保持 Chordesk 在前台后重试" : "麦克风权限未允许，请在系统设置中开启")
                return
            }
            link?.send(.microphoneRequest, value: LANMicrophoneRequest(streamID: id, enabled: true))
            microphoneTimeout = Task { [weak self] in
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled, let self, self.microphoneRequestID == id, self.microphoneStarting else { return }
                self.stopMicrophone("Mac 麦克风连接超时，请检查主机音频设备")
            }
        }
    }
    func stopMicrophone(_ message: String = "麦克风已停止") {
        if let id = microphoneRequestID, supportsMicrophone {
            link?.send(.microphoneRequest, value: LANMicrophoneRequest(streamID: id, enabled: false))
        }
        microphoneRequestID = nil; microphoneTimeout?.cancel(); microphoneTimeout = nil
        microphone.stop(); microphoneEnabled = false; microphoneStarting = false; microphoneMessage = message
    }
    private func receiveMicrophoneState(_ state: LANMicrophoneState) {
        microphoneAvailable = state.available
        if !state.available { stopMicrophone(state.message); return }
        if state.streamID == microphoneRequestID, let id = microphoneRequestID {
            if !state.active { stopMicrophone(state.message); return }
            guard microphoneStarting, !microphoneEnabled else { return }
            microphoneTimeout?.cancel(); microphoneTimeout = nil
            guard UIApplication.shared.applicationState == .active, let wire = link else { stopMicrophone(); return }
            do {
                try microphone.start(streamID: id, send: { [weak wire] data in wire?.send(.microphoneAudio, data: data, droppable: true) },
                    interrupted: { [weak self] in self?.stopMicrophone("系统打断或音频路线改变；麦克风已关闭，请手动重开") })
                microphoneEnabled = true; microphoneStarting = false; microphoneMessage = state.message
            } catch { stopMicrophone("麦克风无法启动：" + error.localizedDescription) }
        } else if !state.active, microphoneEnabled { stopMicrophone(state.message) }
        else if !microphoneEnabled, !microphoneStarting { microphoneMessage = state.message }
        if autoStartMicrophone && !microphoneAutoStartAttempted {
            microphoneAutoStartAttempted = true; setMicrophone(true)
        }
    }

    private var traffic = VideoTrafficMeter()
    private var link: LANLink?
    private var generation = UUID()
    private var heartbeat: Timer?
    private var lastPacket = Date()
    private var currentPairing: LANPairing?
    private var tailnetDialID: Int32?

    private struct RememberedPairing: Codable {
        var pairing: LANPairing
        var hostName: String
    }

    init() {
#if DEBUG && targetEnvironment(simulator)
        // Synthetic pixels for simulator UI checks; never captures or controls a Mac.
        if ProcessInfo.processInfo.environment["DUO_UI_FIXTURE"] == "1" {
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1600, height: 1000))
            image = renderer.image { context in
                UIColor.systemBackground.setFill(); context.fill(CGRect(x: 0, y: 0, width: 1600, height: 1000))
                ("Duo Preview\nRemote text selection\nHigh quality desktop" as NSString).draw(at: CGPoint(x: 100, y: 140), withAttributes: [.font: UIFont.systemFont(ofSize: 48), .foregroundColor: UIColor.label])
            }.cgImage
            if ProcessInfo.processInfo.environment["DUO_UI_PAIRED_MACS"] == "1" {
                rememberedMacs = [
                    .init(pairing: .init(host: "192.168.1.10", port: 49173, secret: "00112233445566778899aabbccddeeff"), hostName: "我的 Mac"),
                    .init(pairing: .init(host: "192.168.1.20", port: 49173, secret: "ffeeddccbbaa99887766554433221100"), hostName: "同学的 Mac")
                ]
            }
            connected = true; controlAllowed = true; supportsDirectTouch = true; supportsTextInput = true
            sourceName = "UI Fixture"; videoQuality = .sharp; captureRevision = "fixture"
            availableVideoQualities = LANVideoQuality.allCases
            if ProcessInfo.processInfo.environment["DUO_UI_LIVE_FRAMES"] == "1" {
                heartbeat = Timer.scheduledTimer(withTimeInterval: 1.0 / 24, repeats: true) { [weak self] _ in
                    Task { @MainActor in self?.receivedFrames += 1 }
                }
            }
            return
        }
#endif
        if let data = LANCredentialStore.read(account: "remembered-macs-v2") {
            if let library = try? JSONDecoder().decode(PairedMacLibrary.self, from: data) {
                rememberedMacs = library.hosts.filter { $0.pairing.isValid }
            } else { rememberedPairingSaveFailed = true }
        } else if let data = LANCredentialStore.read(account: "remembered-mac-v1"),
                  let saved = try? JSONDecoder().decode(RememberedPairing.self, from: data), saved.pairing.isValid {
            // Only retire the legacy credential after the complete new library is saved.
            rememberedMacs = [.init(pairing: saved.pairing, hostName: saved.hostName)]
            _ = saveLibrary(.init(hosts: rememberedMacs))
        }
    }

    func forgetRememberedMac(_ id: UUID) {
        var library = PairedMacLibrary(hosts: rememberedMacs); library.forget(id)
        _ = saveLibrary(library)
    }
    @discardableResult
    private func saveLibrary(_ library: PairedMacLibrary) -> Bool {
#if DEBUG && targetEnvironment(simulator)
        // UI fixtures must exercise deletion without accessing real credentials.
        if ProcessInfo.processInfo.environment["DUO_UI_FIXTURE"] == "1" {
            rememberedMacs = library.hosts; rememberedPairingSaveFailed = false
            return true
        }
#endif
        guard let data = try? JSONEncoder().encode(library),
              LANCredentialStore.write(data, account: "remembered-macs-v2") else {
            rememberedPairingSaveFailed = true; return false
        }
        rememberedMacs = library.hosts; rememberedPairingSaveFailed = false
        LANCredentialStore.remove(account: "remembered-mac-v1")
        return true
    }
    private func remember(_ pairing: LANPairing, hostName: String, hostID: String?) {
        var library = PairedMacLibrary(hosts: rememberedMacs)
        library.remember(pairing, name: hostName, hostID: hostID)
        if library.hosts != rememberedMacs || rememberedPairingSaveFailed { _ = saveLibrary(library) }
    }

    func connect(_ pairing: LANPairing) {
        disconnect()
        guard pairing.isValid else { status = "请检查所选连接模式、IPv4 地址、端口及 32 位配对密钥"; return }
        connectionNetwork = pairing.connectionNetwork
        let token = UUID(); generation = token
        connecting = true
        status = "正在通过\(pairing.connectionNetwork.title)验证配对并连接 Mac…"
        if pairing.connectionNetwork == .tailscale {
            Task {
                do {
                    let route = try await EmbeddedTailnet.shared.dial(pairing)
                    guard generation == token else { EmbeddedTailnet.shared.closeDial(route.identifier); return }
                    tailnetDialID = route.identifier
                    let connection = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: route.port)!,
                                                  using: LANTransport.parameters(secret: pairing.secret))
                    startWire(pairing, token: token, connection: connection)
                } catch {
                    guard generation == token else { return }
                    disconnect(); status = error.localizedDescription
                }
            }
        } else {
            let connection = NWConnection(host: NWEndpoint.Host(pairing.host), port: NWEndpoint.Port(rawValue: pairing.port)!,
                                          using: LANTransport.parameters(secret: pairing.secret))
            startWire(pairing, token: token, connection: connection)
        }
    }
    private func startWire(_ pairing: LANPairing, token: UUID, connection: NWConnection) {
        let wire = LANLink(connection)
        link = wire; connecting = true
        status = "正在通过\(pairing.connectionNetwork.title)验证配对并连接 Mac…"
        let name = UIDevice.current.name
        wire.onReady = { [weak self, weak wire] in
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                self.currentPairing = pairing
                self.connected = true; self.connecting = false; self.lastPacket = Date()
                self.status = "已通过\(pairing.connectionNetwork.title)建立加密连接，等待屏幕画面"
                wire?.send(.hello, value: LANHello(name: name))
                let heartbeat = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                    Task { @MainActor in
                        guard let self else { return }
                        if Date().timeIntervalSince(self.lastPacket) > 6 { self.disconnect(); self.status = "连接中断，控制已释放" }
                        else { self.link?.send(.ping) }
                        if let sample = self.traffic.sample(now: ProcessInfo.processInfo.systemUptime) {
                            self.videoMbps = sample.mbps; self.videoFPS = sample.fps
                        }
                    }
                }
                self.heartbeat = heartbeat
                RunLoop.main.add(heartbeat, forMode: .common)
            }
        }
        wire.onPacket = { [weak self] kind, data in
            // Image decoding happens on the connection queue, outside the UI actor.
            var decoded: CGImage?
            if kind == .frame, let source = CGImageSourceCreateWithData(data as CFData, nil) {
                decoded = CGImageSourceCreateThumbnailAtIndex(source, 0,
                    [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 4096,
                     kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary)
            }
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                self.lastPacket = Date()
                switch kind {
                case .frame:
                    self.traffic.record(bytes: data.count, now: ProcessInfo.processInfo.systemUptime)
                    if let decoded { self.image = decoded; self.receivedFrames += 1 }
                case .status:
                    guard let state = try? JSONDecoder().decode(LANStatus.self, from: data), state.version == 1 else {
                        self.disconnect(); self.status = "主机协议版本不兼容"; return
                    }
                    if self.captureRevision != state.captureRevision { self.image = nil }
                    self.captureRevision = state.captureRevision
                    self.selectedDisplayID = state.selectedDisplayID
                    self.displayName = state.displayName ?? ""
                    self.supportsDisplaySelection = state.supportsDisplaySelection ?? false
                    self.supportsDirectTouch = state.supportsDirectTouch ?? false
                    self.supportsTextInput = state.supportsTextInput ?? false
                    self.supportsWindowOverview = state.supportsWindowOverview ?? false
                    self.supportsDesktopSwitch = state.supportsDesktopSwitch ?? false
                    self.supportsMicrophone = state.supportsMicrophone ?? false
                    self.textFocus = state.textFocus
                    self.mouseButtonDown = state.mouseButtonDown ?? false
                    self.switchingDisplay = state.switchingDisplay ?? false
                    self.videoQuality = state.videoQuality.flatMap(LANVideoQuality.init(rawValue:))
                    self.availableVideoQualities = LANVideoQuality.supported(by: state.supportedVideoQualities)
                    self.sourceRefreshRate = state.sourceRefreshRate.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
                    self.sourceName = state.name
                    if let pairing = self.currentPairing { self.remember(pairing, hostName: state.name, hostID: state.hostID) }
                    self.controlAllowed = state.canControl
                    self.status = "\(self.connectionNetwork.title) · \(state.message)"
                case .microphoneState:
                    guard self.supportsMicrophone, data.count < 4096,
                          let state = try? JSONDecoder().decode(LANMicrophoneState.self, from: data) else { return }
                    self.receiveMicrophoneState(state)
                case .acknowledgement:
                    if let sequence = try? JSONDecoder().decode(UInt64.self, from: data) { self.acknowledged = sequence }
                case .displays:
                    guard data.count < 65536, let catalog = try? JSONDecoder().decode(LANDisplayCatalog.self, from: data) else { return }
                    self.displays = Array(catalog.displays.prefix(32))
                    self.canSwitchDisplays = catalog.canSwitch
                    self.displayMessage = catalog.message
                    self.scaleState = catalog.scale
                default: break
                }
            }
        }
        wire.onClose = { [weak self] reason in
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                self.disconnect()
                self.status = pairing.connectionNetwork == .tailscale
                    ? reason + "。请确认两端 Chordesk 内的 Tailscale 已连接同一私人网络、允许互访，且 Mac 已开启公网入口。"
                    : reason
            }
        }
        wire.start()
    }

    func touchpad(_ event: TouchpadEvent, origin: String = "inner") {
        if event == .leftClick || event == .rightClick || event == .dragBegan { textInputEpoch += 1 }
        var input = LANInput(event); input.origin = origin; send(input)
    }

    func directTouch(_ event: DirectTouchEvent) {
        guard supportsDirectTouch, event.isValid, image != nil else { return }
        // Release must remain possible while a sheet, disconnect or layout change cancels input.
        if event.action == .up { release(); return }
        guard acceptsInput else { return }
        if event.action == .tap || event.action == .context || event.action == .down { textInputEpoch += 1 }
        switch event.action {
        case .tap: TouchFeedback.shared.play(.leftClick)
        case .context: TouchFeedback.shared.play(.rightClick)
        default: break
        }
        send(LANInput(direct: event))
    }

    func nativeText(_ value: LANTextEdit) {
        guard acceptsInput, supportsTextInput, value.isValid else { return }
        var edit = value
        edit.focusID = textFocus?.editable == true ? textFocus?.id : nil
        edit.displayID = selectedDisplayID; edit.captureRevision = captureRevision
        sentEvents += 1; edit.sequence = sentEvents
        link?.send(.textInput, value: edit)
    }

    func nativeKey(_ key: String, modifiers: UInt) {
        textInputEpoch += 1
        send(LANInput(key: key, modifiers: modifiers))
    }
    @discardableResult
    func windowOverview(_ action: WindowOverviewAction) -> Bool {
        guard acceptsInput, action.isDesktopSwitch ? supportsDesktopSwitch : supportsWindowOverview else { return false }
        textInputEpoch += 1
        send(LANInput(overview: action))
        return true
    }

    func nativeCursorKey(_ key: String) {
        guard ["left", "right", "up", "down"].contains(key) else { return }
        // Floating-cursor updates must not change the input context mid-gesture.
        send(LANInput(key: key, modifiers: 0))
    }

    func key(_ value: String, session: DemoSession) {
        switch value {
        case "shift": session.shift.toggle(); return
        case "cmd": session.command.toggle(); return
        case "opt": session.option.toggle(); return
        case "ctrl": session.control.toggle(); return
        default: break
        }
        let flags: UInt = (session.shift ? 1 : 0) | (session.command ? 2 : 0) | (session.option ? 4 : 0) | (session.control ? 8 : 0)
        send(LANInput(key: value, modifiers: flags))
        session.shift = false; session.command = false; session.option = false; session.control = false
    }

    private func send(_ value: LANInput) {
        guard !inputSuspended else { return }
        guard connected, controlAllowed else { status = "请在 Mac 主机窗口开启“允许这台手机控制”"; return }
        var event = value
        event.displayID = selectedDisplayID; event.captureRevision = captureRevision
        sentEvents += 1; event.sequence = sentEvents
        link?.send(.input, value: event)
    }

    func setVideoQuality(_ quality: LANVideoQuality) {
        guard connected, videoQuality != nil, availableVideoQualities.contains(quality), canSwitchDisplays, !switchingDisplay else { return }
        release(); link?.send(.videoQuality, value: quality.rawValue)
    }

    func release() { link?.send(.release) }

    func requestDisplays() {
        guard connected, supportsDisplaySelection else {
            displayMessage = connected ? "请先将 Mac 主机更新到支持应用内切屏的版本" : "请先连接 Mac"
            return
        }
        link?.send(.requestDisplays)
    }

    func selectDisplay(_ id: UInt32) {
        guard connected, canSwitchDisplays, !switchingDisplay, displays.contains(where: { $0.id == id }) else { return }
        release()
        link?.send(.selectDisplay, value: id)
    }

    func adjustScale(_ choice: String) {
        guard connected, controlAllowed, let state = scaleState, state.canAdjust,
              state.displayID == selectedDisplayID,
              state.options.contains(where: { $0.id == choice }) || (choice == "restore" && state.canRestore) else { return }
        release()
        link?.send(.adjustScale, value: LANScaleRequest(displayID: state.displayID, choice: choice))
    }

    func disconnect() {
        stopMicrophone()
        supportsMicrophone = false; microphoneAvailable = false; microphoneAutoStartAttempted = false
        release()
        generation = UUID()
        currentPairing = nil
        if let id = tailnetDialID { EmbeddedTailnet.shared.closeDial(id); tailnetDialID = nil }
        heartbeat?.invalidate(); heartbeat = nil
        link?.close(); link = nil
        connected = false; connecting = false; controlAllowed = false
        image = nil; receivedFrames = 0; sentEvents = 0; acknowledged = 0
        displays = []; selectedDisplayID = nil; displayName = ""; canSwitchDisplays = false
        switchingDisplay = false; supportsDisplaySelection = false; captureRevision = nil
        supportsDirectTouch = false
        supportsWindowOverview = false; supportsDesktopSwitch = false
        supportsTextInput = false; textFocus = nil; mouseButtonDown = false; textInputEpoch += 1
        displayMessage = "连接新版 Mac 主机后显示可用显示器"
        scaleState = nil; videoQuality = nil; videoMbps = 0; videoFPS = 0; traffic = VideoTrafficMeter()
        availableVideoQualities = LANVideoQuality.legacy; sourceRefreshRate = nil
        status = "已断开连接"
    }
}

struct LANDisplaySettings: View {
    @ObservedObject var client: LANClient
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(client.displayMessage).font(.callout)
                    if client.switchingDisplay { ProgressView("正在切换显示器…") }
                    ForEach(client.displays) { display in
                        Button { client.selectDisplay(display.id) } label: {
                            HStack {
                                Label(display.name, systemImage: "display")
                                Spacer()
                                Text("\(Int(display.width))×\(Int(display.height))").font(.caption).foregroundStyle(.secondary)
                                if display.id == client.selectedDisplayID { Image(systemName: "checkmark") }
                            }
                        }
                        .disabled(!client.canSwitchDisplays || client.switchingDisplay || display.id == client.selectedDisplayID)
                    }
                } footer: {
                    Text("在 Mac 开启“允许手机切屏与缩放”后，可直接选择实体屏。缩放还需要 Mac 开启手机控制；切屏和缩放前会释放正在按住的鼠标。")
                }
                if let scale = client.scaleState {
                    Section {
                        Text("当前：\(scale.current)").font(.caption)
                        Text(scale.message).font(.footnote).foregroundStyle(.secondary)
                        if !scale.canAdjust { Label("暂不可调整：请检查 Mac 的控制与切屏授权，或等待当前调整完成", systemImage: "lock").font(.callout) }
                        else if !client.switchingDisplay { Text("以下档位可用，点“应用”切换").font(.callout) }
                        ForEach(scale.options) { option in
                            Button { client.adjustScale(option.id) } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(option.title).fontWeight(.medium)
                                        Text(option.detail).font(.caption)
                                    }
                                    Spacer()
                                    Label("应用", systemImage: "arrow.right.circle").font(.callout)
                                }
                                .foregroundStyle(scale.canAdjust && !client.switchingDisplay ? Color.primary : Color.secondary)
                                .contentShape(Rectangle())
                            }.disabled(!scale.canAdjust || client.switchingDisplay)
                                .accessibilityHint(scale.canAdjust ? "切换到这个文字大小" : "请先在 Mac 允许手机控制及切屏")
                        }
                        Button("恢复原设置") { client.adjustScale("restore") }
                            .disabled(!scale.canRestore || !scale.canAdjust || client.switchingDisplay)
                    } header: {
                        Text("显示模式 · 文字大小")
                    } footer: {
                        Text("改变的是 Mac 实体屏的逻辑分辨率；本机文字也会同步变大。首次调整前保存原模式，结束后点恢复；重启主机后仍保留恢复记录。")
                    }
                }
                Button { client.requestDisplays() } label: { Label("刷新列表", systemImage: "arrow.clockwise") }
            }
            .navigationTitle("切换显示器")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
}

struct LANMonitor: View {
    @ObservedObject var client: LANClient
    var connect: () -> Void
    var body: some View {
        ZStack {
            Color.black
            if let image = client.image {
                Image(decorative: image, scale: 1).resizable().scaledToFit()
                    .accessibilityLabel("\(client.sourceName) 的实时桌面")
                    .accessibilityIdentifier("lan-remote-monitor")
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "desktopcomputer").font(.largeTitle)
                    Text(client.connecting ? "正在连接…" : "连接你的 Mac").font(.title2)
                    Text(client.status).font(.callout).multilineTextAlignment(.center)
                    if !client.connecting { Button("输入 IP 或扫描二维码", action: connect).buttonStyle(.borderedProminent) }
                }
                .padding().foregroundStyle(.white)
            }

        }
        .clipped()
        .background(RemoteFrameRateHint(target: Int(client.videoQuality?.framesPerSecond ?? 24),
                                        frame: client.receivedFrames, active: client.connected && client.image != nil))
    }
}

/// Request high-refresh presentation only while fresh remote frames arrive.
/// The system still chooses the actual refresh rate; this is not an FPS counter.
private struct RemoteFrameRateHint: UIViewRepresentable {
    var target: Int
    var frame: Int
    var active: Bool
    func makeUIView(context: Context) -> FrameRateView { FrameRateView() }
    func updateUIView(_ view: FrameRateView, context: Context) { view.update(target: target, frame: frame, active: active) }
    static func dismantleUIView(_ view: FrameRateView, coordinator: ()) { view.stop() }
}

private final class FrameRateView: UIView {
    private final class TickTarget: NSObject {
        weak var owner: FrameRateView?
        @objc func tick() { owner?.tick() }
    }
    private let tickTarget = TickTarget()
    private var displayLink: CADisplayLink?
    private var target = 24
    private var frameNumber = -1
    private var active = false
    private var lastFrame = 0.0
    override init(frame: CGRect) { super.init(frame: frame); isUserInteractionEnabled = false; tickTarget.owner = self }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func didMoveToWindow() { super.didMoveToWindow(); stop(); configure() }
    func update(target: Int, frame: Int, active: Bool) {
        self.target = target; self.active = active
        if frame != frameNumber { frameNumber = frame; lastFrame = CACurrentMediaTime() }
        configure()
    }
    private func configure() {
        guard let scene = window?.windowScene, active, target >= 60 else { stop(); return }
        if displayLink == nil {
            if #available(iOS 27, *) { displayLink = scene.displayLink(target: tickTarget, selector: #selector(TickTarget.tick)) }
            else { displayLink = scene.screen.displayLink(withTarget: tickTarget, selector: #selector(TickTarget.tick)) }
            displayLink?.add(to: .main, forMode: .common)
        }
        let maximum = Float(min(target, scene.screen.maximumFramesPerSecond))
        displayLink?.preferredFrameRateRange = CAFrameRateRange(minimum: min(30, maximum), maximum: maximum, preferred: maximum)
        displayLink?.isPaused = CACurrentMediaTime() - lastFrame > 0.3
    }
    private func tick() { if CACurrentMediaTime() - lastFrame > 0.3 { displayLink?.isPaused = true } }
    func stop() { displayLink?.invalidate(); displayLink = nil }
    deinit { displayLink?.invalidate() }
}

struct LANConnectView: View {
    @ObservedObject var client: LANClient
    @Environment(\.dismiss) private var dismiss
    @State private var host = ""
    @State private var port = ""
    @State private var secret = ""
    @State private var showScanner = false
    @State private var error = ""
    @State private var forgetting: RememberedMac?
    @State private var network: RemoteNetwork = .lan
    @State private var initialized = false
    @ObservedObject private var tailnet = EmbeddedTailnet.shared
    var body: some View {
        NavigationStack {
            Form {
                Section("连接方式") {
                    Picker("连接方式", selection: $network) {
                        ForEach(RemoteNetwork.allCases) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented).accessibilityIdentifier("connection-network-mode")
                    if network == .lan {
                        Text("同一 Wi-Fi／局域网直接连接，不需要 Tailscale 或账号。")
                            .font(.footnote).foregroundStyle(.secondary)
                    } else {
                        EmbeddedTailnetControls()
                    }
                }
                if !client.rememberedMacs.isEmpty {
                    Section("已配对的 Mac · \(client.rememberedMacs.count) 台") {
                        ForEach(client.rememberedMacs) { saved in
                            VStack(alignment: .leading, spacing: 8) {
                                Button { if let pairing = saved.pairing(for: network) { client.connect(pairing); dismiss() } } label: {
                                    Label(saved.hostName.isEmpty ? "Mac" : saved.hostName, systemImage: "desktopcomputer")
                                }.buttonStyle(.borderless)
                                    .disabled(saved.pairing(for: network) == nil || (network == .tailscale && !tailnet.ready))
                                    .accessibilityIdentifier("lan-reconnect-" + saved.id.uuidString)
                                Text(saved.pairing(for: network).map { "\($0.connectionNetwork.title)配对 · \($0.host):\($0.port)" } ?? "尚未绑定此模式，请扫描 Mac 对应模式的二维码")
                                    .font(.caption).foregroundStyle(.secondary)
                                Button("忘记这台 Mac", role: .destructive) { forgetting = saved }
                                    .buttonStyle(.borderless)
                                    .accessibilityIdentifier("lan-forget-" + saved.id.uuidString)
                            }
                        }
                        Text("每台 Mac 分别记忆局域网和 Tailscale 地址，凭据仅保存在此 iPhone 钥匙串；同名不会合并。首次使用某种模式需扫描对应二维码，之后直接点选。一次连接一台。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section("在 Mac 开启服务，选择对应模式的二维码") {
                    Button { showScanner = true } label: { Label("扫描 Mac \(network.title)配对二维码", systemImage: "qrcode.viewfinder") }
                }
                Section("手动输入") {
                    TextField(network == .lan ? "Mac 局域网 IP，例如 192.168.1.10" : "Mac Tailscale IP，例如 100.100.1.10", text: $host).keyboardType(.decimalPad)
                        .accessibilityIdentifier("lan-host-address")
                    TextField("端口", text: $port).keyboardType(.numberPad)
                        .accessibilityIdentifier("lan-host-port")
                    SecureField("配对密钥（32 位）", text: $secret).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityIdentifier("lan-pairing-secret")
                    Button("配对并连接") {
                        let value = LANPairing(host: host.trimmingCharacters(in: .whitespacesAndNewlines), port: UInt16(port) ?? 0,
                                               secret: secret.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), network: network)
                        guard value.isValid else { error = network == .lan ? "检查局域网 IP、端口和 32 位密钥" : "请使用 Mac 的 Tailscale IPv4 地址（100.64–100.127），并检查端口和密钥"; return }
                        client.connect(value); dismiss()
                    }
                    .disabled(network == .tailscale && !tailnet.ready)
                    .accessibilityIdentifier("lan-connect")
                }
                Section {
                    Text("首次扫码绑定后可以直接重连。Tailscale 登录不代替 Chordesk 配对：两种模式都验证同一台 Mac 的加密凭据。公网地址仅支持 Tailscale IPv4，不接受任意公网 IP 或域名。")
                        .font(.footnote).foregroundStyle(.secondary)
                    if client.rememberedPairingSaveFailed {
                        Text("连接成功，但 iPhone 钥匙串没有保存配对信息；请再次扫码后重试。")
                            .font(.footnote).foregroundStyle(.red)
                    }
                    if !error.isEmpty { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle("连接 Mac")
            .tint(.gray)
            .onAppear {
                if !initialized { initialized = true; network = client.connectionNetwork; port = String(LANPairing.defaultPort) }
            }
            .onChange(of: network) { _, _ in host = ""; secret = ""; error = "" }
            .alert("忘记这台 Mac？", isPresented: Binding(get: { forgetting != nil }, set: { if !$0 { forgetting = nil } }), presenting: forgetting) { saved in
                Button("忘记", role: .destructive) { client.forgetRememberedMac(saved.id); forgetting = nil }
                Button("取消", role: .cancel) { forgetting = nil }
            } message: { saved in Text("只删除手机上的“\(saved.hostName.isEmpty ? "Mac" : saved.hostName)”记录，其他配对保留。下次需要重新扫码。") }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } } }
            .sheet(isPresented: $showScanner) {
                QRScannerView { result in
                    showScanner = false
                    if let value = LANPairing.parse(result) {
                        if value.connectionNetwork == .tailscale && !tailnet.ready {
                            network = .tailscale; error = "请先登录 Tailscale，再扫描公网配对二维码。"
                        } else { client.connect(value); dismiss() }
                    }
                    else { error = "不是有效的 Chordesk 配对二维码；请确认两端均使用支持该连接模式的版本" }
                }
            }
        }
    }
}
#endif

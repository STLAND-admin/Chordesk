#if os(macOS)
import AppKit
import ApplicationServices
import CoreImage
import Darwin
import Network
import ScreenCaptureKit
import Security
import SwiftUI

@MainActor
final class LANHost: NSObject, ObservableObject, SCContentSharingPickerObserver {
    @Published var allowsMicrophone = UserDefaults.standard.bool(forKey: "ChordeskAllowsMicrophone") {
        didSet { UserDefaults.standard.set(allowsMicrophone, forKey: "ChordeskAllowsMicrophone"); stopMicrophone("麦克风接收设置已改变"); sendMicrophoneState() }
    }
    @Published var microphoneDestination = UserDefaults.standard.string(forKey: "ChordeskMicrophoneDestination") ?? "" {
        didSet { UserDefaults.standard.set(microphoneDestination, forKey: "ChordeskMicrophoneDestination"); stopMicrophone("音频设备已改变，请在 Duo 重新开启麦克风"); sendMicrophoneState() }
    }
    @Published private(set) var microphoneDestinations: [MicrophoneDestination] = []
    @Published private(set) var microphoneMessage = "麦克风关闭；选择虚拟音频设备后可接收 Duo 语音"
    @Published private(set) var microphoneActive = false
    private var peerSupportsMicrophone = false
    private var microphoneGate = MicrophoneReceiveGate()
    private let microphonePlayer = MacMicrophonePlayer()
    private var lastMicrophonePacket = Date()
    private var microphoneRequestWindow = Date.distantPast
    private var microphoneStartCount = 0
    private var microphoneAvailable: Bool {
        allowsMicrophone && microphoneDestinations.contains { $0.id == microphoneDestination }
    }
    func refreshMicrophoneDevices() {
        microphoneDestinations = MicrophoneDevices.available()
        if microphoneActive && (!microphoneAvailable || !microphonePlayer.routeIsValid) {
            stopMicrophone("虚拟音频设备已断开，请重新选择后开启麦克风")
        }
        sendMicrophoneState()
    }
    private func sendMicrophoneState(requestID: UUID? = nil) {
        guard peerSupportsMicrophone else { return }
        link?.send(.microphoneState, value: LANMicrophoneState(streamID: requestID ?? microphoneGate.streamID,
            available: microphoneAvailable, active: microphoneActive, message: microphoneMessage))
    }
    private func stopMicrophone(_ message: String) {
        let previous = microphoneGate.streamID
        microphoneGate.stop(); microphonePlayer.stop(); microphoneActive = false; microphoneMessage = message
        sendMicrophoneState(requestID: previous)
    }
    private func requestMicrophone(_ request: LANMicrophoneRequest) {
        guard peerSupportsMicrophone, configuredPeer != nil, connected, sharing else { return }
        if !request.enabled {
            if microphoneGate.streamID == request.streamID { stopMicrophone("Duo 麦克风已关闭") }
            return
        }
        if microphoneGate.streamID == request.streamID { sendMicrophoneState(); return }
        if Date().timeIntervalSince(microphoneRequestWindow) > 10 { microphoneRequestWindow = Date(); microphoneStartCount = 0 }
        guard microphoneStartCount < 5 else { stopMicrophone("麦克风切换过于频繁，请稍后重试"); sendMicrophoneState(requestID: request.streamID); return }
        microphoneStartCount += 1
        stopMicrophone("正在准备虚拟麦克风")
        microphoneDestinations = MicrophoneDevices.available()
        guard microphoneAvailable, let destination = microphoneDestinations.first(where: { $0.id == microphoneDestination }) else {
            microphoneMessage = "请在 Mac 选择虚拟音频设备，并允许 Duo 麦克风接收"
            sendMicrophoneState(requestID: request.streamID); return
        }
        do {
            try microphonePlayer.start(device: destination.device)
            microphoneGate.start(request.streamID); microphoneActive = true; lastMicrophonePacket = Date()
            microphoneMessage = "正在接收 Duo 麦克风 → " + destination.name
        } catch { microphoneMessage = "音频设备启动失败：" + error.localizedDescription }
        sendMicrophoneState(requestID: request.streamID)
    }

    @Published var autoStartHost = UserDefaults.standard.object(forKey: "ChordeskAutoStartHost") as? Bool ?? true {
        didSet { UserDefaults.standard.set(autoStartHost, forKey: "ChordeskAutoStartHost") }
    }
    @Published var wakeDisplayOnConnect = UserDefaults.standard.object(forKey: "ChordeskWakeDisplayOnConnect") as? Bool ?? true {
        didSet { UserDefaults.standard.set(wakeDisplayOnConnect, forKey: "ChordeskWakeDisplayOnConnect") }
    }
    private let hostIdentity: String = {
        if let raw = UserDefaults.standard.string(forKey: "ChordeskHostIdentity"), let id = UUID(uuidString: raw) { return id.uuidString }
        let id = UUID().uuidString; UserDefaults.standard.set(id, forKey: "ChordeskHostIdentity"); return id
    }()
    @Published private(set) var status = "准备内置屏远控服务"
    @Published private(set) var pairing: LANPairing?
    @Published private(set) var tailscalePairings: [LANPairing] = []
    @Published private(set) var tailscaleAddresses: [String] = []
    @Published private(set) var tailscaleMessage = "在 Mac 和 iPhone 的 Tailscale 中登录同一私人网络，然后开启公网连接。"
    @Published var allowsTailscale = UserDefaults.standard.bool(forKey: "ChordeskAllowsTailscaleV1") {
        didSet {
            UserDefaults.standard.set(allowsTailscale, forKey: "ChordeskAllowsTailscaleV1")
            refreshTailscale()
        }
    }
    private var tailnetListener: NWListener?
    private let tailnet = EmbeddedTailnet.shared
    private var candidateNetworks: [UUID: RemoteNetwork] = [:]
    private var peerNetwork: RemoteNetwork = .lan
    private var lastTailscaleRefresh = Date.distantPast
    @Published private(set) var connected = false
    @Published private(set) var sharing = false { didSet { updateAwakeLease() } }
    @Published private(set) var controlAllowed = false
    @Published private(set) var inputCount = 0
    @Published private(set) var postedInputCount = 0
    @Published private(set) var accessibilityAllowed = false
    @Published private(set) var eventPostingAllowed = false
    @Published private(set) var frameCount = 0
    @Published private(set) var lastInput = "尚未收到操作"
    @Published private(set) var desktopAutomationAllowed = false
    @Published private(set) var desktopPermissionBusy = false
    @Published private(set) var desktopSwitchBusy = false
    @Published private(set) var desktopMessage = "桌面切换使用 System Events，需要单独允许自动化"
    @Published private(set) var desktopChangeCount = 0
    func refreshDesktopPermission() {
        desktopAutomationAllowed = DesktopSwitchCommand.permission() == noErr
    }
    func requestDesktopPermission() async {
        guard !desktopPermissionBusy else { return }
        desktopPermissionBusy = true
        defer { desktopPermissionBusy = false }
        let result = await DesktopSwitcher.requestPermission()
        desktopAutomationAllowed = result == noErr
        desktopMessage = result == noErr ? "System Events 已允许；重新触发桌面切换即可" : DesktopSwitchResult.error(Int(result)).message
        sendStatus()
    }
    func testDesktopSwitch(_ action: WindowOverviewAction) async {
        guard !desktopSwitchBusy, !desktopPermissionBusy, action.isDesktopSwitch else { return }
        desktopSwitchBusy = true
        defer { desktopSwitchBusy = false }
        input.release()
        let result = await DesktopSwitcher.perform(action) {
            AXIsProcessTrusted() && CGPreflightPostEventAccess() && !self.systemSleeping
        }
        desktopMessage = result.message
        refreshDesktopPermission()
    }
    @Published private(set) var clientName = ""
    @Published private(set) var addresses: [String] = []
    @Published var selectedAddress = ""
    @Published private(set) var displays: [LANDisplay] = []
    @Published private(set) var screenCaptureAllowed = false
    @Published private(set) var displayListMessage = "读取实体显示器列表并设置文字大小"
    @Published private(set) var switchingDisplay = false
    @Published private(set) var currentDisplayName = ""
    @Published var selectedDisplay: UInt32 = 0
    @Published var allowsDisplaySwitching = false { didSet { sendCatalog() } }
    @Published private(set) var scaleState: LANScaleState?
    @Published private(set) var adjustingScale = false
    @Published private(set) var restoringScale = false
    @Published var autoConfigurePairing = UserDefaults.standard.object(forKey: "DuoAutoConfigurePairing") as? Bool ?? true {
        didSet { UserDefaults.standard.set(autoConfigurePairing, forKey: "DuoAutoConfigurePairing") }
    }
    var scaleBusy: Bool { adjustingScale || restoringScale }
    private var scaleIdleWaiters: [CheckedContinuation<Void, Never>] = []
    private var scaleRestoreTask: Task<Void, Never>?
    @Published private(set) var restoreFailed = false
    @Published private(set) var pairingCredentialStored = false
    @Published private(set) var pairingCredentialLoading = true
    private var configuredPeer: UUID?
    private var latestFocusClick: UInt64 = 0
    @Published private(set) var scaleMessage = "内置显示模式 · 默认 1600×900"
    private let displayScaling = DisplayScalingService()
    @Published private(set) var scalingBackend = DisplayScalingBackend(rawValue: UserDefaults.standard.string(forKey: "ChordeskScalingBackend") ?? "") ?? .native
    func setScalingBackend(_ backend: DisplayScalingBackend) {
        guard !connected, !scaleBusy, !switchingDisplay, !restoreFailed, scaleState?.canRestore != true else { return }
        scalingBackend = backend
        UserDefaults.standard.set(backend.rawValue, forKey: "ChordeskScalingBackend")
        Task { await refreshScaleOptions() }
    }
    private var scaleRefreshToken = UUID()
    private var captureGeneration = UUID()
    private var captureRevision = UUID().uuidString
    private var peerSupportsDisplays = false
    private var controlRevision = 0
    private var displaySwitchOperation: UUID?
    private var listener: NWListener?
    private var link: LANLink?
    private var candidates: [UUID: LANLink] = [:]
    private var stream: SCStream?
    private var frames: LANFrameSource?
    private var timer: Timer?
    private var generation = UUID()
    private var pickerRegistered = false
    private var displayID: CGDirectDisplayID?
    private var lastPing = Date()
    private var latestFrame: Data?
    @Published private(set) var videoQuality = LANVideoQuality(rawValue: UserDefaults.standard.string(forKey: "DuoVideoQuality") ?? "") ?? .efficient
    @Published private(set) var videoMbps = 0.0
    @Published private(set) var videoFPS = 0.0
    private var traffic = VideoTrafficMeter()
    private let input = LANMacInput()
    private let focusMonitor = MacTextFocusMonitor()
    private var pairingSecret = ""
    private var textFocus: LANTextFocus?
    private var focusRequest: UInt64 = 0
    private var focusProbeRunning = false
    private enum PendingInput {
        case pointer(LANInput)
        case text(LANTextEdit)
    }
    private var pendingInputs: [PendingInput] = []
    private var drainingInputs = false
    private var inputQueueEpoch = 0
    private var observers: [NSObjectProtocol] = []
    private let awakeLease = HostAwakeLease()
    private var captureRecovery = CaptureRecovery()
    private var pendingAutomaticPeer: (LANLink, UUID, Int)?
    private let displayWake = AuthenticatedDisplayWake()
    private var runtimeActivity: NSObjectProtocol?
    private var captureInterrupted = false
    private var captureRepair: Task<Void, Never>?
    private var displaySleeping = false
    private var systemSleeping = false

    @Published private(set) var availabilityMessage = "等待共享；显示器息屏与系统睡眠分别处理"
    @Published var keepAwakeWhileSharing = UserDefaults.standard.object(forKey: "DuoKeepAwakeWhileSharing") as? Bool ?? true {
        didSet { UserDefaults.standard.set(keepAwakeWhileSharing, forKey: "DuoKeepAwakeWhileSharing"); updateAwakeLease() }
    }
    private func updateAwakeLease() {
        awakeLease.update(sharing: sharing, enabled: keepAwakeWhileSharing)
        // Keep network/capture work schedulable when the window is closed, without holding the display on.
        if sharing && runtimeActivity == nil {
            runtimeActivity = ProcessInfo.processInfo.beginActivity(options: [.userInitiatedAllowingIdleSystemSleep], reason: "Chordesk remote service")
        } else if !sharing, let activity = runtimeActivity {
            ProcessInfo.processInfo.endActivity(activity); runtimeActivity = nil
        }
    }
    private func releaseQueuedInput() {
        input.release(); inputQueueEpoch += 1; pendingInputs.removeAll(); textFocus = nil
    }
    private func capturePaused() {
        guard !captureRecovery.paused else { return }
        captureRecovery.pause(allowed: controlAllowed, revision: controlRevision)
        releaseQueuedInput(); controlAllowed = false; latestFrame = nil
        availabilityMessage = "捕获暂时无画面；保持连接，等待新画面后核对原控制许可"
        status = availabilityMessage; sendStatus(); sendCatalog()
    }
    private func captureResumed() {
        guard captureRecovery.paused else { return }
        refreshInputPermissions()
        let resume = captureRecovery.receivedFrame(revision: controlRevision,
            eligible: connected && sharing && accessibilityAllowed && eventPostingAllowed && !switchingDisplay && !scaleBusy)
        controlAllowed = resume
        availabilityMessage = resume ? "画面已恢复，原控制许可仍有效" : "画面已恢复；控制保持关闭"
        status = availabilityMessage; sendStatus(); sendCatalog()
        if let (peer, token, revision) = pendingAutomaticPeer {
            pendingAutomaticPeer = nil
            if token == generation && revision == controlRevision && link === peer {
                Task { await self.configurePairedPhone(peer, generation: token, expectedRevision: revision) }
            }
        }
    }

    /// Explicit entry point used by launch and the primary Start button.
    func startDefaultDisplay() async {
        guard !sharing, !switchingDisplay, !pairingCredentialLoading else { return }
        await refreshDisplays()
        guard let id = DefaultHostDisplay.choose(displays.map(\.id), builtIn: { CGDisplayIsBuiltin($0) != 0 }, main: CGMainDisplayID()) else {
            status = "未找到可共享显示器"; return
        }
        selectedDisplay = id
        await selectDisplay(id)
    }

    private func retryInterruptedCapture() {
        guard sharing, !systemSleeping, !displaySleeping, !switchingDisplay, !scaleBusy,
              captureInterrupted, captureRepair == nil, let id = displayID else { return }
        guard CGPreflightScreenCaptureAccess() else { stop(); status = "屏幕录制权限已撤销，请在设置中重新授权"; return }
        let token = generation
        captureRepair = Task { [weak self] in
            guard let self else { return }
            defer { self.captureRepair = nil }
            for delay in [1, 2, 4] {
                do { try await Task.sleep(for: .seconds(delay)) } catch { return }
                guard !Task.isCancelled, self.generation == token, self.sharing, !self.systemSleeping,
                      !self.displaySleeping, !self.scaleBusy, !self.switchingDisplay else { return }
                guard CGPreflightScreenCaptureAccess() else { self.stop(); return }
                do {
                    let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
                    guard self.generation == token, let display = content.displays.first(where: { $0.displayID == id }) else { return }
                    try await self.installCapture(SCContentFilter(display: display, excludingWindows: []), display: display,
                        sessionToken: token, preserveRecovery: true)
                    self.captureInterrupted = false
                    self.status = "捕获已恢复，等待新画面"; self.sendStatus(); return
                } catch { self.availabilityMessage = "捕获恢复尚未成功；可重新连接后再试" }
            }
        }
    }

    override init() {
        super.init()
        input.scrollPermission = { [weak self] in
            guard let self else { return false }
            return self.connected && self.controlAllowed && self.sharing && !self.switchingDisplay
                && !self.scaleBusy && !self.systemSleeping && !self.captureRecovery.paused
                && AXIsProcessTrusted() && CGPreflightPostEventAccess()
        }
        // This standalone Mac build uses the file-based Keychain. Refuse optional
        // password dialogs rather than blocking startup on a legacy item ACL.
        // Access is still denied by Keychain when authentication is required.
        SecKeychainSetUserInteractionAllowed(false)
        // Keep storage work off the main thread even when a locked Keychain
        // rejects it; the display picker must remain responsive.
        Task {
            let credential = await Task.detached { () -> (String, Bool) in
                if let data = LANCredentialStore.read(account: "host-pairing-v2-signed"),
                   let saved = String(data: data, encoding: .utf8), LANPairing.isValidSecret(saved) {
                    return (saved, true)
                }
                guard let secret = try? LANPairing.newSecret() else { return ("", false) }
                return (secret, LANCredentialStore.write(Data(secret.utf8), account: "host-pairing-v2-signed"))
            }.value
            self.pairingSecret = credential.0
            self.pairingCredentialStored = credential.1
            self.pairingCredentialLoading = false
        }
        refreshAddresses()
        refreshMicrophoneDevices()
        refreshInputPermissions()
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.desktopChangeCount += 1 }
        })
        observers.append(center.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.displaySleeping = true
                self.capturePaused()
                self.availabilityMessage = "显示器已息屏；保留共享与许可，捕获暂停时等待新画面"
            }
        })
        for name in [NSWorkspace.screensDidWakeNotification, NSWorkspace.didWakeNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.displaySleeping = false; self.systemSleeping = false
                    self.retryInterruptedCapture()
                }
            })
        }
        for name in [NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.willSleepNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    if name == NSWorkspace.willSleepNotification { self.systemSleeping = true }
                    self.setControl(false)
                    self.stopMicrophone("Mac 会话失活，麦克风已停止")
                    self.availabilityMessage = "会话已离开或系统将睡眠；控制已撤销，恢复后需重新授权或重连"
                }
            })
        }
        restoreSessionSettings()
    }

    func resetPairingCredential() {
        guard !pairingCredentialLoading else { status = "正在读取配对密钥，请检查系统钥匙串提示"; return }
        guard !sharing, !connected else { status = "请先停止共享，再重置配对"; return }
        guard let secret = try? LANPairing.newSecret(),
              LANCredentialStore.write(Data(secret.utf8), account: "host-pairing-v2-signed") else {
            status = "无法安全保存新的配对密钥；旧配对仍保留"
            return
        }
        pairingSecret = secret
        pairingCredentialStored = true
        pairing = nil
        status = "已重置配对密钥；旧手机凭据已失效，下次共享后请重新扫码"
    }

    func refreshAddresses() {
        let found = RemoteInterfaceAddress.current().filter { $0.isUp && LANPairing.isLocalHost($0.address) && !$0.address.hasPrefix("127.") }.map { ($0.name, $0.address) }
        addresses = found.sorted { ($0.0.hasPrefix("en") ? 0 : 1, $0.0) < ($1.0.hasPrefix("en") ? 0 : 1, $1.0) }
            .map(\.1).reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
        if !addresses.contains(selectedAddress) { selectedAddress = addresses.first ?? "" }
        refreshTailscale()
    }

    /// A private loopback TLS endpoint is reached only through the embedded
    /// userspace node. Never bind the remote service to a public interface.
    func refreshTailscale() {
        lastTailscaleRefresh = Date()
        tailscaleAddresses = tailnet.addresses
        guard allowsTailscale, sharing, tailnet.ready else {
            if let server = tailnetListener {
                server.cancel(); tailnetListener = nil; tailnet.stopForwarding()
            }
            tailscalePairings.removeAll()
            if peerNetwork == .tailscale { releaseQueuedInput(); setControl(false); link?.close() }
            for (id, network) in candidateNetworks where network == .tailscale { candidates[id]?.close() }
            tailscaleMessage = !allowsTailscale ? "公网入口关闭；局域网仍可免登录使用。"
                : !tailnet.ready ? "请先在 Chordesk 登录并连接 Tailscale。"
                : "公网已连接；开启远控服务后生成配对二维码。"
            return
        }
        if tailnetListener != nil {
            if !tailscalePairings.isEmpty {
                tailscalePairings = tailnet.addresses.map {
                    LANPairing(host: $0, port: LANPairing.defaultPort, secret: pairingSecret, network: .tailscale)
                }
            }
            return
        }
        let token = generation
        do {
            let server = try LANTransport.listener(secret: pairingSecret, localAddress: "127.0.0.1", port: .any)
            tailnetListener = server
            server.newConnectionHandler = { [weak self, weak server] connection in
                Task { @MainActor in
                    guard let self, let server, self.generation == token, self.allowsTailscale,
                          self.tailnet.ready, self.tailnetListener === server else { connection.cancel(); return }
                    self.accept(connection, token: token, network: .tailscale)
                }
            }
            server.stateUpdateHandler = { [weak self, weak server] state in
                Task { @MainActor in
                    guard let self, let server, self.generation == token, self.tailnetListener === server else { return }
                    if case .ready = state, let port = server.port {
                        let started = await self.tailnet.forward(to: port.rawValue)
                        guard self.generation == token, self.tailnetListener === server, self.allowsTailscale, self.tailnet.ready else { return }
                        if started {
                            self.tailscalePairings = self.tailnet.addresses.map {
                                LANPairing(host: $0, port: LANPairing.defaultPort, secret: self.pairingSecret, network: .tailscale)
                            }
                            self.tailscaleMessage = "公网入口已就绪；手机在 Chordesk 登录同一 Tailscale 网络后扫码绑定。"
                        } else {
                            server.cancel(); self.tailnetListener = nil
                            self.tailscaleMessage = "公网入口未能开启：" + self.tailnet.message
                        }
                    } else if case .failed(let error) = state {
                        server.cancel(); self.tailnetListener = nil; self.tailnet.stopForwarding()
                        self.tailscalePairings.removeAll(); self.tailscaleMessage = error.localizedDescription
                    }
                }
            }
            server.start(queue: DispatchQueue(label: "dev.chordesk.tailnet-tls"))
        } catch { tailscaleMessage = "无法开启公网入口：" + error.localizedDescription }
    }

    func refreshDisplays(requestPermission: Bool = false) async {
        screenCaptureAllowed = CGPreflightScreenCaptureAccess()
        if requestPermission && !screenCaptureAllowed {
            screenCaptureAllowed = CGRequestScreenCaptureAccess()
        }
        let screens = NSScreen.screens
        displays = screens.compactMap { screen in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 else { return nil }
            let bounds = CGDisplayBounds(id)
            return LANDisplay(id: id, name: screen.localizedName, width: bounds.width, height: bounds.height)
        }
        if !displays.contains(where: { $0.id == selectedDisplay }) {
            selectedDisplay = DefaultHostDisplay.choose(displays.map(\.id), builtIn: { CGDisplayIsBuiltin($0) != 0 }, main: CGMainDisplayID()) ?? 0
        }
        displayListMessage = screenCaptureAllowed
            ? "按名称选择实体屏；可直接调整文字大小"
            : "应用内选择需要屏幕录制权限；点击授权后按系统提示允许，必要时重新打开主机"
        sendCatalog()
    }

    func selectDisplay(_ id: UInt32, fromPhone: Bool = false) async {
        guard !switchingDisplay, !scaleBusy else { return }
        if fromPhone && (!allowsDisplaySwitching || !connected) { sendCatalog(); return }
        await refreshDisplays()
        guard screenCaptureAllowed, displays.contains(where: { $0.id == id }) else {
            displayListMessage = "显示器不可用或未授予屏幕录制权限"; sendCatalog(); return
        }
        let sessionToken = generation
        let restoreControl = controlAllowed
        let controlToken = controlRevision
        let operation = UUID(); displaySwitchOperation = operation
        switchingDisplay = true
        controlAllowed = false; input.release(); inputQueueEpoch += 1; pendingInputs.removeAll()
        captureRevision = UUID().uuidString
        latestFrame = nil
        sendStatus(); sendCatalog()
        defer {
            if displaySwitchOperation == operation {
                displaySwitchOperation = nil; switchingDisplay = false; sendStatus(); sendCatalog()
                Task { await self.refreshScaleOptions() }
            }
        }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            guard generation == sessionToken else { return }
            guard !fromPhone || allowsDisplaySwitching else { return }
            guard let display = content.displays.first(where: { $0.displayID == id }) else {
                throw NSError(domain: "DuoDisplay", code: 1, userInfo: [NSLocalizedDescriptionKey: "所选显示器已断开"])
            }
            let filter = SCContentFilter(display: display, excludingWindows: [])
            if sharing {
                try await installCapture(filter, display: display, sessionToken: sessionToken)
                guard generation == sessionToken else { return }
                guard !fromPhone || allowsDisplaySwitching else { stop(); status = "切屏授权已撤销，共享已停止"; return }
                refreshInputPermissions()
                controlAllowed = restoreControl && controlRevision == controlToken && accessibilityAllowed && eventPostingAllowed && connected
                status = "已切换到 \(currentDisplayName)"
            } else {
                refreshAddresses()
                guard !selectedAddress.isEmpty || (allowsTailscale && !tailscaleAddresses.isEmpty) else { status = "请先连接局域网或登录 Tailscale"; return }
                await start(filter, display: display)
            }
        } catch {
            // An incomplete switch must never leave input targeting an unseen display.
            if generation == sessionToken { stop(); status = "切屏失败，已停止共享：\(error.localizedDescription)" }
        }
    }

    private func displayName(_ id: UInt32) -> String {
        NSScreen.screens.first(where: { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32) == id })?.localizedName ?? "显示器 \(id)"
    }

    private func sendCatalog() {
        guard peerSupportsDisplays else { return }
        var remoteScale = scaleState
        let matchesCurrentDisplay = remoteScale?.displayID == displayID
        remoteScale?.canAdjust = controlAllowed && allowsDisplaySwitching && !scaleBusy && !switchingDisplay && matchesCurrentDisplay
        if scaleBusy { remoteScale?.message = "正在调整显示器…" }
        link?.send(.displays, value: LANDisplayCatalog(displays: displays, selectedID: displayID,
            canSwitch: allowsDisplaySwitching && screenCaptureAllowed && !switchingDisplay && !scaleBusy,
            message: allowsDisplaySwitching ? displayListMessage : "请在 Mac 开启“允许手机切屏与缩放”", scale: remoteScale))
    }

    func refreshScaleOptions() async {
        guard !scaleBusy else { return }
        let id = displayID ?? selectedDisplay
        guard id != 0 else { scaleState = nil; return }
        let token = UUID(); scaleRefreshToken = token
        do {
            var state = try await displayScaling.state(displayID: id, backend: scalingBackend)
            guard scaleRefreshToken == token, (displayID ?? selectedDisplay) == id else { return }
            state.canAdjust = !switchingDisplay
            scaleState = state; scaleMessage = state.message
        } catch {
            guard scaleRefreshToken == token else { return }
            scaleState = nil; scaleMessage = error.localizedDescription
        }
        sendCatalog()
    }

    func adjustDisplayScale(_ choice: String, fromPhone: Bool = false) async {
        guard !scaleBusy, !switchingDisplay,
              ["fit", "larger", "largest", "space", "restore"].contains(choice) else { return }
        if fromPhone && (!controlAllowed || !allowsDisplaySwitching || !connected) { sendCatalog(); return }
        let id = displayID ?? selectedDisplay
        guard id != 0 else { return }
        let token = generation
        let controlToken = controlRevision
        let resumeControl = controlAllowed
        adjustingScale = true; input.release(); controlAllowed = false; inputQueueEpoch += 1; pendingInputs.removeAll()
        captureRevision = UUID().uuidString
        latestFrame = nil
        scaleMessage = "正在调整显示模式…"
        sendStatus(); sendCatalog()
        var succeeded = false
        do {
            try await displayScaling.apply(displayID: id, choice: choice, sessionScoped: connected, backend: scalingBackend)
            if generation == token, displayID == id, let stream {
                try await updateCaptureSize(stream, displayID: id)
            }
            scaleMessage = choice == "restore" ? "已恢复原显示模式" : connected ? "已调整文字大小，断开后恢复连接前分辨率" : "文字大小已调整，可随时恢复原设置"
            succeeded = true
        } catch {
            scaleMessage = error.localizedDescription
        }
        let resultMessage = scaleMessage
        adjustingScale = false
        let waiters = scaleIdleWaiters; scaleIdleWaiters.removeAll()
        waiters.forEach { $0.resume() }
        if generation == token && !restoringScale {
            refreshInputPermissions()
            controlAllowed = succeeded && resumeControl && controlRevision == controlToken && accessibilityAllowed && eventPostingAllowed && connected
            status = resultMessage
            sendStatus()
        }
        guard !restoringScale, generation == token else { return }
        await refreshDisplays()
        await refreshScaleOptions()
        scaleMessage = resultMessage
        scaleState?.message = resultMessage
        sendCatalog()
    }

    private func updateCaptureSize(_ stream: SCStream, displayID id: UInt32) async throws {
        let bounds = CGDisplayBounds(id)
        input.bounds = bounds
        let config = captureConfiguration(displayID: id)
        try await stream.updateConfiguration(config)
        captureRevision = UUID().uuidString
    }

    private func captureConfiguration(displayID id: UInt32) -> SCStreamConfiguration {
        let config = SCStreamConfiguration()
        let mode = CGDisplayCopyDisplayMode(id)
        let pixels = CGSize(width: mode?.pixelWidth ?? Int(CGDisplayBounds(id).width),
                            height: mode?.pixelHeight ?? Int(CGDisplayBounds(id).height))
        let size = videoQuality.captureSize(pixels: pixels)
        config.width = Int(size.width); config.height = Int(size.height)
        config.minimumFrameInterval = CMTime(value: 1, timescale: videoQuality.framesPerSecond)
        config.queueDepth = 3; config.showsCursor = true; config.capturesAudio = false
        return config
    }

    func setVideoQuality(_ quality: LANVideoQuality, fromPhone: Bool = false) async {
        guard !switchingDisplay, !scaleBusy else { return }
        if fromPhone && (!connected || !allowsDisplaySwitching) { return }
        let old = videoQuality
        videoQuality = quality
        guard let stream, let id = displayID else {
            UserDefaults.standard.set(quality.rawValue, forKey: "DuoVideoQuality"); return
        }
        let token = generation, controlToken = controlRevision, resume = controlAllowed
        switchingDisplay = true; controlAllowed = false; input.release()
        inputQueueEpoch += 1; pendingInputs.removeAll(); latestFrame = nil
        sendStatus(); sendCatalog()
        do {
            try await updateCaptureSize(stream, displayID: id)
            guard generation == token else { return }
            frames?.setQuality(quality.jpegQuality)
            UserDefaults.standard.set(quality.rawValue, forKey: "DuoVideoQuality")
            controlAllowed = resume && controlToken == controlRevision && connected
            status = "画质：" + quality.title
        } catch {
            videoQuality = old; controlAllowed = false
            status = "画质更新失败，请重新共享：" + error.localizedDescription
        }
        if generation == token { switchingDisplay = false; sendStatus(); sendCatalog() }
    }

    private func configurePairedPhone(_ peer: LANLink, generation token: UUID, expectedRevision: Int) async {
        guard expectedRevision == controlRevision else { return }
        let controlToken = expectedRevision
        if restoreFailed { restoreSessionSettings() }
        await scaleRestoreTask?.value
        if adjustingScale { await withCheckedContinuation { scaleIdleWaiters.append($0) } }
        guard generation == token, link === peer, connected, sharing, autoConfigurePairing,
              controlRevision == controlToken, !restoreFailed, !switchingDisplay else { return }
        refreshInputPermissions()
        guard accessibilityAllowed && eventPostingAllowed else {
            status = "已配对；系统控制权限未允许，请在 Mac 授权后开启控制"; sendStatus(); return
        }
        allowsDisplaySwitching = true
        if captureRecovery.paused {
            pendingAutomaticPeer = (peer, token, controlToken)
            status = "已配对，等待息屏后的新画面再启用控制"; sendStatus(); return
        }
        setControl(true)
        guard controlAllowed else { return }
        await refreshScaleOptions()
        guard generation == token, link === peer, connected, controlAllowed else { return }
        guard scaleState?.options.contains(where: { $0.id == "fit" }) == true else {
            status = "已允许控制，保持当前分辨率；当前无可用适配档位"
            sendStatus(); return
        }
        await adjustDisplayScale("fit")
    }

    /// Also used on window close and normal app quit. Resolution changes finish
    /// before restoration; a quick reconnect waits for the old baseline to return.
    func restoreSessionSettings() {
        guard scaleRestoreTask == nil else { return }
        restoringScale = true
        input.release(); inputQueueEpoch += 1; pendingInputs.removeAll()
        controlAllowed = false; latestFrame = nil; captureRevision = UUID().uuidString
        scaleMessage = "正在恢复连接前的分辨率…"
        sendStatus(); sendCatalog()
        scaleRestoreTask = Task { @MainActor in
            if self.adjustingScale { await withCheckedContinuation { self.scaleIdleWaiters.append($0) } }
            let errors = await self.displayScaling.restoreSessionModes()
            self.restoreFailed = !errors.isEmpty
            if let stream = self.stream, let id = self.displayID {
                do { try await self.updateCaptureSize(stream, displayID: id) }
                catch { self.stop(); self.status = "显示恢复后需要重新共享：\(error.localizedDescription)" }
            }
            self.restoringScale = false
            let message = errors.isEmpty ? "连接前分辨率已恢复" : "自动恢复未完成：" + errors.joined(separator: "；")
            await self.refreshDisplays(); await self.refreshScaleOptions()
            self.scaleMessage = message; self.scaleState?.message = message
            self.sendStatus(); self.sendCatalog()
            self.scaleRestoreTask = nil
        }
    }

    func stopAndRestore() async {
        stop()
        await scaleRestoreTask?.value
    }

    func chooseDisplay() {
        guard #available(macOS 15.2, *) else { status = "局域网主机需要 macOS 15.2 或更新版本"; return }
        stop()
        refreshAddresses()
        guard !selectedAddress.isEmpty else { status = "请先连接 Wi-Fi 或有线局域网"; return }
        NSApp.activate()
        let picker = SCContentSharingPicker.shared
        var config = SCContentSharingPickerConfiguration()
        config.allowedPickerModes = [.singleDisplay]
        config.allowsChangingSelectedContent = false
        picker.defaultConfiguration = config
        picker.add(self); pickerRegistered = true
        picker.isActive = true
        picker.present(using: .display)
        status = "在系统选择器中共享显示器，然后用手机扫码"
    }

    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        Task { @MainActor in self.status = "已取消显示器共享" }
    }
    nonisolated func contentSharingPickerStartDidFailWithError(_ error: Error) {
        Task { @MainActor in self.status = error.localizedDescription }
    }
    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
        Task { @MainActor in await self.start(filter) }
    }

    private func start(_ filter: SCContentFilter, display requestedDisplay: SCDisplay? = nil) async {
        guard !pairingCredentialLoading else { status = "配对密钥尚未就绪，请检查系统钥匙串提示后重试"; return }
        guard #available(macOS 15.2, *), let display = requestedDisplay ?? filter.includedDisplays.first else {
            status = "请选择整个显示器"; return
        }
        await scaleRestoreTask?.value
        guard !restoreFailed else { status = "请先完成连接前分辨率恢复，再开始共享"; return }
        let token = UUID(); generation = token
        do {
            guard LANPairing.isValidSecret(pairingSecret) else { throw LANWireError.random }
            let localBind = selectedAddress.isEmpty ? "127.0.0.1" : selectedAddress
            let newListener = try LANTransport.listener(secret: pairingSecret, localAddress: localBind)
            newListener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in
                    guard let self, self.generation == token else { connection.cancel(); return }
                    self.accept(connection, token: token)
                }
            }
            newListener.stateUpdateHandler = { [weak self, weak newListener] state in
                Task { @MainActor in
                    guard let self, self.generation == token else { return }
                    if case .ready = state, let port = newListener?.port {
                        if localBind != "127.0.0.1" { self.pairing = LANPairing(host: localBind, port: port.rawValue, secret: self.pairingSecret) }
                        self.status = "等待已配对 Duo 或首次扫码 · TLS 加密 · 一次只连接一台手机"
                    } else if case .failed(let error) = state { self.stop(); self.status = error.localizedDescription }
                }
            }
            listener = newListener
            try await installCapture(filter, display: display, sessionToken: token)
            guard generation == token else { return }
            sharing = true
            refreshTailscale()
            Task { await self.refreshScaleOptions() }
            newListener.start(queue: DispatchQueue(label: "dev.iphoneduo.listener"))
            let heartbeat = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.tick() }
            }
            timer = heartbeat
            RunLoop.main.add(heartbeat, forMode: .common)
        } catch {
            if generation == token { stop(); status = "共享失败：\(error.localizedDescription)" }
        }
    }

    private func installCapture(_ filter: SCContentFilter, display: SCDisplay, sessionToken: UUID, preserveRecovery: Bool = false) async throws {
        let token = UUID(); captureGeneration = token
        if !preserveRecovery { captureRecovery = CaptureRecovery() }
        let previous = stream; stream = nil; frames = nil
        if let previous { try await previous.stopCapture() }
        guard generation == sessionToken else { throw CancellationError() }
        displayID = display.displayID; selectedDisplay = display.displayID
        currentDisplayName = displayName(display.displayID)
        input.bounds = CGDisplayBounds(display.displayID)
        latestFrame = nil; frameCount = 0
        captureRevision = UUID().uuidString
        sendStatus()
        let config = captureConfiguration(displayID: display.displayID)
        let sink = LANFrameSource(quality: videoQuality.jpegQuality, frame: { [weak self] data in
            Task { @MainActor in
                guard let self, self.generation == sessionToken, self.captureGeneration == token, !self.scaleBusy else { return }
                self.captureResumed()
                self.latestFrame = data; self.frameCount += 1
                self.link?.send(.frame, data: data, droppable: true)
            }
        }, pause: { [weak self] in
            Task { @MainActor in
                guard let self, self.generation == sessionToken, self.captureGeneration == token else { return }
                guard !self.scaleBusy else { return }
                self.capturePaused()
            }
        }, stopped: { [weak self] error in
            Task { @MainActor in
                guard let self, self.generation == sessionToken, self.captureGeneration == token else { return }
                let value = error as NSError
                // A user/system stop is an intentional boundary. Only interrupted capture-service connections retry.
                let transient = CaptureRestartDecision.permits(isCaptureError: value.domain == SCStreamErrorDomain,
                    code: value.code, screenPermission: CGPreflightScreenCaptureAccess(),
                    displayOnline: self.displayID.map { CGDisplayIsOnline($0) != 0 } ?? false)
                guard transient else { self.stop(); self.status = value.localizedDescription; return }
                self.capturePaused(); self.captureInterrupted = true
                self.stream = nil; self.frames = nil
                self.availabilityMessage = "捕获服务中断；配对监听仍在线"
                self.retryInterruptedCapture()
            }
        })
        let capture = SCStream(filter: filter, configuration: config, delegate: sink)
        try capture.addStreamOutput(sink, type: .screen, sampleHandlerQueue: sink.queue)
        frames = sink; stream = capture
        try await capture.startCapture()
        guard generation == sessionToken, captureGeneration == token else {
            try? await capture.stopCapture(); throw CancellationError()
        }
    }

    private func accept(_ connection: NWConnection, token: UUID, network: RemoteNetwork = .lan) {
        guard link == nil, candidates.count < 3 else { connection.cancel(); return }
        let id = UUID()
        let candidate = LANLink(connection)
        candidates[id] = candidate
        candidateNetworks[id] = network
        candidate.onFrameSent = { [weak self, weak candidate] bytes in
            Task { @MainActor in
                guard let self, let candidate, self.generation == token, self.link === candidate else { return }
                self.traffic.record(bytes: bytes, now: ProcessInfo.processInfo.systemUptime)
            }
        }
        candidate.onReady = { [weak self, weak candidate] in
            Task { @MainActor in
                guard let self, let candidate, self.generation == token, self.link == nil else { candidate?.close(); return }
                guard network == .lan || (self.allowsTailscale && self.tailnet.ready && self.tailnetListener != nil) else { candidate.close(); return }
                self.link = candidate
                self.candidates.removeValue(forKey: id)
                self.candidateNetworks.removeValue(forKey: id)
                self.peerNetwork = network
                self.connected = true; self.lastPing = Date(); self.configuredPeer = nil
                self.traffic = VideoTrafficMeter(); self.videoMbps = 0; self.videoFPS = 0
                self.status = self.autoConfigurePairing ? "手机已安全配对 · 正在准备自动控制与显示设置" : "手机已安全配对 · 仅查看"
                self.sendStatus()
                if let frame = self.latestFrame { candidate.send(.frame, data: frame, droppable: true) }
            }
        }
        candidate.onPacket = { [weak self, weak candidate] kind, data in
            Task { @MainActor in
                guard let self, let candidate, self.generation == token, self.link === candidate else { return }
                self.lastPing = Date()
                switch kind {
                case .hello:
                    if let hello = try? JSONDecoder().decode(LANHello.self, from: data) {
                        self.clientName = String(hello.name.prefix(80)); self.peerSupportsDisplays = hello.displaySelection
                        self.peerSupportsMicrophone = hello.microphone == true
                    } else {
                        self.clientName = (String(data: data, encoding: .utf8) ?? "iPhone").prefix(80).description
                        self.peerSupportsDisplays = false; self.peerSupportsMicrophone = false
                    }
                    self.sendStatus(); self.sendCatalog()
                    if self.configuredPeer != id {
                        self.configuredPeer = id
                        _ = self.displayWake.request(authenticated: true, enabled: self.wakeDisplayOnConnect)
                        self.displaySleeping = false
                        self.retryInterruptedCapture()
                        if self.autoConfigurePairing && self.peerSupportsDisplays {
                            let revision = self.controlRevision
                            Task { await self.configurePairedPhone(candidate, generation: token, expectedRevision: revision) }
                        }
                    }
                    self.sendMicrophoneState()
                case .microphoneRequest:
                    guard data.count < 512, let request = try? JSONDecoder().decode(LANMicrophoneRequest.self, from: data) else { return }
                    self.requestMicrophone(request)
                case .microphoneAudio:
                    guard self.microphoneActive, self.microphoneAvailable,
                          let packet = MicrophonePacket(data), self.microphoneGate.accept(packet) else { return }
                    self.lastMicrophonePacket = Date(); self.microphonePlayer.play(packet)
                case .input:
                    guard data.count < 2048, let event = try? JSONDecoder().decode(LANInput.self, from: data),
                          event.x.isFinite, event.y.isFinite else { return }
                    guard !self.switchingDisplay, !self.scaleBusy else { return }
                    if self.peerSupportsDisplays {
                        guard event.displayID == self.displayID, event.captureRevision == self.captureRevision else { return }
                    }
                    self.enqueue(.pointer(event))
                case .requestDisplays:
                    guard self.peerSupportsDisplays else { return }
                    Task { await self.refreshDisplays(); await self.refreshScaleOptions() }
                case .selectDisplay:
                    guard data.count < 128, self.peerSupportsDisplays,
                          let id = try? JSONDecoder().decode(UInt32.self, from: data) else { return }
                    Task { await self.selectDisplay(id, fromPhone: true) }
                case .adjustScale:
                    guard data.count < 256, self.peerSupportsDisplays,
                          let request = try? JSONDecoder().decode(LANScaleRequest.self, from: data),
                          request.displayID == self.displayID else { return }
                    Task { await self.adjustDisplayScale(request.choice, fromPhone: true) }
                case .videoQuality:
                    guard data.count < 128, let raw = try? JSONDecoder().decode(String.self, from: data),
                          let quality = LANVideoQuality(rawValue: raw) else { return }
                    Task { await self.setVideoQuality(quality, fromPhone: true) }
                case .textInput:
                    guard data.count < 16384, self.peerSupportsDisplays, self.controlAllowed,
                          let edit = try? JSONDecoder().decode(LANTextEdit.self, from: data), edit.isValid,
                          edit.displayID == self.displayID, edit.captureRevision == self.captureRevision else { return }
                    self.enqueue(.text(edit))
                case .release:
                    self.inputQueueEpoch += 1; self.pendingInputs.removeAll()
                    self.input.release(); self.sendStatus()
                case .ping: candidate.send(.ping)
                default: break
                }
            }
        }
        candidate.onClose = { [weak self, weak candidate] reason in
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                self.candidates.removeValue(forKey: id)
                self.candidateNetworks.removeValue(forKey: id)
                if let candidate, self.link === candidate {
                    self.inputQueueEpoch += 1; self.pendingInputs.removeAll(); self.textFocus = nil; self.focusRequest = 0; self.latestFocusClick = 0
                    self.stopMicrophone("手机已断开，麦克风已停止"); self.peerSupportsMicrophone = false
                    self.input.release(); self.link = nil
                    self.peerNetwork = .lan
                    self.controlRevision += 1
                    self.controlAllowed = false; self.connected = false; self.peerSupportsDisplays = false
                    self.allowsDisplaySwitching = false; self.configuredPeer = nil
                    self.status = "手机已断开：\(reason)"; self.clientName = ""
                    self.restoreSessionSettings()
                }
            }
        }
        candidate.start()
    }

    func setControl(_ enabled: Bool) {
        controlRevision += 1
        captureRecovery.invalidate(); pendingAutomaticPeer = nil
        if !enabled { inputQueueEpoch += 1; pendingInputs.removeAll(); textFocus = nil }
        if enabled {
            guard !captureRecovery.paused else { status = "等待新画面后再开启控制"; sendStatus(); return }
            guard !switchingDisplay, !scaleBusy else { return }
            guard connected, sharing else { status = "请先让手机连接当前共享会话"; sendStatus(); return }
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            accessibilityAllowed = AXIsProcessTrustedWithOptions(options)
            eventPostingAllowed = CGPreflightPostEventAccess()
            if accessibilityAllowed && !eventPostingAllowed {
                eventPostingAllowed = CGRequestPostEventAccess()
            }
            guard accessibilityAllowed && eventPostingAllowed else {
                controlAllowed = false; status = "请在系统隐私设置中允许 Chordesk · Mac 主机 控制 Mac，再开启远程控制"; sendStatus(); return
            }
        }
        input.release()
        controlAllowed = enabled
        status = enabled ? "允许这台手机控制当前共享屏幕" : "仅查看 · Mac 控制已关闭"
        sendStatus(); sendCatalog()
    }

    private func tick() {
        if allowsTailscale && Date().timeIntervalSince(lastTailscaleRefresh) >= 5 { refreshTailscale() }
        if microphoneActive {
            if Date().timeIntervalSince(lastMicrophonePacket) > 2 { stopMicrophone("麦克风数据中断，请在 Duo 重新开启") }
            else if !microphonePlayer.routeIsValid { stopMicrophone("音频输出设备已改变，麦克风已停止") }
        }
        if let sample = traffic.sample(now: ProcessInfo.processInfo.systemUptime) {
            videoMbps = sample.mbps; videoFPS = sample.fps
        }
        refreshInputPermissions()
        if connected && Date().timeIntervalSince(lastPing) > 4 { input.release(); link?.close() }
        if let displayID, !scaleBusy {
            guard CGDisplayIsOnline(displayID) != 0 else { stop(); status = "共享显示器已断开"; return }
            input.bounds = CGDisplayBounds(displayID)
        }
        sendStatus()
        if connected && controlAllowed { Task { await self.refreshTextFocus() } }
    }

    private func refreshTextFocus() async {
        guard connected, controlAllowed, !focusProbeRunning, !switchingDisplay, !scaleBusy else { return }
        focusProbeRunning = true
        let token = generation, revision = captureRevision, request = focusRequest, controlToken = controlRevision
        let result = await focusMonitor.refresh(in: input.bounds, requestID: request)
        focusProbeRunning = false
        guard generation == token, captureRevision == revision, controlRevision == controlToken, controlAllowed, request == focusRequest else { return }
        textFocus = result; sendStatus()
    }

    private func enqueue(_ event: PendingInput) {
        guard pendingInputs.count < 256 else {
            inputQueueEpoch += 1; pendingInputs.removeAll(); input.release()
            setControl(false); status = "输入队列繁忙，请重新开启控制"; return
        }
        pendingInputs.append(event)
        if !drainingInputs { drainingInputs = true; Task { await drainInputs() } }
    }

    private func handlePointer(_ event: LANInput) async {
        inputCount += 1
        let description = "\(event.origin.prefix(12)) · " + (event.action == "key" ? "键盘 \(event.key)" : event.action)
        guard controlAllowed else { lastInput = description + " · 控制已关闭"; sendStatus(); return }
        let token = generation, controlToken = controlRevision, queueToken = inputQueueEpoch
        let result: LANInputResult
        if let action = event.windowOverview, action.isDesktopSwitch {
            input.release()
            let revision = captureRevision
            let desktop = await DesktopSwitcher.perform(action) {
                self.generation == token && self.controlRevision == controlToken && self.inputQueueEpoch == queueToken
                    && self.captureRevision == revision && self.controlAllowed && self.connected && self.sharing
                    && !self.switchingDisplay && !self.scaleBusy && !self.systemSleeping
                    && AXIsProcessTrusted() && CGPreflightPostEventAccess()
            }
            guard token == generation, controlToken == controlRevision, queueToken == inputQueueEpoch else { return }
            desktopMessage = desktop.message
            refreshDesktopPermission()
            result = desktop == .submitted ? .posted : .desktopSwitchFailed
            if desktop != .submitted { status = desktop.message; sendStatus() }
        } else if let action = event.windowOverview { result = await input.windowOverview(action) }
        else { result = input.handle(event) }
        guard token == generation, controlToken == controlRevision, queueToken == inputQueueEpoch,
              controlAllowed, connected else { return }
        lastInput = description + " · " + result.description
        if result == .posted {
            postedInputCount += 1
            link?.send(.acknowledgement, value: event.sequence)
            if event.action == "click" || event.action == "touch.tap" {
                latestFocusClick = event.sequence
                let peer = link, token = generation
                Task {
                    try? await Task.sleep(nanoseconds: 180_000_000)
                    guard self.generation == token, self.link === peer, self.connected,
                          self.latestFocusClick == event.sequence else { return }
                    self.focusRequest = event.sequence
                    await self.refreshTextFocus()
                }
            }
            if ["down", "up", "touch.down", "touch.move", "touch.up"].contains(event.action) { sendStatus() }
        } else if result == .permissionDenied {
            setControl(false)
            status = "系统阻止发送输入；请检查当前主机的控制权限，授权后重新开启控制"
            sendStatus()
        }
    }

    /// Keep committed text, Return/Tab, and pointer clicks in wire order. AX queries
    /// can suspend; release/disconnect invalidate a pending query before it can post.
    private func drainInputs() async {
        defer { drainingInputs = false }
        while !pendingInputs.isEmpty {
            let event = pendingInputs.removeFirst()
            guard connected, controlAllowed, !switchingDisplay, !scaleBusy else { continue }
            switch event {
            case .pointer(let pointer):
                if peerSupportsDisplays {
                    guard pointer.displayID == displayID, pointer.captureRevision == captureRevision else { continue }
                }
                await handlePointer(pointer)
            case .text(let edit):
                let token = generation, controlToken = controlRevision, queueToken = inputQueueEpoch
                let focus = await focusMonitor.refresh(in: input.bounds, requestID: focusRequest)
                guard generation == token, controlRevision == controlToken, inputQueueEpoch == queueToken,
                      connected, controlAllowed, !switchingDisplay, !scaleBusy,
                      edit.displayID == displayID, edit.captureRevision == captureRevision else { continue }
                textFocus = focus
                guard edit.focusID == nil || (focus.editable && edit.focusID == focus.id) else {
                    status = "输入目标已变化，请重新点选输入框"; sendStatus(); continue
                }
                inputCount += 1
                let result = input.typeText(edit)
                lastInput = "iPhone 输入法 · \(edit.text.count) 字符 · " + result.description
                if result == .posted {
                    postedInputCount += 1; link?.send(.acknowledgement, value: edit.sequence)
                } else { setControl(false); status = "文字输入未完成，请检查 Mac 权限与当前应用" }
                sendStatus()
            }
        }
    }

    func refreshInputPermissions() {
        accessibilityAllowed = AXIsProcessTrusted()
        eventPostingAllowed = CGPreflightPostEventAccess()
        if controlAllowed && (!accessibilityAllowed || !eventPostingAllowed) {
            setControl(false)
            status = "系统控制权限未生效；重新授权当前主机后，再开启控制"
            sendStatus()
        }
    }

    private func sendStatus() {
        link?.send(.status, value: LANStatus(name: Host.current().localizedName ?? "Mac", width: input.bounds.width,
            height: input.bounds.height, canControl: controlAllowed && !switchingDisplay && !scaleBusy, message: status,
            selectedDisplayID: displayID, displayName: currentDisplayName, supportsDisplaySelection: true,
            switchingDisplay: switchingDisplay || scaleBusy, captureRevision: captureRevision, supportsDirectTouch: true,
            supportsTextInput: true, textFocus: controlAllowed ? textFocus : nil, mouseButtonDown: input.isDragging,
            videoQuality: videoQuality.rawValue, supportsWindowOverview: true, supportsDesktopSwitch: true,
            supportedVideoQualities: LANVideoQuality.allCases.map(\.rawValue),
            supportsMicrophone: true, sourceRefreshRate: displayID.flatMap { CGDisplayCopyDisplayMode($0)?.refreshRate }, hostID: hostIdentity,
            supportsScrollDynamics: true))
    }

    func stop() {
        captureRepair?.cancel(); captureRepair = nil; captureInterrupted = false; pendingAutomaticPeer = nil
        stopMicrophone("共享已停止，麦克风已停止"); peerSupportsMicrophone = false
        inputQueueEpoch += 1; pendingInputs.removeAll(); textFocus = nil; focusRequest = 0; latestFocusClick = 0
        generation = UUID(); captureGeneration = UUID()
        controlRevision += 1; displaySwitchOperation = nil
        captureRecovery = CaptureRecovery()
        peerSupportsDisplays = false; allowsDisplaySwitching = false; switchingDisplay = false
        input.release(); controlAllowed = false
        timer?.invalidate(); timer = nil
        link?.close(); link = nil
        candidates.values.forEach { $0.close() }; candidates.removeAll()
        candidateNetworks.removeAll(); peerNetwork = .lan
        tailnetListener?.cancel(); tailnetListener = nil; tailnet.stopForwarding(); tailscalePairings.removeAll()
        listener?.cancel(); listener = nil
        let old = stream; stream = nil; frames = nil
        if let old { Task { try? await old.stopCapture() } }
        if pickerRegistered {
            SCContentSharingPicker.shared.remove(self)
            SCContentSharingPicker.shared.isActive = false
            pickerRegistered = false
        }
        sharing = false; connected = false; pairing = nil; displayID = nil; latestFrame = nil
        clientName = ""; currentDisplayName = ""; status = "共享已停止；已配对的 Duo 可在重新共享后重连"
        configuredPeer = nil
        restoreSessionSettings()
    }
}

private final class LANFrameSource: NSObject, SCStreamOutput, SCStreamDelegate {
    let queue = DispatchQueue(label: "dev.iphoneduo.jpeg", qos: .userInitiated)
    private let context = CIContext(options: [.cacheIntermediates: false])
    private var quality: Double
    func setQuality(_ value: Double) { queue.async { self.quality = value } }
    private let frame: (Data) -> Void
    private let pause: () -> Void
    private let stopped: (Error) -> Void
    init(quality: Double, frame: @escaping (Data) -> Void, pause: @escaping () -> Void, stopped: @escaping (Error) -> Void) {
        self.quality = quality; self.frame = frame; self.pause = pause; self.stopped = stopped
    }
    func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, buffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int, let status = SCFrameStatus(rawValue: raw) else { return }
        if [.blank, .suspended, .stopped].contains(status) { pause(); return }
        guard status == .complete, let pixels = buffer.imageBuffer else { return }
        autoreleasepool {
            let source = CIImage(cvPixelBuffer: pixels)
            if let image = context.createCGImage(source, from: source.extent),
               let jpeg = NSBitmapImageRep(cgImage: image).representation(using: .jpeg, properties: [.compressionFactor: quality]), jpeg.count <= LANLink.maximumPacketSize { frame(jpeg) }
        }
    }
    func stream(_ stream: SCStream, didStopWithError error: Error) { stopped(error) }
}

/// Real remote desktop input is explicitly enabled on the Mac for the paired peer.
/// No input listener is installed; events are released on timeout or disconnect.
private enum LANInputResult {
    case posted, permissionDenied, invalidDisplay, unsupported, creationFailed, overviewLaunchFailed, desktopSwitchFailed

    var description: String {
        switch self {
        case .posted: "已投递（执行效果需观察目标应用）"
        case .permissionDenied: "系统拒绝输入权限"
        case .invalidDisplay: "共享显示器不可用"
        case .unsupported: "不支持的操作"
        case .creationFailed: "无法创建输入事件"
        case .overviewLaunchFailed: "系统未能启动 Mission Control"
        case .desktopSwitchFailed: "桌面切换未执行／未确认，请看桌面切换设置"
        }
    }
}

@MainActor
private final class LANMacInput {
    private let events = RemoteEventFactory()
    var scrollPermission: () -> Bool = { false }
    private lazy var scrolling = HostScrollDriver(allowed: { [weak self] in self?.scrollPermission() == true }, emit: { [weak self] output in
        guard let self, let event = self.events.scroll(dy: output.y, dx: output.x, phase: output.phase, momentum: output.momentum) else { return false }
        event.location = output.location; event.post(tap: .cghidEventTap)
        return true
    })
    var bounds = CGRect.zero
    private var dragging = false
    var isDragging: Bool { dragging }
    private var lastClick = Date.distantPast
    private var lastClickPosition = CGPoint.zero
    private var clickCount: Int64 = 1

    func release() { scrolling.cancel(); if dragging { mouse(.leftMouseUp) }; dragging = false }

    func windowOverview(_ action: WindowOverviewAction) async -> LANInputResult {
        guard AXIsProcessTrusted(), CGPreflightPostEventAccess() else { release(); return .permissionDenied }
        guard bounds.width > 0, bounds.height > 0 else { return .invalidDisplay }
        release()
        if action == .hide { return key("esc", modifiers: 0) }
        // Spaces use the separately gated System Events path in LANHost.
        guard !action.isDesktopSwitch else { return .unsupported }
        // Launch Apple's installed application through public NSWorkspace. System
        // global shortcuts may ignore posted keyboard events even when ordinary
        // application keys work. Never accept an application path from the phone.
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.exposelauncher") else { return .overviewLaunchFailed }
        do {
            _ = try await NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            return .posted
        } catch { return .overviewLaunchFailed }
    }

    func typeText(_ edit: LANTextEdit) -> LANInputResult {
        scrolling.cancel()
        guard AXIsProcessTrusted(), CGPreflightPostEventAccess() else { release(); return .permissionDenied }
        guard edit.isValid, bounds.width > 0, bounds.height > 0, !dragging else { return .unsupported }
        for _ in 0..<edit.deleteCount { if key("delete", modifiers: 0) != .posted { return .creationFailed } }
        for character in edit.text {
            if character == "\n" || character == "\r\n" { if key("return", modifiers: 0) != .posted { return .creationFailed }; continue }
            if character == "\t" { if key("tab", modifiers: 0) != .posted { return .creationFailed }; continue }
            let units = Array(String(character).utf16)
            guard let pair = events.keyboard(code: 0, modifiers: 0), pair.count == 2 else { return .creationFailed }
            let down = pair[0], up = pair[1]
            units.withUnsafeBufferPointer { buffer in
                down.keyboardSetUnicodeString(stringLength: units.count, unicodeString: buffer.baseAddress!)
                up.keyboardSetUnicodeString(stringLength: units.count, unicodeString: buffer.baseAddress!)
            }
            down.flags = []; up.flags = []
            down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
        }
        return .posted
    }

    func handle(_ event: LANInput) -> LANInputResult {
        guard AXIsProcessTrusted(), CGPreflightPostEventAccess() else { release(); return .permissionDenied }
        guard bounds.width > 0, bounds.height > 0 else { release(); return .invalidDisplay }
        if event.action == "scroll.gesture" {
            guard !dragging, let sample = event.scrollGesture else { scrolling.cancel(); return .unsupported }
            return scrolling.receive(sample, bounds: bounds, pointer: clampedPointer()) ? .posted : .unsupported
        }
        scrolling.cancel()
        if event.action.hasPrefix("touch.") {
            guard let direct = event.directTouch else { return .unsupported }
            return handleDirect(direct)
        }
        switch event.action {
        case "move":
            let old = CGEvent(source: nil)?.location ?? CGPoint(x: bounds.midX, y: bounds.midY)
            let point = CGPoint(x: min(max(old.x + min(max(event.x, -1), 1) * bounds.width * 1.5, bounds.minX), bounds.maxX - 1),
                y: min(max(old.y + min(max(event.y, -1), 1) * bounds.height * 1.5, bounds.minY), bounds.maxY - 1))
            guard let movement = events.mouse(dragging ? .leftMouseDragged : .mouseMoved, at: point) else { return .creationFailed }
            movement.post(tap: .cghidEventTap)
        case "click":
            let point = CGEvent(source: nil)?.location ?? .zero
            clickCount = Date().timeIntervalSince(lastClick) < NSEvent.doubleClickInterval && hypot(point.x - lastClickPosition.x, point.y - lastClickPosition.y) < 5 ? min(clickCount + 1, 3) : 1
            lastClick = Date(); lastClickPosition = point
            let down = mouse(.leftMouseDown, count: clickCount)
            let up = mouse(.leftMouseUp, count: clickCount)
            guard down && up else { return .creationFailed }
        case "rightClick":
            let down = mouse(.rightMouseDown)
            let up = mouse(.rightMouseUp)
            guard down && up else { return .creationFailed }
        case "down":
            guard mouse(.leftMouseDown) else { return .creationFailed }
            dragging = true
        case "up": release()
        case "scroll":
            let dy = Int32(min(max(event.y * 1200, -1500), 1500))
            guard let scroll = events.scroll(dy: dy) else { return .creationFailed }
            scroll.location = clampedPointer()
            scroll.post(tap: .cghidEventTap)
        case "key": return key(event.key, modifiers: event.modifiers)
        default: return .unsupported
        }
        return .posted
    }

    private func handleDirect(_ event: DirectTouchEvent) -> LANInputResult {
        let point = event.displayPoint(in: bounds)
        switch event.action {
        case .tap, .context:
            guard !dragging else { return .unsupported }
            let right = event.action == .context
            guard mouse(right ? .rightMouseDown : .leftMouseDown, count: Int64(event.clicks), at: point) else { return .creationFailed }
            guard mouse(right ? .rightMouseUp : .leftMouseUp, count: Int64(event.clicks), at: point) else { return .creationFailed }
        case .scroll:
            guard !dragging else { return .unsupported }
            let dx = Int32(min(max(event.delta.x * bounds.width, -1500), 1500))
            let dy = Int32(min(max(event.delta.y * bounds.height, -1500), 1500))
            guard let scroll = events.scroll(dy: dy, dx: dx) else { return .creationFailed }
            scroll.location = point; scroll.post(tap: .cghidEventTap)
        case .down:
            guard !dragging else { return .unsupported }
            guard mouse(.leftMouseDown, at: point) else { return .creationFailed }
            dragging = true
        case .move:
            guard dragging else { return .unsupported }
            guard mouse(.leftMouseDragged, at: point) else { return .creationFailed }
        case .up: release()
        }
        return .posted
    }

    @discardableResult
    private func mouse(_ type: CGEventType, count: Int64 = 1, at point: CGPoint? = nil) -> Bool {
        guard let event = events.mouse(type, at: point ?? clampedPointer()) else { return false }
        event.setIntegerValueField(.mouseEventClickState, value: count)
        event.post(tap: .cghidEventTap)
        return true
    }

    private func clampedPointer() -> CGPoint {
        let point = CGEvent(source: nil)?.location ?? CGPoint(x: bounds.midX, y: bounds.midY)
        return CGPoint(x: min(max(point.x, bounds.minX), bounds.maxX - 1), y: min(max(point.y, bounds.minY), bounds.maxY - 1))
    }

    private func key(_ key: String, modifiers: UInt) -> LANInputResult {
        let codes: [String: CGKeyCode] = ["a":0,"s":1,"d":2,"f":3,"h":4,"g":5,"z":6,"x":7,"c":8,"v":9,"b":11,"q":12,"w":13,"e":14,"r":15,"y":16,"t":17,
            "1":18,"2":19,"3":20,"4":21,"6":22,"5":23,"9":25,"7":26,"-":27,"8":28,"0":29,"o":31,"u":32,"i":34,"p":35,
            "=":24,"[":33,"]":30,"return":36,"l":37,"j":38,"'":39,"k":40,";":41,"\\":42,",":43,"/":44,"n":45,"m":46,".":47,"tab":48,"space":49,"`":50,"delete":51,"esc":53,
            "left":123,"right":124,"down":125,"up":126,"f1":122,"f2":120,"f3":99,"f4":118,"f5":96,"f6":97,"f7":98,"f8":100,"f9":101,"f10":109,"f11":103,"f12":111]
        guard let code = codes[key] else { return .unsupported }
        guard let sequence = events.keyboard(code: code, modifiers: modifiers) else { return .creationFailed }
        // Build the complete balanced batch before posting: no partial modifier-down
        // if event creation fails, and no interleaved pointer event while it is held.
        for event in sequence { event.post(tap: .cghidEventTap) }
        return .posted
    }
}

/// Remote gestures carry their own modifier state. Never inherit Control from the
/// combined desktop state: Control + left click is interpreted as a context click.
/// Kept separate from posting so regressions can inspect real CGEvents without
/// injecting test input into the user's desktop.
final class RemoteEventFactory {
    private let source = CGEventSource(stateID: .privateState)
    func mouse(_ type: CGEventType, at point: CGPoint) -> CGEvent? {
        guard let source, let event = CGEvent(mouseEventSource: source, mouseType: type,
            mouseCursorPosition: point, mouseButton: [.rightMouseDown, .rightMouseUp].contains(type) ? .right : .left) else { return nil }
        event.flags = []
        return event
    }
    func scroll(dy: Int32, dx: Int32 = 0, phase: ScrollWheelPhase = .none, momentum: ScrollMomentumPhase = .none) -> CGEvent? {
        guard let source, let event = CGEvent(scrollWheelEvent2Source: source, units: .pixel,
            wheelCount: 2, wheel1: dy, wheel2: dx, wheel3: 0) else { return nil }
        event.flags = []
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase.rawValue)
        event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentum.rawValue)
        return event
    }
    func keyboard(code: CGKeyCode, modifiers: UInt) -> [CGEvent]? {
        guard let source, modifiers & ~15 == 0 else { return nil }
        let definitions: [(UInt, CGKeyCode, CGEventFlags)] = [
            (8, 59, .maskControl), (4, 58, .maskAlternate), (1, 56, .maskShift), (2, 55, .maskCommand)
        ]
        let selected = definitions.filter { modifiers & $0.0 != 0 }
        var result: [CGEvent] = [], flags: CGEventFlags = []
        func append(_ code: CGKeyCode, down: Bool, modifier: Bool = false) -> Bool {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down) else { return false }
            if modifier { event.type = .flagsChanged }
            event.flags = flags; result.append(event); return true
        }
        for (_, key, flag) in selected {
            flags.insert(flag)
            guard append(key, down: true, modifier: true) else { return nil }
        }
        guard append(code, down: true), append(code, down: false) else { return nil }
        for (_, key, flag) in selected.reversed() {
            flags.remove(flag)
            guard append(key, down: false, modifier: true) else { return nil }
        }
        return result
    }
}
#endif

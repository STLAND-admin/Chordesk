#if os(iOS)
import SwiftUI
import UIKit
import Network
import ImageIO

@MainActor
final class LANClient: ObservableObject {
    @Published var connectionPreference = ConnectionPreference(rawValue: UserDefaults.standard.string(forKey: "connectionPreferenceV1") ?? "") ?? .automatic {
        didSet { UserDefaults.standard.set(connectionPreference.rawValue, forKey: "connectionPreferenceV1") }
    }
    private var routeGeneration = UUID()
    private var routeProbes: [RemoteNetwork: LANPresenceProbe] = [:]
    private var routeRace = AutomaticRouteRace([])
    private var autoTargetID: UUID?
    private var autoRetryCount = 0
    private var autoRetryTask: Task<Void, Never>?
    private var connectedAt = Date()

    private func cancelRouteAttempts() {
        routeGeneration = UUID(); autoRetryTask?.cancel(); autoRetryTask = nil
        let probes = Array(routeProbes.values); routeProbes.removeAll(); probes.forEach { $0.cancel() }
        autoTargetID = nil; autoRetryCount = 0
    }
    func connectInvitation(_ invitation: LANPairing) {
        let primary = LANPairing(host: invitation.host, port: invitation.port, secret: invitation.secret, network: invitation.connectionNetwork)
        guard let identity = invitation.invitationHostID, UUID(uuidString: identity) != nil,
              let endpoints = invitation.invitationEndpoints, endpoints.count <= 8 else { connect(primary); return }
        let routes = endpoints.compactMap { $0.pairing(secret: primary.secret) }
        // QR gives out-of-band identity/PSK; only LANStatus after TLS saves a host.
        let saved = RememberedMac(pairing: primary, hostName: "Mac", hostID: identity,
            alternativePairings: routes.filter { $0.connectionNetwork != primary.connectionNetwork }, supportsPresenceProbe: true)
        connectSaved(saved, preference: connectionPreference)
    }
    func connectSaved(_ saved: RememberedMac, preference: ConnectionPreference, retry: Int = 0) {
        connectionPreference = preference
        if connected, currentPairing == saved.pairing(for: connectionNetwork),
           preference.network == nil || preference.network == connectionNetwork { return }
        if let network = preference.network {
            if let pairing = saved.pairing(for: network) { connect(pairing) }
            return
        }
        disconnect()
        let routes = RemoteNetwork.allCases.compactMap { saved.pairing(for: $0) }.filter {
            $0.isValid && ($0.connectionNetwork == .lan || EmbeddedTailnet.shared.ready || EmbeddedTailnet.shared.shouldResume)
        }
        guard !routes.isEmpty else { status = "尚无可用地址；请先在 Chordesk 登录已配对的 Tailscale 网络"; return }
        guard saved.supportsPresenceProbe == true, let identity = saved.hostID, UUID(uuidString: identity) != nil else {
            // Old hosts claim a session on TLS ready. Never race them.
            connect(routes.first!, automaticHostID: saved.id, retry: retry); return
        }
        connecting = true; autoTargetID = saved.id; autoRetryCount = retry
        status = "正在自动检查局域网与 Tailscale…"
        let token = routeGeneration
        routeRace = AutomaticRouteRace(routes.map(\.connectionNetwork))
        for pairing in routes {
            let probe = LANPresenceProbe(hostID: identity) { [weak self] reply in
                guard let self, self.routeGeneration == token else { return }
                if self.routeRace.complete(pairing.connectionNetwork, reachable: reply != nil && reply?.busy != true) {
                    self.connect(pairing, automaticHostID: saved.id, retry: retry)
                } else if self.routeRace.exhausted {
                    self.connectionLost("自动连接未成功：检查 Mac 服务、是否被其他设备占用及 Tailscale 状态；已保留配对")
                }
            }
            routeProbes[pairing.connectionNetwork] = probe; probe.start()
            Task { await self.attachProbe(probe, pairing: pairing) }
        }
    }
    private func attachProbe(_ probe: LANPresenceProbe, pairing: LANPairing) async {
        if pairing.connectionNetwork == .tailscale {
            if !EmbeddedTailnet.shared.ready, EmbeddedTailnet.shared.shouldResume {
                EmbeddedTailnet.shared.resumeIfNeeded()
                for _ in 0..<20 {
                    guard !probe.finished else { return }
                    if EmbeddedTailnet.shared.ready { break }
                    try? await Task.sleep(for: .milliseconds(200))
                }
            }
            do {
                guard !probe.finished else { return }
                let route = try await EmbeddedTailnet.shared.dial(pairing)
                probe.cleanup = { EmbeddedTailnet.shared.closeDial(route.identifier) }
                guard !probe.finished else { return }
                probe.attach(NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: route.port)!, using: LANTransport.parameters(secret: pairing.secret)))
            } catch { probe.fail() }
        } else {
            probe.attach(NWConnection(host: NWEndpoint.Host(pairing.host), port: NWEndpoint.Port(rawValue: pairing.port)!, using: LANTransport.parameters(secret: pairing.secret)))
        }
    }
    private func connectionLost(_ reason: String) {
        let saved = rememberedMacs.first { $0.id == autoTargetID }
        let retry = (Date().timeIntervalSince(connectedAt) > 30 ? 0 : autoRetryCount) + 1
        let mayRetry = connectionPreference == .automatic && UIApplication.shared.applicationState == .active
        disconnect()
        guard mayRetry, retry <= 3, let saved else { status = reason; return }
        status = "连接中断，已释放操作；正在自动重新选择网络（\(retry)/3）…"
        connecting = true
        let token = routeGeneration
        autoRetryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, let self, self.routeGeneration == token,
                  UIApplication.shared.applicationState == .active else { return }
            self.connectSaved(saved, preference: .automatic, retry: retry)
        }
    }

    struct PresenceObservation {
        var network: RemoteNetwork
        var message: String
        var checkedAt: Date?
    }
    @Published private(set) var presence: [UUID: PresenceObservation] = [:]
    @Published private(set) var checkingPresence = false
    private var presenceGeneration = UUID()
    private var presenceTask: Task<Void, Never>?
    private var presenceProbes: [UUID: LANPresenceProbe] = [:]

    func presenceMessage(_ saved: RememberedMac, network requestedNetwork: RemoteNetwork?) -> String {
        let network = requestedNetwork ?? (connected && saved.pairing.secret == currentPairing?.secret ? connectionNetwork : presence[saved.id]?.network ?? saved.pairing.connectionNetwork)
        if connected, currentPairing == saved.pairing(for: network), Date().timeIntervalSince(lastPacket) < 6 {
            return "在线 · 当前已连接"
        }
        if saved.pairing(for: network) == nil { return "此模式尚未配对" }
        if network == .tailscale && !EmbeddedTailnet.shared.ready { return "请先连接此 iPhone 的 Tailscale" }
        if let value = presence[saved.id], value.network == network { return value.message }
        return saved.supportsPresenceProbe == true ? "尚未检查" : "状态未知 · 连接新版 Mac 一次后可检查"
    }
    func cancelPresenceChecks() {
        presenceGeneration = UUID(); presenceTask?.cancel(); presenceTask = nil; checkingPresence = false
        let probes = Array(presenceProbes.values); presenceProbes.removeAll()
        probes.forEach { $0.cancel() }
        for (id, value) in presence where value.checkedAt == nil { presence.removeValue(forKey: id) }
    }
    func refreshPresence(network: RemoteNetwork?) {
        cancelPresenceChecks()
#if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.environment["DUO_UI_FIXTURE"] == "1" {
            for saved in rememberedMacs { presence[saved.id] = .init(network: network ?? .lan, message: "在线 · 服务可连接（模拟）", checkedAt: Date()) }
            return
        }
#endif
        guard UIApplication.shared.applicationState == .active,
              network != .tailscale || EmbeddedTailnet.shared.ready else { return }
        let token = presenceGeneration, hosts = rememberedMacs
        checkingPresence = true
        presenceTask = Task { [weak self] in
            guard let self else { return }
            for saved in hosts {
                guard !Task.isCancelled, self.presenceGeneration == token else { return }
                guard saved.supportsPresenceProbe == true, saved.hostID.flatMap(UUID.init(uuidString:)) != nil else { continue }
                for path in network.map({ [$0] }) ?? RemoteNetwork.allCases {
                    guard !Task.isCancelled, self.presenceGeneration == token else { return }
                    guard let pairing = saved.pairing(for: path), pairing.isValid,
                          path == .lan || EmbeddedTailnet.shared.ready else { continue }
                    if self.connected && self.currentPairing == pairing { break }
                    if await self.checkPresence(saved, pairing: pairing, token: token) { break }
                }
            }
            if self.presenceGeneration == token { self.checkingPresence = false; self.presenceTask = nil }
        }
    }
    private func checkPresence(_ saved: RememberedMac, pairing: LANPairing, token: UUID) async -> Bool {
        presence[saved.id] = .init(network: pairing.connectionNetwork, message: "正在检查…", checkedAt: nil)
        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let probe = LANPresenceProbe(hostID: saved.hostID ?? "") { [weak self] reply in
                if let self, self.presenceGeneration == token {
                    self.presenceProbes.removeValue(forKey: saved.id)
                    let message: String
                    if let reply {
                        if !reply.sessionActive { message = "在线 · 用户会话暂不可用，未验证锁屏输入" }
                        else if !reply.displayAvailable { message = "在线 · 显示器／画面暂不可用" }
                        else if reply.busy { message = "在线 · 已有设备连接" }
                        else { message = "在线 · 服务可连接" }
                    } else { message = "暂时无法连接 · 检查 Mac 服务、网络或睡眠状态" }
                    self.presence[saved.id] = .init(network: pairing.connectionNetwork, message: message, checkedAt: Date())
                }
                continuation.resume(returning: reply != nil)
            }
            presenceProbes[saved.id] = probe
            probe.start()
            Task { await self.attachProbe(probe, pairing: pairing) }
        }
    }

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
    @Published private(set) var supportsScrollDynamics = false
    @Published private(set) var lastScrollEnd = "尚无滚动抬手记录"
    @Published var scrollInertia = ScrollTuning.coefficient(UserDefaults.standard.object(forKey: ScrollTuning.key) as? Double ?? ScrollTuning.defaultCoefficient) {
        didSet { UserDefaults.standard.set(ScrollTuning.coefficient(scrollInertia), forKey: ScrollTuning.key); release() }
    }
    @Published private(set) var supportsTextInput = false
    @Published private(set) var supportsWindowOverview = false
    @Published private(set) var supportsDesktopSwitch = false
    @Published private(set) var textFocus: LANTextFocus?
    @Published private(set) var mouseButtonDown = false
    @Published private(set) var textInputEpoch = 0
    @Published private(set) var videoQuality: LANVideoQuality?
    @Published private(set) var availableVideoQualities = LANVideoQuality.legacy
    @Published private(set) var sourceRefreshRate: Double?
    @Published var prefersH264 = UserDefaults.standard.object(forKey: "preferH264V1") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(prefersH264, forKey: "preferH264V1")
            if supportsH264 { link?.send(.videoRequest, value: LANVideoRequest(codec: prefersH264 ? "h264" : "jpeg", keyframe: true)) }
        }
    }
    @Published private(set) var videoCodec = "JPEG"
    @Published private(set) var roundTripMS: Double?
    private var supportsH264 = false
    private var pingNonce: Data?
    private var pingSentAt: TimeInterval = 0
    var streamMetadata: String {
        let resolution = image.map { "\($0.width)×\($0.height)" } ?? "—×—"
        let latency = roundTripMS.map { String(format: "%.0f ms", $0) } ?? "—"
        return "\(connectionNetwork == .lan ? "LAN" : "Tailscale") · \(videoCodec) · \(resolution) · \(String(format: "%.0f", videoFPS)) fps · \(String(format: "%.2f", videoMbps)) Mbps · RTT \(latency)"
    }
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
        cancelPresenceChecks(); presence.removeValue(forKey: id)
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
    private func remember(_ pairing: LANPairing, hostName: String, hostID: String?, supportsPresenceProbe: Bool?, endpoints: [LANEndpoint]?) {
        var library = PairedMacLibrary(hosts: rememberedMacs)
        library.remember(pairing, name: hostName, hostID: hostID, supportsPresenceProbe: supportsPresenceProbe, endpoints: endpoints)
        if library.hosts != rememberedMacs || rememberedPairingSaveFailed { _ = saveLibrary(library) }
    }

    func connect(_ pairing: LANPairing, automaticHostID: UUID? = nil, retry: Int = 0) {
        disconnect()
        autoTargetID = automaticHostID; autoRetryCount = retry; connectedAt = Date()
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
                    connectionLost(error.localizedDescription)
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
        let decoder = H264Decoder()
        var requestedDecoderFallback = false
        var lastKeyframeRequest = -Double.infinity
        link = wire; connecting = true
        status = "正在通过\(pairing.connectionNetwork.title)验证配对并连接 Mac…"
        let name = UIDevice.current.name
        wire.onReady = { [weak self, weak wire] in
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                self.currentPairing = pairing
                self.connected = true; self.connecting = false; self.lastPacket = Date()
                self.status = "已通过\(pairing.connectionNetwork.title)建立加密连接，等待屏幕画面"
                wire?.send(.hello, value: LANHello(name: name, videoCodecs: ["h264", "jpeg"], preferredVideoCodec: self.prefersH264 ? "h264" : "jpeg"))
                let heartbeat = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                    Task { @MainActor in
                        guard let self else { return }
                        if Date().timeIntervalSince(self.lastPacket) > 6 { self.connectionLost("连接中断，控制已释放") }
                        else {
                            if self.pingNonce == nil || ProcessInfo.processInfo.systemUptime - self.pingSentAt > 6 {
                                let nonce = Data(UUID().uuidString.utf8)
                                self.pingNonce = nonce; self.pingSentAt = ProcessInfo.processInfo.systemUptime
                                self.link?.send(.ping, data: nonce)
                            } else { self.link?.send(.ping) }
                        }
                        if let sample = self.traffic.sample(now: ProcessInfo.processInfo.systemUptime) {
                            self.videoMbps = sample.mbps; self.videoFPS = sample.fps
                        }
                    }
                }
                self.heartbeat = heartbeat
                RunLoop.main.add(heartbeat, forMode: .common)
            }
        }
        wire.onPacket = { [weak self, weak wire] kind, data in
            // Image decoding happens on the connection queue, outside the UI actor.
            var decoded: CGImage?
            if kind == .frame { decoder.invalidate(); requestedDecoderFallback = false }
            if kind == .frame, let source = CGImageSourceCreateWithData(data as CFData, nil) {
                decoded = CGImageSourceCreateThumbnailAtIndex(source, 0,
                    [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 4096,
                     kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary)
            }
            if kind == .videoFrame {
                if let packet = H264Packet(data) { decoded = decoder.decode(packet) }
                else { requestedDecoderFallback = true; wire?.send(.videoRequest, value: LANVideoRequest(codec: "jpeg")) }
                if decoder.failed, !requestedDecoderFallback {
                    requestedDecoderFallback = true; wire?.send(.videoRequest, value: LANVideoRequest(codec: "jpeg"))
                } else if decoder.needsKeyframe, !requestedDecoderFallback,
                          ProcessInfo.processInfo.systemUptime - lastKeyframeRequest > 1 {
                    lastKeyframeRequest = ProcessInfo.processInfo.systemUptime
                    wire?.send(.videoRequest, value: LANVideoRequest(codec: "h264", keyframe: true))
                }
            }
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                self.lastPacket = Date()
                switch kind {
                case .ping:
                    if data == self.pingNonce, !data.isEmpty {
                        self.roundTripMS = min(12000, max(0, (ProcessInfo.processInfo.systemUptime - self.pingSentAt) * 1000))
                        self.pingNonce = nil
                    }
                case .frame, .videoFrame:
                    self.traffic.record(bytes: data.count, now: ProcessInfo.processInfo.systemUptime)
                    if let decoded {
                        self.image = decoded; self.receivedFrames += 1
                        self.videoCodec = kind == .videoFrame ? "H.264" : "JPEG"
                    }
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
                    self.supportsH264 = state.supportsH264 == true
                    self.supportsScrollDynamics = state.supportsScrollDynamics ?? false
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
                    if let pairing = self.currentPairing { self.remember(pairing, hostName: state.name, hostID: state.hostID, supportsPresenceProbe: state.supportsPresenceProbe, endpoints: state.endpoints) }
                    if self.connectionPreference == .automatic, let current = self.currentPairing {
                        self.autoTargetID = self.rememberedMacs.first { $0.pairing.secret == current.secret }?.id
                    }
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
                self.connectionLost(pairing.connectionNetwork == .tailscale
                    ? reason + "。请确认两端 Tailscale 在线且 Mac 入口开启。" : reason)
            }
        }
        wire.start()
    }

    func touchpad(_ event: TouchpadEvent, origin: String = "inner") {
        if event == .leftClick || event == .rightClick || event == .dragBegan { textInputEpoch += 1 }
        var input = LANInput(event); input.origin = origin; send(input)
    }

    func scroll(_ sample: ScrollGestureEvent) {
        guard acceptsInput, sample.isValid else { return }
        if sample.phase == .ended {
            lastScrollEnd = "\(sample.mode == .trackpad ? "触控板" : "直接触屏")抬手 · 速度 \(String(format: "%.2f", abs(sample.velocity.y))) 区域／秒 · 系数 \(String(format: "%.1f", scrollInertia)) · \(supportsScrollDynamics ? "惯性协议" : "旧主机普通滚动")"
        }
        if supportsScrollDynamics {
            var value = sample; value.coefficient = ScrollTuning.coefficient(scrollInertia)
            send(LANInput(scroll: value))
        } else if sample.phase == .changed {
            // Old hosts retain their existing scroll protocol; never run a second
            // phone-side inertia simulation on top of the host's momentum.
            if sample.mode == .direct {
                directTouch(.init(action: .scroll, point: sample.anchor, delta: sample.delta))
            } else { touchpad(.scrolled(amount: sample.delta.y)) }
        }
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
        cancelRouteAttempts()
        cancelPresenceChecks()
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
        supportsScrollDynamics = false
        supportsWindowOverview = false; supportsDesktopSwitch = false
        supportsTextInput = false; textFocus = nil; mouseButtonDown = false; textInputEpoch += 1
        displayMessage = "连接新版 Mac 主机后显示可用显示器"
        scaleState = nil; videoQuality = nil; videoMbps = 0; videoFPS = 0; traffic = VideoTrafficMeter()
        roundTripMS = nil; pingNonce = nil; supportsH264 = false; videoCodec = "JPEG"
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
    @Environment(\.scenePhase) private var scenePhase
    @State private var host = ""
    @State private var port = ""
    @State private var secret = ""
    @State private var showScanner = false
    @State private var error = ""
    @State private var forgetting: RememberedMac?
    @State private var preference = ConnectionPreference.automatic
    private var network: RemoteNetwork { preference.network ?? client.connectionNetwork }
    @State private var initialized = false
    @ObservedObject private var tailnet = EmbeddedTailnet.shared
    var body: some View {
        NavigationStack {
            Form {
                Section("连接方式") {
                    Picker("连接方式", selection: $preference) {
                        ForEach(ConnectionPreference.allCases) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented).accessibilityIdentifier("connection-network-mode")
                    if preference == .automatic {
                        Text("自动检查已绑定的局域网与 Tailscale，选择先验证通过的可用路径。设备按加密身份识别，不按名称合并；换网后有限次自动重连。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    if preference == .lan {
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
                                Button { client.connectSaved(saved, preference: preference); dismiss() } label: {
                                    Label(saved.hostName.isEmpty ? "Mac" : saved.hostName, systemImage: "desktopcomputer")
                                }.buttonStyle(.borderless)
                                    .disabled(preference.network.map { saved.pairing(for: $0) == nil } ?? false || (preference == .tailscale && !tailnet.ready))
                                    .accessibilityIdentifier("lan-reconnect-" + saved.id.uuidString)
                                Text(preference == .automatic ? "自动 · " + RemoteNetwork.allCases.filter { saved.pairing(for: $0) != nil }.map(\.title).joined(separator: " / ") : saved.pairing(for: network).map { "\($0.connectionNetwork.title)配对 · \($0.host):\($0.port)" } ?? "尚未绑定此模式，请扫描 Mac 对应模式的二维码")
                                    .font(.caption).foregroundStyle(.secondary)
                                Text(client.presenceMessage(saved, network: preference.network))
                                    .font(.caption).foregroundStyle(.secondary)
                                    .accessibilityIdentifier("lan-presence-" + saved.id.uuidString)
                                if let checked = client.presence[saved.id], (preference == .automatic || checked.network == network), let date = checked.checkedAt {
                                    Text("上次检查：\(date.formatted(date: .omitted, time: .standard))")
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                                Button("忘记这台 Mac", role: .destructive) { forgetting = saved }
                                    .buttonStyle(.borderless)
                                    .accessibilityIdentifier("lan-forget-" + saved.id.uuidString)
                            }
                        }
                        Button { client.refreshPresence(network: preference.network) } label: {
                            Label(client.checkingPresence ? "正在检查在线状态…" : "刷新在线状态", systemImage: "arrow.clockwise")
                        }.buttonStyle(.borderless).disabled(client.checkingPresence)
                            .accessibilityIdentifier("lan-refresh-presence")
                        Text("在线表示 Chordesk 服务刚刚通过加密验证，不代表屏幕已唤醒或锁屏可输入。无法连接也可能是地址变化或网络不通，不等于 Mac 已关机。")
                            .font(.footnote).foregroundStyle(.secondary)
                        Text("配对凭据仅保存在此 iPhone 钥匙串。新版主机通过已认证连接补齐其他可用地址，通常无需分别扫码；同名电脑不会合并。Tailscale 首次仍需登录自己的私人网络。一次控制一台。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section("在 Mac 开启服务，扫描配对二维码") {
                    Button { showScanner = true } label: { Label(preference == .automatic ? "扫描 Mac 配对二维码" : "扫描 Mac \(network.title)配对二维码", systemImage: "qrcode.viewfinder") }
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
                if !initialized { initialized = true; preference = client.connectionPreference; port = String(LANPairing.defaultPort) }
                client.refreshPresence(network: preference.network)
            }
            .onChange(of: preference) { _, value in
                client.connectionPreference = value
                host = ""; secret = ""; error = ""; client.refreshPresence(network: preference.network)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { client.cancelPresenceChecks() }
                else { client.refreshPresence(network: preference.network) }
            }
            .onDisappear { client.cancelPresenceChecks() }
            .alert("忘记这台 Mac？", isPresented: Binding(get: { forgetting != nil }, set: { if !$0 { forgetting = nil } }), presenting: forgetting) { saved in
                Button("忘记", role: .destructive) { client.forgetRememberedMac(saved.id); forgetting = nil }
                Button("取消", role: .cancel) { forgetting = nil }
            } message: { saved in Text("只删除手机上的“\(saved.hostName.isEmpty ? "Mac" : saved.hostName)”记录，其他配对保留。下次需要重新扫码。") }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } } }
            .sheet(isPresented: $showScanner) {
                QRScannerView { result in
                    showScanner = false
                    if let value = LANPairing.parse(result) {
                        if value.invitationHostID == nil && value.connectionNetwork == .tailscale && !tailnet.ready {
                            preference = .automatic; error = "请先登录 Tailscale，再扫描公网配对二维码。"
                        } else { client.connectInvitation(value); dismiss() }
                    }
                    else { error = "不是有效的 Chordesk 配对二维码；请确认两端均使用支持该连接模式的版本" }
                }
            }
        }
    }
}
#endif

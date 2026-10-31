import Foundation
import Network
import Security
import CoreGraphics
import Darwin

enum RemoteNetwork: String, Codable, CaseIterable, Identifiable {
    case lan, tailscale
    var id: String { rawValue }
    var title: String { self == .lan ? "局域网" : "Tailscale 公网" }
    var symbol: String { self == .lan ? "wifi" : "network" }
    func accepts(_ address: String) -> Bool {
        self == .lan ? LANPairing.isLocalHost(address) : LANPairing.isTailscaleHost(address)
    }
}

/// An interface address is a routing hint, never proof of login or identity.
/// Keep the existing pairing PSK mandatory even on a private tailnet.
struct RemoteInterfaceAddress: Equatable {
    var name: String
    var address: String
    var isUp: Bool
    static func current() -> [Self] {
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0 else { return [] }
        defer { freeifaddrs(pointer) }
        var current = pointer, result: [Self] = []
        while let entry = current {
            defer { current = entry.pointee.ifa_next }
            guard let address = entry.pointee.ifa_addr, address.pointee.sa_family == UInt8(AF_INET) else { continue }
            var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(address, socklen_t(address.pointee.sa_len), &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            result.append(.init(name: String(cString: entry.pointee.ifa_name), address: String(cString: buffer),
                                isUp: entry.pointee.ifa_flags & UInt32(IFF_UP) != 0))
        }
        return result
    }
}

/// Chordesk pairing remains independent of the optional Tailscale account.
struct LANPairing: Codable, Equatable {
    static let defaultPort: UInt16 = 49_173
    var version = 1
    var host: String
    var port: UInt16
    var secret: String
    var network: RemoteNetwork? = nil
    var connectionNetwork: RemoteNetwork { network ?? .lan }

    init(host: String, port: UInt16, secret: String, network: RemoteNetwork = .lan) {
        self.host = host; self.port = port; self.secret = secret
        self.network = network == .lan ? nil : network
        version = network == .lan ? 1 : 2
    }

    var code: String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return "duoremote:" + (try! encoder.encode(self)).base64EncodedString()
    }

    static func parse(_ value: String) -> LANPairing? {
        guard value.count < 4096, value.hasPrefix("duoremote:"), let data = Data(base64Encoded: String(value.dropFirst(10))),
              let pairing = try? JSONDecoder().decode(Self.self, from: data), pairing.isValid else { return nil }
        return pairing
    }

    var isValid: Bool {
        let supported = (version == 1 && connectionNetwork == .lan) || (version == 2 && network == .tailscale)
        return supported && port > 0 && connectionNetwork.accepts(host) && Self.isValidSecret(secret)
    }

    static func isLocalHost(_ value: String) -> Bool {
        let parts = value.split(separator: ".").compactMap { UInt8($0) }
        guard parts.count == 4, parts.map(String.init).joined(separator: ".") == value else { return false }
        return parts[0] == 10 || parts[0] == 127 || (parts[0] == 192 && parts[1] == 168)
            || (parts[0] == 172 && (16...31).contains(parts[1])) || (parts[0] == 169 && parts[1] == 254)
    }

    static func isTailscaleHost(_ value: String) -> Bool {
        let parts = value.split(separator: ".").compactMap { UInt8($0) }
        guard parts.count == 4, parts.map(String.init).joined(separator: ".") == value else { return false }
        return parts[0] == 100 && (64...127).contains(parts[1])
    }

    static func newSecret() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw LANWireError.random }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    static func isValidSecret(_ value: String) -> Bool {
        value.count == 32 && value.allSatisfy { $0.isASCII && $0.isHexDigit }
    }
}

/// Identity comes from the authenticated host, never its display name or IP.
struct RememberedMac: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var pairing: LANPairing
    var hostName: String
    var hostID: String? = nil
    var alternativePairings: [LANPairing]? = nil
    func pairing(for network: RemoteNetwork) -> LANPairing? {
        if pairing.connectionNetwork == network { return pairing }
        return alternativePairings?.first { $0.isValid && $0.connectionNetwork == network && $0.secret == pairing.secret }
    }
}
struct PairedMacLibrary: Codable, Equatable {
    var hosts: [RememberedMac] = []
    mutating func remember(_ pairing: LANPairing, name: String, hostID: String?) {
        guard pairing.isValid else { return }
        let identity = hostID.flatMap(UUID.init(uuidString:))?.uuidString
        let match = hosts.firstIndex { existing in
            (identity != nil && existing.hostID == identity) || existing.pairing.secret == pairing.secret
        }
        var item = match.map { hosts[$0] } ?? RememberedMac(pairing: pairing, hostName: "Mac")
        // Preserve one authenticated endpoint per mode, but never retain an old
        // key after a credential rotation. Legacy single-endpoint records decode unchanged.
        let previous = [item.pairing] + (item.alternativePairings ?? [])
        item.alternativePairings = RemoteNetwork.allCases.filter { $0 != pairing.connectionNetwork }.compactMap { network in
            previous.first { $0.isValid && $0.secret == pairing.secret && $0.connectionNetwork == network }
        }
        item.pairing = pairing; item.hostName = String(name.prefix(80))
        item.hostID = identity ?? item.hostID
        if let match { hosts.remove(at: match) }
        hosts.insert(item, at: 0)
    }
    mutating func forget(_ id: UUID) { hosts.removeAll { $0.id == id } }
}

/// Stores long-lived pairing credentials in the platform Keychain.
enum LANCredentialStore {
    private static let service = "dev.iphoneduo.remote-pairing"

    static func read(account: String) -> Data? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    @discardableResult
    static func write(_ data: Data, account: String) -> Bool {
        let query = baseQuery(account: account)
        let attributes: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return true }
        guard updateStatus == errSecItemNotFound else { return false }
        var addQuery = query
        addQuery[kSecValueData as String] = data
#if os(iOS)
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
#endif
        return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
    }

    @discardableResult
    static func remove(account: String) -> Bool {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    private static func baseQuery(account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }
}

enum LANWireError: Error { case random, malformed }
enum LANPacket: UInt8 { case hello = 1, status = 2, frame = 3, input = 4, ping = 5, release = 6, acknowledgement = 7, displays = 8, selectDisplay = 9, requestDisplays = 10, adjustScale = 11, textInput = 12, videoQuality = 13, microphoneRequest = 14, microphoneState = 15, microphoneAudio = 16 }

enum LANVideoQuality: String, CaseIterable, Identifiable, Codable {
    case efficient, sharp, ultra, responsive60, experimental120, experimental144
    var id: String { rawValue }
    static let legacy: [Self] = [.efficient, .sharp, .ultra]
    static func supported(by advertised: [String]?) -> [Self] {
        guard let advertised else { return legacy }
        return allCases.filter { advertised.contains($0.rawValue) }
    }
    var title: String {
        switch self {
        case .efficient: "省流 · 15 fps"
        case .sharp: "清晰 · 24 fps"
        case .ultra: "超清 · 24 fps"
        case .responsive60: "低分辨率 · 60 fps"
        case .experimental120: "实验 · 120 fps"
        case .experimental144: "实验 · 144 fps"
        }
    }
    var maximumEdge: Int {
        switch self {
        case .efficient, .responsive60: 1280
        case .sharp: 2560
        case .ultra: 3840
        case .experimental120: 960
        case .experimental144: 800
        }
    }
    var framesPerSecond: Int32 {
        switch self {
        case .efficient: 15
        case .sharp, .ultra: 24
        case .responsive60: 60
        case .experimental120: 120
        case .experimental144: 144
        }
    }
    var jpegQuality: Double {
        switch self {
        case .efficient, .responsive60: 0.65
        case .sharp: 0.86
        case .ultra: 0.94
        case .experimental120: 0.55
        case .experimental144: 0.50
        }
    }
    var detail: String { "最长边 \(maximumEdge) 像素 · JPEG \(Int(jpegQuality * 100))% · 请求上限 \(framesPerSecond) fps" }
    func captureSize(pixels: CGSize) -> CGSize {
        guard pixels.width > 0, pixels.height > 0 else { return CGSize(width: 2, height: 2) }
        let scale = min(1, CGFloat(maximumEdge) / max(pixels.width, pixels.height))
        return CGSize(width: max(2, Int(pixels.width * scale) / 2 * 2), height: max(2, Int(pixels.height * scale) / 2 * 2))
    }
}

struct VideoTrafficMeter {
    private var start: TimeInterval?
    private var bytes = 0
    private var frames = 0
    mutating func record(bytes: Int, now: TimeInterval) {
        if start == nil { start = now }
        self.bytes += max(0, bytes); frames += 1
    }
    mutating func sample(now: TimeInterval) -> (mbps: Double, fps: Double)? {
        guard let start, now - start >= 1 else { return nil }
        let elapsed = now - start
        let value = (Double(bytes) * 8 / elapsed / 1_000_000, Double(frames) / elapsed)
        self.start = now; bytes = 0; frames = 0
        return value
    }
}

struct LANHello: Codable { var name: String; var displaySelection = true; var microphone: Bool? = true }
struct LANDisplay: Codable, Identifiable, Equatable {
    var id: UInt32
    var name: String
    var width: Double
    var height: Double
}
struct LANDisplayCatalog: Codable {
    var displays: [LANDisplay]
    var selectedID: UInt32?
    var canSwitch: Bool
    var message: String
    var scale: LANScaleState? = nil
}

struct LANScaleOption: Codable, Identifiable {
    var id: String
    var title: String
    var detail: String
}
struct LANScaleState: Codable {
    var displayID: UInt32
    var current: String
    var options: [LANScaleOption]
    var canRestore: Bool
    var canAdjust: Bool
    var message: String
}
struct LANScaleRequest: Codable { var displayID: UInt32; var choice: String }

struct LANStatus: Codable {
    var version = 1
    var name: String
    var width: Double
    var height: Double
    var canControl: Bool
    var message: String
    var selectedDisplayID: UInt32? = nil
    var displayName: String? = nil
    var supportsDisplaySelection: Bool? = nil
    var switchingDisplay: Bool? = nil
    var captureRevision: String? = nil
    var supportsDirectTouch: Bool? = nil
    var supportsTextInput: Bool? = nil
    var textFocus: LANTextFocus? = nil
    var mouseButtonDown: Bool? = nil
    var videoQuality: String? = nil
    var supportsWindowOverview: Bool? = nil
    var supportsDesktopSwitch: Bool? = nil
    var supportedVideoQualities: [String]? = nil
    var supportsMicrophone: Bool? = nil
    var sourceRefreshRate: Double? = nil
    var hostID: String? = nil
}

struct LANInput: Codable {
    var action: String
    var origin: String = "inner"
    var x: Double = 0
    var y: Double = 0
    var key: String = ""
    var modifiers: UInt = 0
    var sequence: UInt64 = 0
    var displayID: UInt32? = nil
    var captureRevision: String? = nil
    var scrollX: Double? = nil
    var scrollY: Double? = nil
    var clickCount: Int? = nil

    init(direct event: DirectTouchEvent) {
        action = "touch." + event.action.rawValue
        origin = "inner-direct"
        x = event.point.x; y = event.point.y
        scrollX = event.delta.x; scrollY = event.delta.y; clickCount = event.clicks
    }

    var directTouch: DirectTouchEvent? {
        guard action.hasPrefix("touch."), let kind = DirectTouchEvent.Action(rawValue: String(action.dropFirst(6))) else { return nil }
        let event = DirectTouchEvent(action: kind, point: CGPoint(x: x, y: y),
                                    delta: CGPoint(x: scrollX ?? 0, y: scrollY ?? 0), clicks: clickCount ?? 1)
        return event.isValid ? event : nil
    }

    init(_ event: TouchpadEvent) {
        switch event {
        case let .pointerMoved(dx, dy): action = "move"; x = Double(dx); y = Double(dy)
        case let .dragMoved(dx, dy): action = "move"; x = Double(dx); y = Double(dy)
        case .leftClick: action = "click"
        case .rightClick: action = "rightClick"
        case .dragBegan: action = "down"
        case .dragEnded: action = "up"
        case let .scrolled(amount): action = "scroll"; y = Double(amount)
        }
    }

    init(key: String, modifiers: UInt) { action = "key"; self.key = key; self.modifiers = modifiers }
    init(overview: WindowOverviewAction) {
        switch overview {
        case .show: action = "window.show"
        case .hide: action = "window.hide"
        case .previousDesktop: action = "desktop.previous"
        case .nextDesktop: action = "desktop.next"
        }
        origin = "window-overview"
    }
    var windowOverview: WindowOverviewAction? {
        switch action {
        case "window.show": .show
        case "window.hide": .hide
        case "desktop.previous": .previousDesktop
        case "desktop.next": .nextDesktop
        default: nil
        }
    }
}

/// TLS 1.2 PSK authenticates both ends using the random 128-bit pairing key.
/// It never disables certificate verification or sends the key over the connection.
enum LANTransport {
    static func listener(secret: String, localAddress: String, port: NWEndpoint.Port = NWEndpoint.Port(rawValue: LANPairing.defaultPort)!, network: RemoteNetwork = .lan) throws -> NWListener {
        guard network.accepts(localAddress), LANPairing.isValidSecret(secret) else { throw LANWireError.malformed }
        let options = parameters(secret: secret)
        // NWListener sets its port itself. Supplying a concrete port in both
        // requiredLocalEndpoint and init(using:on:) produces EINVAL.
        options.requiredLocalEndpoint = .hostPort(host: NWEndpoint.Host(localAddress), port: .any)
        return try NWListener(using: options, on: port)
    }

    static func parameters(secret: String) -> NWParameters {
        let tls = NWProtocolTLS.Options()
        let key = Data(stride(from: 0, to: secret.count, by: 2).compactMap { offset -> UInt8? in
            let start = secret.index(secret.startIndex, offsetBy: offset)
            let end = secret.index(start, offsetBy: 2, limitedBy: secret.endIndex) ?? secret.endIndex
            return UInt8(secret[start..<end], radix: 16)
        })
        let identity = Data("DuoRemote-v1".utf8)
        key.withUnsafeBytes { keyBytes in
            identity.withUnsafeBytes { identityBytes in
                sec_protocol_options_add_pre_shared_key(tls.securityProtocolOptions,
                    DispatchData(bytes: keyBytes) as __DispatchData, DispatchData(bytes: identityBytes) as __DispatchData)
            }
        }
        sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)
        sec_protocol_options_set_max_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)
        // Public CipherSuite.h defines TLS_PSK_WITH_AES_128_GCM_SHA256 as 0x00A8.
        sec_protocol_options_append_tls_ciphersuite(tls.securityProtocolOptions, tls_ciphersuite_t(rawValue: 0x00A8)!)
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        tcp.enableKeepalive = true
        let parameters = NWParameters(tls: tls, tcp: tcp)
        parameters.includePeerToPeer = false
        return parameters
    }
}

/// All framing and writes are serialized on this connection's queue.
/// Frames have bounded size and are dropped rather than queued behind a slow peer.
final class LANLink {
    static let maximumPacketSize = 4 * 1024 * 1024
    let connection: NWConnection
    let queue = DispatchQueue(label: "dev.iphoneduo.lan-link", qos: .userInteractive)
    var onReady: (() -> Void)?
    var onPacket: ((LANPacket, Data) -> Void)?
    var onClose: ((String) -> Void)?
    var onFrameSent: ((Int) -> Void)?
    private var closed = false
    private var pendingBytes = 0

    init(_ connection: NWConnection) { self.connection = connection }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self, !self.closed else { return }
            switch state {
            case .ready: self.onReady?(); self.readHeader()
            case .failed(let error): self.finish(error.localizedDescription)
            case .cancelled: self.finish("连接已结束")
            default: break
            }
        }
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + 12) { [weak self] in
            guard let self, self.connection.state != .ready else { return }
            self.finish("连接超时，请检查地址、配对密钥及 Mac 服务；公网模式还需两端 Tailscale 在线且允许互访")
        }
    }

    func send<T: Encodable>(_ kind: LANPacket, value: T) {
        if let data = try? JSONEncoder().encode(value) { send(kind, data: data) }
    }

    func send(_ kind: LANPacket, data: Data = Data(), droppable: Bool = false) {
        queue.async { [weak self] in
            guard let self, !self.closed, data.count <= Self.maximumPacketSize else { return }
            if kind == .microphoneAudio && (data.count != MicrophonePacket.byteCount || self.pendingBytes > MicrophonePacket.byteCount * 6) { return }
            if droppable && self.pendingBytes > 512 * 1024 { return }
            guard self.pendingBytes < Self.maximumPacketSize * 2 else { self.finish("连接过慢，已停止排队"); return }
            var packet = Data([kind.rawValue])
            var length = UInt32(data.count).bigEndian
            withUnsafeBytes(of: &length) { packet.append(contentsOf: $0) }
            packet.append(data)
            let count = packet.count
            self.pendingBytes += count
            self.connection.send(content: packet, completion: .contentProcessed { [weak self] error in
                guard let self else { return }
                self.pendingBytes -= count
                if let error { self.finish(error.localizedDescription) }
                else if kind == .frame { self.onFrameSent?(data.count) }
            })
        }
    }

    func close() { queue.async { self.finish("连接已结束") } }

    deinit { connection.cancel() }

    private func finish(_ reason: String) {
        guard !closed else { return }
        closed = true
        connection.cancel()
        onClose?(reason)
        onReady = nil; onPacket = nil; onClose = nil
    }

    private func readHeader() {
        connection.receive(minimumIncompleteLength: 5, maximumLength: 5) { [weak self] data, _, complete, error in
            guard let self, !self.closed else { return }
            guard let data, data.count == 5, let kind = LANPacket(rawValue: data[0]), error == nil else {
                self.finish(error?.localizedDescription ?? "连接已关闭或数据头无效"); return
            }
            let length = data.dropFirst().reduce(0) { ($0 << 8) | Int($1) }
            guard length <= Self.maximumPacketSize else { self.finish("数据包超过上限"); return }
            if length == 0 {
                self.onPacket?(kind, Data())
                if complete { self.finish("连接已关闭") } else { self.readHeader() }
            } else { self.readPayload(kind, count: length) }
        }
    }

    private func readPayload(_ kind: LANPacket, count: Int) {
        connection.receive(minimumIncompleteLength: count, maximumLength: count) { [weak self] data, _, complete, error in
            guard let self, !self.closed else { return }
            guard let data, data.count == count, error == nil else { self.finish(error?.localizedDescription ?? "数据包不完整"); return }
            self.onPacket?(kind, data)
            if complete { self.finish("连接已关闭") } else { self.readHeader() }
        }
    }
}

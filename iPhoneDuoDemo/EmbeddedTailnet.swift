import Foundation
import SwiftUI
import ChordeskTailnet
#if os(iOS)
import SafariServices
#else
import AppKit
#endif

struct TailnetSnapshot: Decodable, Equatable {
    var state: String?
    var authURL: String?
    var addresses: [String]?
    var error: String?
    var port: UInt16?
    var identifier: Int32?
    var health: [String]?
    var ready: Bool { state == "Running" && (addresses?.contains(where: LANPairing.isTailscaleHost) == true) }
    var loginURL: URL? {
        guard let raw = authURL, let url = URL(string: raw), url.scheme == "https",
              url.host == "login.tailscale.com", url.user == nil, url.password == nil,
              url.port == nil || url.port == 443 else { return nil }
        return url
    }
    var loginDiagnostic: String? {
        guard state == "NeedsLogin" else { return nil }
        guard let raw = authURL, !raw.isEmpty else { return "正在向 Tailscale 请求登录页面；暂未收到地址。" }
        if loginURL == nil { return "登录页面未通过地址检查（" + (URL(string: raw)?.host ?? "未知地址") + "），请更新 App 或反馈此提示。" }
        return "已收到官方登录页面；未自动打开时可点下方按钮。"
    }
}

/// The engine is app-scoped, not a system VPN. All C calls run off the UI actor
/// and in order. Generation checks prevent stale login/dial results resurfacing.
@MainActor
final class EmbeddedTailnet: ObservableObject {
    static let shared = EmbeddedTailnet()
    @Published private(set) var snapshot = TailnetSnapshot(state: "Stopped")
    @Published private(set) var busy = false
    @Published private(set) var message = "公网关闭；局域网无需登录。"
    @Published private(set) var enabled = false
    @Published var showLogin = false
    private let queue = DispatchQueue(label: "dev.chordesk.embedded-tailnet", qos: .userInitiated)
    private var polling: Task<Void, Never>?
    private var generation = UUID()
    private var requestLoginPresentation = false
    var ready: Bool { enabled && snapshot.ready }
    var addresses: [String] { ready ? (snapshot.addresses ?? []).filter(LANPairing.isTailscaleHost) : [] }
    var shouldResume: Bool { UserDefaults.standard.bool(forKey: "ChordeskEmbeddedTailnetEnabledV1") }

    private func call(_ operation: @escaping () -> UnsafeMutablePointer<CChar>?) async -> TailnetSnapshot {
        await withCheckedContinuation { continuation in
            queue.async {
                guard let result = operation() else {
                    continuation.resume(returning: .init(error: "公网引擎没有返回结果")); return
                }
                defer { free(result) }
                let value = (try? JSONDecoder().decode(TailnetSnapshot.self, from: Data(String(cString: result).utf8)))
                    ?? .init(error: "公网引擎返回了无效状态")
                continuation.resume(returning: value)
            }
        }
    }
    private func update(_ value: TailnetSnapshot) {
        if let error = value.error { snapshot = value; message = error; return }
        if snapshot != value { snapshot = value }
        if value.loginURL != nil, requestLoginPresentation {
            requestLoginPresentation = false; showLogin = true
        }
        switch value.state {
        case "Running": message = "已连接我的 Tailscale 私人网络"; showLogin = false
        case "NeedsLogin": message = "请登录 Tailscale，授权此 Chordesk 设备加入你的私人网络。"
        case "NeedsMachineAuth": message = "请在 Tailscale 管理页面批准这台设备，再返回继续。"
        case "Stopped": message = "公网已断开；局域网仍可用。"
        default: message = "正在连接 Tailscale…"
        }
    }
    func connect(interactive: Bool = true) {
        guard !busy else { return }
        if enabled { presentLogin(); return }
        generation = UUID(); let token = generation
        enabled = true; busy = true; requestLoginPresentation = interactive
        UserDefaults.standard.set(true, forKey: "ChordeskEmbeddedTailnetEnabledV1")
        message = "正在启动内嵌 Tailscale…"
        Task {
            guard token == generation else { return }
            do {
                let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                var directory = base.appendingPathComponent("Chordesk/Tailnet", isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                var values = URLResourceValues(); values.isExcludedFromBackup = true
                try directory.setResourceValues(values)
#if os(iOS)
                let name = "chordesk-iphone"
#else
                let name = "chordesk-mac"
#endif
                let path = directory.path
                let value = await call { path.withCString { p in name.withCString { n in CRStart(UnsafeMutablePointer(mutating: p), UnsafeMutablePointer(mutating: n)) } } }
                guard token == generation else { return }
                busy = false; update(value)
                if value.error != nil { enabled = false; return }
                beginPolling(token)
            } catch {
                guard token == generation else { return }
                busy = false; enabled = false; message = "无法准备公网节点：" + error.localizedDescription
            }
        }
    }
    func presentLogin() {
        guard !busy else { return }
        if !enabled { connect(); return }
        if snapshot.loginURL != nil { showLogin = true; return }
        guard !ready else { return }
        busy = true; let token = generation
        Task {
            let value = await call { CRLogin() }
            guard generation == token else { return }
            busy = false; update(value)
            if snapshot.loginURL != nil { showLogin = true }
        }
    }
    private func beginPolling(_ token: UUID) {
        polling?.cancel()
        polling = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.generation == token, self.enabled else { return }
                let value = await self.call { CRStatus() }
                guard !Task.isCancelled, self.generation == token else { return }
                self.update(value)
                do { try await Task.sleep(for: .seconds(value.ready ? 5 : 2)) } catch { return }
            }
        }
    }
    func disconnect(preservePreference: Bool = false) {
        let token = prepareDisconnect(preservePreference: preservePreference)
        Task { await finishDisconnect(token) }
    }
    func disconnectAndWait(preservePreference: Bool = false) async {
        let token = prepareDisconnect(preservePreference: preservePreference)
        await finishDisconnect(token)
    }
    private func prepareDisconnect(preservePreference: Bool) -> UUID {
        generation = UUID(); let token = generation
        polling?.cancel(); polling = nil
        enabled = false; busy = true; showLogin = false; snapshot = .init(state: "Stopped")
        message = "正在断开公网…"
        if !preservePreference { UserDefaults.standard.set(false, forKey: "ChordeskEmbeddedTailnetEnabledV1") }
        return token
    }
    private func finishDisconnect(_ token: UUID) async {
        _ = await call { CRStop() }
        guard token == generation else { return }; busy = false; message = "公网已断开；登录记忆保留。"
    }
    func logout() {
        guard !busy, enabled else { return }
        generation = UUID(); let token = generation; polling?.cancel(); polling = nil
        busy = true; showLogin = false; snapshot = .init(state: "Stopped")
        Task {
            let value = await call { CRLogout() }
            guard token == generation else { return }
            busy = false
            if let error = value.error {
                message = "退出账号未完成：" + error; beginPolling(token); return
            }
            enabled = false; snapshot = .init(state: "Stopped"); message = "已退出 Tailscale；局域网配对保留。"
            UserDefaults.standard.set(false, forKey: "ChordeskEmbeddedTailnetEnabledV1")
        }
    }
    func suspend() {
        guard enabled else { return }; disconnect(preservePreference: true)
    }
    func resumeIfNeeded() {
        guard shouldResume, !enabled else { return }
        if busy {
            Task { try? await Task.sleep(for: .milliseconds(300)); if !Task.isCancelled { self.resumeIfNeeded() } }
        } else { connect(interactive: false) }
    }
    func forward(to port: UInt16) async -> Bool {
        guard ready else { return false }
        let token = generation
        let value = await call { CRForward(Int32(port)) }
        guard token == generation, ready else { return false }
        if let error = value.error { message = error; return false }; return true
    }
    // Enqueue synchronously so a subsequent forward cannot overtake this stop.
    func stopForwarding() { queue.async { if let result = CRStopForward() { free(result) } } }
    func dial(_ pairing: LANPairing) async throws -> (port: UInt16, identifier: Int32) {
        guard ready, pairing.connectionNetwork == .tailscale, pairing.isValid else {
            throw NSError(domain: "ChordeskTailnet", code: 1, userInfo: [NSLocalizedDescriptionKey: "请先在 Chordesk 登录并连接 Tailscale"])
        }
        let token = generation
        let value = await call { pairing.host.withCString { CRDial(UnsafeMutablePointer(mutating: $0), Int32(pairing.port)) } }
        guard token == generation, ready, let port = value.port, let id = value.identifier else {
            if let id = value.identifier { closeDial(id) }
            throw NSError(domain: "ChordeskTailnet", code: 2, userInfo: [NSLocalizedDescriptionKey: value.error ?? "公网连接已取消"])
        }
        return (port,id)
    }
    func closeDial(_ id: Int32) { queue.async { if let result = CRCloseDial(id) { free(result) } } }
}

struct EmbeddedTailnetControls: View {
    @ObservedObject var tailnet = EmbeddedTailnet.shared
    @State private var confirmLogout = false
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(tailnet.message, systemImage: tailnet.ready ? "checkmark.shield" : "network")
                .font(.callout).accessibilityIdentifier("tailscale-state")
            if tailnet.ready {
                Text(tailnet.addresses.joined(separator: " · ")).font(.caption.monospaced()).textSelection(.enabled)
            }
            if let diagnostic = tailnet.snapshot.loginDiagnostic { Text(diagnostic).font(.caption).foregroundStyle(.secondary) }
            if !tailnet.ready, let health = tailnet.snapshot.health, !health.isEmpty {
                Text(health.joined(separator: "\n")).font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                if !tailnet.enabled {
                    Button("登录／连接 Tailscale") { tailnet.connect() }.disabled(tailnet.busy)
                        .accessibilityIdentifier("tailscale-connect")
                } else {
                    if !tailnet.ready { Button("打开 Tailscale 登录") { tailnet.presentLogin() }.disabled(tailnet.busy) }
                    Button("断开公网") { tailnet.disconnect() }.disabled(tailnet.busy)
                    Button("退出账号", role: .destructive) { confirmLogout = true }.disabled(tailnet.busy)
                }
                if tailnet.busy { ProgressView().controlSize(.small) }
            }
            Text("两端 Chordesk 登录同一 Tailscale 私人网络，无需额外安装 App。仅 Chordesk 的远程连接走此网络；局域网免登录。个人免费计划以 Tailscale 条件为准。")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Link("个人计划", destination: URL(string: "https://tailscale.com/pricing")!)
                Link("隐私政策", destination: URL(string: "https://tailscale.com/privacy-policy")!)
            }.font(.caption)
        }
        .confirmationDialog("退出此设备的 Tailscale 账号？", isPresented: $confirmLogout, titleVisibility: .visible) {
            Button("退出账号", role: .destructive) { tailnet.logout() }
        } message: { Text("公网连接会断开，局域网配对不会删除。再次使用公网需重新登录。") }
#if os(iOS)
        .sheet(isPresented: $tailnet.showLogin) {
            if let url = tailnet.snapshot.loginURL { TailnetLoginBrowser(url: url).ignoresSafeArea(edges: .bottom) }
        }
#else
        .onChange(of: tailnet.showLogin, initial: true) { _, value in
            if value, let url = tailnet.snapshot.loginURL { NSWorkspace.shared.open(url); tailnet.showLogin = false }
        }
#endif
    }
}
#if os(iOS)
private struct TailnetLoginBrowser: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
#endif

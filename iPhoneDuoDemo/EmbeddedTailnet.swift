import Foundation
import SwiftUI
import ChordeskTailnet
#if os(iOS)
import AuthenticationServices
import UIKit
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
    var ready: Bool { error == nil && state == "Running" && (addresses?.contains(where: LANPairing.isTailscaleHost) == true) }
    // Browser completion is not evidence of enrollment. Only the engine's
    // authenticated Running state and an assigned tailnet address count.
    var canAuthorize: Bool { error == nil && state == "NeedsLogin" }
    var shouldCloseAuthentication: Bool { error == nil && (ready || state == "NeedsMachineAuth") }
    func permitsAuthenticationGrace(browserVisible: Bool) -> Bool {
        browserVisible && canAuthorize
    }
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
        return "请在官方页面确认将此 Chordesk 设备加入网络。若网页显示下载 App，关闭网页后点“继续绑定这台设备”；无需下载安装。"
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
    @Published private(set) var authenticationNotice: String?
#if os(iOS)
    private var authenticationBackgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var authenticationGraceTimer: Task<Void, Never>?
#endif
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
        if value.canAuthorize, value.loginURL != nil, requestLoginPresentation {
            requestLoginPresentation = false; showLogin = true
        }
        if value.shouldCloseAuthentication {
            requestLoginPresentation = false; showLogin = false; authenticationNotice = nil
        }
        switch value.state {
        case "Running": message = value.ready ? "已连接我的 Tailscale 私人网络" : "设备已授权，正在等待私人网络地址…"
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
        guard !ready, snapshot.state != "NeedsMachineAuth" else { refreshStatus(); return }
        // Ask the live node to resume enrollment, rather than reopening a URL
        // saved before an engine restart. The provider manages URL expiry.
        busy = true; requestLoginPresentation = true; authenticationNotice = nil
        let token = generation
        Task {
            let value = await call { CRLogin() }
            guard generation == token else { return }
            busy = false; update(value)
            if value.error != nil { requestLoginPresentation = false }
        }
    }
    func authenticationEnded(couldNotStart: Bool = false) {
        showLogin = false; requestLoginPresentation = false
        authenticationNotice = couldNotStart
            ? "系统认证窗口未能打开，请回到 Chordesk 后重试。"
            : "正在核对本机绑定状态。仅登录网页账号还不代表设备已加入网络。"
        refreshStatus()
    }
    func refreshStatus() {
        guard enabled, !busy else { return }
        let token = generation
        Task {
            let value = await call { CRStatus() }
            guard token == generation, enabled else { return }
            update(value)
            if value.canAuthorize, !showLogin {
#if os(iOS)
                authenticationNotice = "此设备尚未完成绑定。点“继续绑定这台设备”，确认设备名 chordesk-iphone；请使用与 Mac 相同的账号／私人网络。"
#else
                authenticationNotice = "此设备尚未完成绑定。点“继续绑定这台设备”，确认设备名 chordesk-mac；请使用与手机相同的账号／私人网络。"
#endif
            }
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
#if os(iOS)
        endAuthenticationGrace()
#endif
        generation = UUID(); let token = generation
        polling?.cancel(); polling = nil
        enabled = false; busy = true; showLogin = false; requestLoginPresentation = false
        authenticationNotice = nil; snapshot = .init(state: "Stopped")
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
#if os(iOS)
        endAuthenticationGrace()
#endif
        generation = UUID(); let token = generation; polling?.cancel(); polling = nil
        busy = true; showLogin = false; requestLoginPresentation = false
        authenticationNotice = nil; snapshot = .init(state: "Stopped")
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
        guard enabled else { return }
#if os(iOS)
        // A short trip to an identity provider or an OTP app must not immediately
        // destroy the node whose browser authorization is still in progress.
        // Remote input/capture are stopped separately by ContentView as before.
        if snapshot.permitsAuthenticationGrace(browserVisible: showLogin),
           authenticationBackgroundTask == .invalid {
            authenticationBackgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Finish Chordesk enrollment") { [weak self] in
                Task { @MainActor in self?.disconnect(preservePreference: true) }
            }
            if authenticationBackgroundTask != .invalid {
                authenticationGraceTimer = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(20)) } catch { return }
                    self?.disconnect(preservePreference: true)
                }
                return
            }
        }
#endif
        disconnect(preservePreference: true)
    }
    func resumeIfNeeded() {
#if os(iOS)
        endAuthenticationGrace()
#endif
        if enabled { refreshStatus(); return }
        guard shouldResume, !enabled else { return }
        if busy {
            Task { try? await Task.sleep(for: .milliseconds(300)); if !Task.isCancelled { self.resumeIfNeeded() } }
        } else { connect(interactive: false) }
    }
#if os(iOS)
    private func endAuthenticationGrace() {
        authenticationGraceTimer?.cancel(); authenticationGraceTimer = nil
        let task = authenticationBackgroundTask; authenticationBackgroundTask = .invalid
        if task != .invalid { UIApplication.shared.endBackgroundTask(task) }
    }
#endif
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
    @State private var fixtureActions: [String] = []
    @State private var fixtureEnabled = false
    private var interactionFixture: Bool {
#if DEBUG && targetEnvironment(simulator)
        ProcessInfo.processInfo.environment["DUO_UI_FIXTURE"] == "1" &&
        ProcessInfo.processInfo.environment["DUO_UI_TAILNET_TAPS"] == "1"
#else
        false
#endif
    }
    private func invoke(_ action: String, operation: () -> Void) {
        if interactionFixture {
            fixtureActions.append(action)
            if action == "connect" { fixtureEnabled = true }
        } else { operation() }
    }
#if os(iOS)
    @StateObject private var authentication = TailnetAuthenticationController()
#endif
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(tailnet.message, systemImage: tailnet.ready ? "checkmark.shield" : "network")
                .font(.callout).accessibilityIdentifier("tailscale-state")
            if tailnet.ready {
                Text(tailnet.addresses.joined(separator: " · ")).font(.caption.monospaced()).textSelection(.enabled)
            }
            if let diagnostic = tailnet.snapshot.loginDiagnostic { Text(diagnostic).font(.caption).foregroundStyle(.secondary) }
            if let notice = tailnet.authenticationNotice { Text(notice).font(.caption).foregroundStyle(.secondary) }
            if !tailnet.ready, let health = tailnet.snapshot.health, !health.isEmpty {
                Text(health.joined(separator: "\n")).font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                if !tailnet.enabled && !(interactionFixture && fixtureEnabled) {
                    Button("登录／连接 Tailscale") { invoke("connect") { tailnet.connect() } }.disabled(tailnet.busy)
                        .accessibilityIdentifier("tailscale-connect")
                } else {
                    if !tailnet.ready {
                        if tailnet.snapshot.state != "NeedsMachineAuth" {
                            Button("继续绑定这台设备") { invoke("authorize") { tailnet.presentLogin() } }.disabled(tailnet.busy)
                                .accessibilityIdentifier("tailscale-authorize")
                        }
                        Button("检查绑定状态") { invoke("status") { tailnet.refreshStatus() } }.disabled(tailnet.busy)
                            .accessibilityIdentifier("tailscale-check-status")
                    }
                    Button("断开公网") { invoke("disconnect") { tailnet.disconnect() } }.disabled(tailnet.busy)
                        .accessibilityIdentifier("tailscale-disconnect")
                    Button("退出账号", role: .destructive) { invoke("logout-prompt") { confirmLogout = true } }.disabled(tailnet.busy)
                        .accessibilityIdentifier("tailscale-logout")
                }
                if tailnet.busy { ProgressView().controlSize(.small) }
            }
            Text("两端 Chordesk 登录同一 Tailscale 私人网络，无需额外安装 App。仅 Chordesk 的远程连接走此网络；局域网免登录。个人免费计划以 Tailscale 条件为准。")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Link("个人计划", destination: URL(string: "https://tailscale.com/pricing")!)
                    .accessibilityIdentifier("tailscale-plan-link")
                Link("隐私政策", destination: URL(string: "https://tailscale.com/privacy-policy")!)
                    .accessibilityIdentifier("tailscale-privacy-link")
            }.font(.caption)
            if interactionFixture {
                Text(fixtureActions.joined(separator: ",")).accessibilityIdentifier("tailscale-fixture-actions")
            }
        }
        // Embedded in one Form row: .automatic makes every button/link a row
        // action. A physical tap then runs login, disconnect, logout and both
        // external links together. Give each control its own hit target.
        .buttonStyle(.borderless)
        .environment(\.openURL, OpenURLAction { url in
            if interactionFixture { fixtureActions.append("link-" + url.lastPathComponent); return .handled }
            return .systemAction
        })
        .confirmationDialog("退出此设备的 Tailscale 账号？", isPresented: $confirmLogout, titleVisibility: .visible) {
            Button("退出账号", role: .destructive) { tailnet.logout() }
        } message: { Text("公网连接会断开，局域网配对不会删除。再次使用公网需重新登录。") }
#if os(iOS)
        .onChange(of: tailnet.showLogin, initial: true) { _, value in
            if value, tailnet.snapshot.canAuthorize, let url = tailnet.snapshot.loginURL {
                authentication.start(url: url) { failed in tailnet.authenticationEnded(couldNotStart: failed) }
            } else { authentication.cancel() }
        }
        .onDisappear {
            authentication.cancel()
            if tailnet.showLogin { tailnet.authenticationEnded() }
        }
#else
        .onChange(of: tailnet.showLogin, initial: true) { _, value in
            if value, let url = tailnet.snapshot.loginURL { NSWorkspace.shared.open(url); tailnet.showLogin = false }
        }
#endif
    }
}
#if os(iOS)
/// Use Apple's authentication UI. Like Tailscale's official embedded iOS
/// example, the ipnauth callback is only a dismissal signal; CRStatus remains
/// authoritative. Never log URLs, callbacks, cookies, or provider errors.
@MainActor
private final class TailnetAuthenticationController: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?
    private var anchor: UIWindow?
    private var token = UUID()
    private var completion: ((Bool) -> Void)?

    func start(url: URL, completion: @escaping (Bool) -> Void) {
        cancel()
        guard let window = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
            .filter({ $0.activationState != .background && $0.activationState != .unattached })
            .flatMap(\.windows).first(where: \.isKeyWindow) else { completion(true); return }
        anchor = window; self.completion = completion
        let id = token
        let auth = ASWebAuthenticationSession(url: url, callbackURLScheme: "ipnauth",
            completionHandler: Self.callback(for: self, token: id))
        // Retain the user's official login cookies across a retry after a
        // generic onboarding page, rather than requiring account login again.
        auth.prefersEphemeralWebBrowserSession = false
        auth.presentationContextProvider = self
        session = auth
        if !auth.start() { finish(token: id, failed: true) }
    }
    nonisolated private static func callback(for controller: TailnetAuthenticationController, token: UUID) -> @Sendable (URL?, Error?) -> Void {
        { [weak controller] _, _ in
            Task { @MainActor in controller?.finish(token: token, failed: false) }
        }
    }
    private func finish(token id: UUID, failed: Bool) {
        guard id == token else { return }
        let done = completion
        token = UUID(); completion = nil; session = nil; anchor = nil
        done?(failed)
    }
    func cancel() {
        // Invalidate first: a late callback must not dismiss a newer login.
        token = UUID(); completion = nil
        session?.cancel(); session = nil; anchor = nil
    }
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        // start() checks and retains a real window before asking the system.
        anchor ?? ASPresentationAnchor()
    }
}
#endif

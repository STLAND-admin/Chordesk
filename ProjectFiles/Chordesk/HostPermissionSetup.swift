#if os(macOS)
import AppKit
import ApplicationServices
import SwiftUI
import Darwin

struct HostPermissionSnapshot: Equatable, Codable {
    var screen: Bool
    var accessibility: Bool
    var input: Bool
    var ready: Bool { screen && accessibility && input }
    static func current() -> Self {
        .init(screen: CGPreflightScreenCaptureAccess(), accessibility: AXIsProcessTrusted(), input: CGPreflightPostEventAccess())
    }
}

enum HostPermissionState: String, Equatable {
    case notGranted, restartRequired, ready
    var title: String {
        switch self { case .notGranted: "未授权"; case .restartRequired: "已授权 · 需重启 App"; case .ready: "已授权 · 可用" }
    }
    var symbol: String {
        switch self { case .notGranted: "circle"; case .restartRequired: "arrow.clockwise.circle"; case .ready: "checkmark.circle.fill" }
    }
    static func resolve(current: Bool, fresh: Bool?, requestedThisLaunch: Bool) -> Self {
        // A fresh denial can expose a revoked grant still cached by this process.
        if fresh == false { return .notGranted }
        if fresh == true && (!current || requestedThisLaunch) { return .restartRequired }
        if current { return requestedThisLaunch ? .restartRequired : .ready }
        return .notGranted
    }
}

/// One explicit check uses the same signed executable in a fresh process. It
/// only calls public preflight APIs for itself, never reads TCC or asks access.
enum HostPermissionProbe {
    static let argument = "--chordesk-permission-snapshot"
    static func accepts(arguments: [String]) -> Bool { arguments.count == 2 && arguments[1] == argument }
    static func run(arguments: [String]) {
        guard accepts(arguments: arguments), let data = try? JSONEncoder().encode(HostPermissionSnapshot.current()) else { return }
        FileHandle.standardOutput.write(data)
    }
    static func readFresh() async -> HostPermissionSnapshot? {
        guard Bundle.main.bundleURL.pathExtension == "app", let executable = Bundle.main.executableURL else { return nil }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let child = Process(), pipe = Pipe(), done = DispatchSemaphore(value: 0)
                child.executableURL = executable; child.arguments = [argument]
                child.currentDirectoryURL = FileManager.default.temporaryDirectory
                child.standardOutput = pipe; child.standardError = FileHandle.nullDevice
                child.terminationHandler = { _ in done.signal() }
                do { try child.run() } catch { continuation.resume(returning: nil); return }
                guard done.wait(timeout: .now() + 6) == .success else {
                    if child.isRunning { child.terminate() }
                    continuation.resume(returning: nil); return
                }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                guard child.terminationStatus == 0, data.count < 1024 else { continuation.resume(returning: nil); return }
                continuation.resume(returning: try? JSONDecoder().decode(HostPermissionSnapshot.self, from: data))
            }
        }
    }
}

/// A permission request is a user action, never a polling side effect. A new
/// process clears this launch-local restart barrier, including an OS relaunch
/// without custom arguments. Partial permission grants may be restarted safely.
struct ManualPermissionPolicy {
    private(set) var needsRestart = false
    mutating func didRequestPermission() { needsRestart = true }
    func canStart(_ value: HostPermissionSnapshot, busy: Bool) -> Bool {
        value.ready && !needsRestart && !busy
    }
    static func canRestart(busy: Bool) -> Bool { !busy }
}

/// Requesting access may return false without showing another system prompt.
/// Opening Settings is navigation only: it never counts as a grant.
struct ScreenPermissionRequest {
    enum SettingsResult: Equatable { case paneRequested, settingsOpened, unavailable }
    enum Result: Equatable { case granted, needsSettings(SettingsResult) }
    static func perform(request: () -> Bool, isGranted: () -> Bool,
                        openSettings: () -> SettingsResult) -> Result {
        if request() || isGranted() { return .granted }
        return .needsSettings(openSettings())
    }
}

@MainActor
enum HostPrivacySettings {
    static func openScreenCapture(
        open: (URL) -> Bool = { NSWorkspace.shared.open($0) },
        settingsApp: () -> URL? = { NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.systempreferences") }
    ) -> ScreenPermissionRequest.SettingsResult {
        // The pane URL is a best-effort Settings navigation hint, not an
        // authorization API. Keep a plain app launch and readable path fallback.
        let pane = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        if open(pane) { return .paneRequested }
        if let app = settingsApp(), open(app) { return .settingsOpened }
        return .unavailable
    }
}

/// Launch only this bundle after its old process has actually exited. Starting
/// another host before termination can race the listener and embedded node.
enum HostRelaunchHelper {
    static let argument = "--chordesk-wait-and-relaunch"
    static func schedule() throws {
        guard let executable = Bundle.main.executableURL else { throw CocoaError(.fileNoSuchFile) }
        let helper = Process()
        helper.executableURL = executable
        helper.currentDirectoryURL = FileManager.default.temporaryDirectory
        helper.arguments = [argument, String(ProcessInfo.processInfo.processIdentifier)]
        helper.standardOutput = FileHandle.nullDevice
        helper.standardError = FileHandle.nullDevice
        try helper.run()
    }
    static func run(arguments: [String]) {
        guard arguments.count == 3, arguments[1] == argument,
              let parent = Int32(arguments[2]), parent > 1, parent != getpid(),
              Bundle.main.bundleURL.pathExtension == "app" else { return }
        // A failed quit must not create a second host. This process never
        // initializes SwiftUI, Keychain, permission requests, or networking.
        for _ in 0..<60 {
            if kill(parent, 0) != 0 && errno == ESRCH {
                let opener = Process()
                opener.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                opener.currentDirectoryURL = FileManager.default.temporaryDirectory
                opener.arguments = ["-n", "-a", Bundle.main.bundleURL.path, "--args", "--chordesk-permission-relaunch"]
                do { try opener.run(); opener.waitUntilExit() } catch { return }
                return
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
    }
}

/// Returning terminateLater from a main-actor task can keep AppKit's nested
/// termination loop waiting on another task on the same actor. Cancel the first
/// request, finish cleanup on the normal run loop, then request termination once.
@MainActor
final class HostShutdownCoordinator {
    private(set) var prepared = false
    private(set) var task: Task<Void, Never>?
    func request(cleanup: @escaping @MainActor () async -> Void, terminate: @escaping @MainActor () -> Void) -> Bool {
        if prepared { return true }
        guard task == nil else { return false }
        task = Task {
            await cleanup()
            self.prepared = true
            self.task = nil
            DispatchQueue.main.async { terminate() }
        }
        return false
    }
}

@MainActor
final class HostPermissionSetup: ObservableObject {
    @Published private(set) var permissions = HostPermissionSnapshot.current()
    @Published private(set) var message = ""
    @Published private(set) var restarting = false
    @Published private var policy = ManualPermissionPolicy()
    @Published private(set) var freshPermissions: HostPermissionSnapshot?
    @Published private(set) var checking = false
    @Published private var requestedScreen = false
    @Published private var requestedControl = false
    private var probeGeneration = UUID()
    static let resumeServiceKey = "ChordeskStartAfterPermissionSetupV1"
    static let instructions = "分别点击下方两个授权按钮。每项授权完成后，请按 macOS 提示“退出并重新打开”；没有提示时点“重启 Chordesk”。重开后继续另一项，两项均生效后再开启服务。只需重启 App，不需要重启 Mac。"
    private let defaults = UserDefaults.standard
    var screenState: HostPermissionState { .resolve(current: permissions.screen, fresh: freshPermissions?.screen, requestedThisLaunch: requestedScreen) }
    var controlState: HostPermissionState { .resolve(current: permissions.accessibility && permissions.input,
        fresh: freshPermissions.map { $0.accessibility && $0.input }, requestedThisLaunch: requestedControl) }
    var visible: Bool { screenState != .ready || controlState != .ready || policy.needsRestart || restarting || checking }
    var needsRestart: Bool { screenState == .restartRequired || controlState == .restartRequired }
    var primaryTitle: String { visible ? "设置权限" : "开始服务" }

    init() {
        // Old automatic/countdown flags must not schedule a restart or block
        // the new manual flow. The current process is already a fresh launch.
        for key in ["ChordeskPermissionsPendingV1", "ChordeskPermissionRestartAttemptedV1", "ChordeskAutoPermissionRestartV1"] {
            defaults.removeObject(forKey: key)
        }
    }
    func monitor(_ host: LANHost) async {
        await check(host, verifyFresh: true)
        while !Task.isCancelled {
            await check(host)
            do { try await Task.sleep(for: .seconds(2)) } catch { break }
        }
    }
    func check(_ host: LANHost, verifyFresh: Bool = false) async {
        guard !restarting else { return }
        let value = HostPermissionSnapshot.current()
        if value != permissions {
            permissions = value
            freshPermissions = nil
            host.refreshInputPermissions()
            await host.refreshDisplays()
            await host.refreshScaleOptions()
        }
        guard verifyFresh, !checking else { return }
        checking = true
        let token = probeGeneration
        let fresh = await HostPermissionProbe.readFresh()
        guard token == probeGeneration else { checking = false; return }
        freshPermissions = fresh; checking = false
        permissions = .current()
        if fresh == nil {
            message = "新进程只读核验未完成。当前进程状态已刷新；若设置中已开启但仍不可用，请重启 App 后再检查。"
        } else if needsRestart {
            message = permissions.ready
                ? "授权检查已通过；本进程刚请求过权限，请按系统提示重开后使用。无需重复开启系统开关。"
                : "新进程已确认授权，但当前进程尚未生效。请点“重启 Chordesk”，无需重复开启系统开关。"
        } else if screenState == .ready && controlState == .ready {
            message = "两项权限在当前进程与新进程均可用，可以开启服务。"
        } else {
            message = "仍有权限未授权。只读检查不会开启系统权限，请完成对应授权；若系统要求，按提示重开 App。"
            if host.sharing { await host.stopAndRestore() }
        }
    }
    private func busy(_ host: LANHost) -> Bool {
        host.sharing || host.connected || host.scaleBusy || host.switchingDisplay || host.restoreFailed
    }
    func startService(_ host: LANHost) {
        guard !restarting, !checking, !host.pairingCredentialLoading else { return }
        permissions = .current()
        guard screenState == .ready, controlState == .ready, policy.canStart(permissions, busy: busy(host)) else {
            message = policy.needsRestart ? "本次已请求权限。授权后请先重启 Chordesk，再继续设置或开启服务。" : "请先分别完成屏幕录制和控制授权，并按系统提示重启。"
            return
        }
        Task { await host.startDefaultDisplay() }
    }
    func requestScreen(_ host: LANHost) {
        guard beginRequest(host) else { return }
        requestedScreen = true
        message = "正在请求屏幕录制；若系统不再弹窗，将打开对应设置。"
        let result = ScreenPermissionRequest.perform(request: CGRequestScreenCaptureAccess,
            isGranted: CGPreflightScreenCaptureAccess, openSettings: { HostPrivacySettings.openScreenCapture() })
        switch result {
        case .granted:
            message = "屏幕录制已允许。请按系统提示退出并重新打开 Chordesk；没有提示时点重启按钮。"
        case .needsSettings(let navigation):
            let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Chordesk"
            let path = "系统设置 → 隐私与安全 → 录屏与系统录音（部分系统称为屏幕录制）"
            let guidance = "在\(path)中开启“\(name)”，然后按系统提示退出重开。若已开启仍显示待允许，请先重启 App。"
            message = navigation == .unavailable ? "未能打开系统设置，请手动前往。" + guidance : guidance
        }
        Task { await check(host, verifyFresh: true) }
    }
    func requestControl(_ host: LANHost) {
        guard beginRequest(host) else { return }
        requestedControl = true
        message = "第 2 项：允许辅助功能／设备控制后，请按系统提示重启 Chordesk。若没有提示，点下方重启按钮。"
        if !AXIsProcessTrusted() {
            _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        } else if !CGPreflightPostEventAccess() {
            _ = CGRequestPostEventAccess()
        }
        Task { await check(host, verifyFresh: true) }
    }
    private func beginRequest(_ host: LANHost) -> Bool {
        guard !restarting, !checking, !busy(host), !host.pairingCredentialLoading else {
            message = "请先停止服务并完成显示设置恢复，再修改权限。"
            return false
        }
        policy.didRequestPermission()
        probeGeneration = UUID(); freshPermissions = nil
        defaults.set(true, forKey: Self.resumeServiceKey)
        return true
    }
    func restart(_ host: LANHost) async {
        guard !restarting else { return }
        guard ManualPermissionPolicy.canRestart(busy: busy(host)) else {
            message = "请先结束当前共享和显示调整，再重启。"
            return
        }
        guard !Bundle.main.bundlePath.hasPrefix("/Volumes/"), !Bundle.main.bundlePath.contains("/AppTranslocation/") else {
            message = "请先把 Chordesk 拖入“应用程序”并从那里打开，再完成授权。"
            return
        }
        restarting = true
        defaults.synchronize()
        message = "正在释放控制并恢复显示设置…"
        await host.stopAndRestore()
        guard !host.restoreFailed else {
            restarting = false
            message = "原显示设置恢复失败，暂不重启。请先在显示模式区域重试恢复。"
            return
        }
        await EmbeddedTailnet.shared.disconnectAndWait(preservePreference: true)
        do {
            try HostRelaunchHelper.schedule()
            message = "正在重启 Chordesk；重开后检查已生效的权限。"
            DispatchQueue.main.async { NSApplication.shared.terminate(nil) }
        } catch {
            restarting = false
            message = "未能重新打开 Chordesk：\(error.localizedDescription)。可手动退出并重新打开。"
        }
    }
}

struct HostPermissionChecklist: View {
    @ObservedObject var setup: HostPermissionSetup
    @ObservedObject var host: LANHost
    var body: some View {
        GroupBox("首次使用 · 权限检查") {
            VStack(alignment: .leading, spacing: 10) {
                Text(HostPermissionSetup.instructions).font(.callout)
                permission("屏幕与系统音频录制（用于传输画面）", state: setup.screenState)
                permission("控制 Mac（辅助功能／设备控制）", state: setup.controlState)
                HostPermissionActions(setup: setup, host: host)
                Button(setup.checking ? "正在只读核验…" : "重新检查授权状态") { Task { await setup.check(host, verifyFresh: true) } }
                    .disabled(setup.restarting || setup.checking).accessibilityIdentifier("host-check-permissions")
                if !setup.message.isEmpty { Text(setup.message).font(.callout) }
                Text("系统授权由你本人确认。重开后保留已生效的权限，不会自动请求下一项或循环重启。文稿、桌面、下载及完全磁盘访问不属于基础远控所需权限。")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(5)
        }
    }
    private func permission(_ title: String, state: HostPermissionState) -> some View {
        Label("\(title)：\(state.title)", systemImage: state.symbol)
            .foregroundStyle(state == .ready ? Color.green : state == .restartRequired ? Color.orange : Color.secondary)
    }
}

struct HostPermissionActions: View {
    @ObservedObject var setup: HostPermissionSetup
    @ObservedObject var host: LANHost
    private var busy: Bool { setup.restarting || setup.checking || host.sharing || host.connected || host.scaleBusy || host.switchingDisplay || host.restoreFailed || host.pairingCredentialLoading }
    var body: some View {
        VStack(spacing: 8) {
            Button { setup.requestScreen(host) } label: { Label("1 · 允许屏幕录制", systemImage: "record.circle") }
                .disabled(busy || setup.screenState != .notGranted).accessibilityIdentifier("host-request-screen")
            Text("允许屏幕录制后，macOS 可能要求退出并重新打开 Chordesk。请按提示重开，再继续第 2 步。")
                .font(.caption).foregroundStyle(.secondary)
            Button { setup.requestControl(host) } label: { Label("2 · 允许控制 Mac", systemImage: "cursorarrow") }
                .disabled(busy || setup.controlState != .notGranted).accessibilityIdentifier("host-request-control")
            Text("允许控制后，也可能需要重启 Chordesk 才能生效。两项都显示已允许后，再开启服务；不需要重启 Mac。")
                .font(.caption).foregroundStyle(.secondary)
            Button { Task { await setup.restart(host) } } label: { Label("重启 Chordesk", systemImage: "arrow.clockwise") }
                .disabled(busy).accessibilityIdentifier("host-manual-restart")
        }.buttonStyle(.bordered)
    }
}
#endif

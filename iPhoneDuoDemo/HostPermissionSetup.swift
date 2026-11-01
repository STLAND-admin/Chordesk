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
    static let resumeServiceKey = "ChordeskStartAfterPermissionSetupV1"
    static let instructions = "分别点击下方两个授权按钮。每项授权完成后，请按 macOS 提示“退出并重新打开”；没有提示时点“重启 Chordesk”。重开后继续另一项，两项均生效后再开启服务。只需重启 App，不需要重启 Mac。"
    private let defaults = UserDefaults.standard
    var visible: Bool { !permissions.ready || policy.needsRestart || restarting }
    var needsRestart: Bool { policy.needsRestart }
    var primaryTitle: String { visible ? "设置权限" : "开始服务" }

    init() {
        // Old automatic/countdown flags must not schedule a restart or block
        // the new manual flow. The current process is already a fresh launch.
        for key in ["ChordeskPermissionsPendingV1", "ChordeskPermissionRestartAttemptedV1", "ChordeskAutoPermissionRestartV1"] {
            defaults.removeObject(forKey: key)
        }
    }
    func monitor(_ host: LANHost) async {
        while !Task.isCancelled {
            await check(host)
            do { try await Task.sleep(for: .seconds(2)) } catch { break }
        }
    }
    func check(_ host: LANHost) async {
        guard !restarting else { return }
        let value = HostPermissionSnapshot.current()
        if value != permissions {
            permissions = value
            host.refreshInputPermissions()
            await host.refreshDisplays()
            await host.refreshScaleOptions()
        }
        // Deliberately no requests, child-process probes, countdown or relaunch.
        // Cached permission checks are refreshed by the user's next app launch.
    }
    private func busy(_ host: LANHost) -> Bool {
        host.sharing || host.connected || host.scaleBusy || host.switchingDisplay || host.restoreFailed
    }
    func startService(_ host: LANHost) {
        guard !restarting, !host.pairingCredentialLoading else { return }
        permissions = .current()
        guard policy.canStart(permissions, busy: busy(host)) else {
            message = policy.needsRestart ? "本次已请求权限。授权后请先重启 Chordesk，再继续设置或开启服务。" : "请先分别完成屏幕录制和控制授权，并按系统提示重启。"
            return
        }
        Task { await host.startDefaultDisplay() }
    }
    func requestScreen(_ host: LANHost) {
        guard beginRequest(host) else { return }
        message = "第 1 项：允许屏幕录制后，请按系统提示退出并重新打开 Chordesk。重开后继续控制授权。"
        _ = CGRequestScreenCaptureAccess()
        Task { await check(host) }
    }
    func requestControl(_ host: LANHost) {
        guard beginRequest(host) else { return }
        message = "第 2 项：允许辅助功能／设备控制后，请按系统提示重启 Chordesk。若没有提示，点下方重启按钮。"
        if !AXIsProcessTrusted() {
            _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        } else if !CGPreflightPostEventAccess() {
            _ = CGRequestPostEventAccess()
        }
        Task { await check(host) }
    }
    private func beginRequest(_ host: LANHost) -> Bool {
        guard !restarting, !busy(host), !host.pairingCredentialLoading else {
            message = "请先停止服务并完成显示设置恢复，再修改权限。"
            return false
        }
        policy.didRequestPermission()
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
                permission("屏幕与系统音频录制（用于传输画面）", passed: setup.permissions.screen)
                permission("控制 Mac（辅助功能／设备控制）", passed: setup.permissions.accessibility && setup.permissions.input)
                HostPermissionActions(setup: setup, host: host)
                Button("重新检查") { Task { await setup.check(host) } }.disabled(setup.restarting)
                if !setup.message.isEmpty { Text(setup.message).font(.callout) }
                Text("系统授权由你本人确认。重开后保留已生效的权限，不会自动请求下一项或循环重启。文稿、桌面、下载及完全磁盘访问不属于基础远控所需权限。")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(5)
        }
    }
    private func permission(_ title: String, passed: Bool) -> some View {
        Label("\(title)：\(passed ? "已允许" : "待允许／待生效")", systemImage: passed ? "checkmark.circle.fill" : "circle")
            .foregroundStyle(passed ? Color.green : Color.secondary)
    }
}

struct HostPermissionActions: View {
    @ObservedObject var setup: HostPermissionSetup
    @ObservedObject var host: LANHost
    private var busy: Bool { setup.restarting || host.sharing || host.connected || host.scaleBusy || host.switchingDisplay || host.restoreFailed || host.pairingCredentialLoading }
    var body: some View {
        VStack(spacing: 8) {
            Button { setup.requestScreen(host) } label: { Label("1 · 允许屏幕录制", systemImage: "record.circle") }
                .disabled(busy || setup.permissions.screen).accessibilityIdentifier("host-request-screen")
            Button { setup.requestControl(host) } label: { Label("2 · 允许控制 Mac", systemImage: "cursorarrow") }
                .disabled(busy || (setup.permissions.accessibility && setup.permissions.input)).accessibilityIdentifier("host-request-control")
            Button { Task { await setup.restart(host) } } label: { Label("重启 Chordesk", systemImage: "arrow.clockwise") }
                .disabled(busy).accessibilityIdentifier("host-manual-restart")
        }.buttonStyle(.bordered)
    }
}
#endif

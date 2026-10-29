#if os(macOS)
import AppKit
import ApplicationServices
import SwiftUI

struct HostPermissionSnapshot: Equatable, Codable {
    var screen: Bool
    var accessibility: Bool
    var input: Bool
    var ready: Bool { screen && accessibility && input }
    static func current() -> Self {
        .init(screen: CGPreflightScreenCaptureAccess(), accessibility: AXIsProcessTrusted(), input: CGPreflightPostEventAccess())
    }
}

/// Preflight APIs can cache a denial until process restart. Check the same signed
/// executable in a fresh process, without starting SwiftUI, capture, or networking.
/// No TCC database reads and no permission requests occur in this probe.
enum HostPermissionProbe {
    static func printSnapshot() {
        if let data = try? JSONEncoder().encode(HostPermissionSnapshot.current()) {
            FileHandle.standardOutput.write(data)
        }
    }
    static func read(executable: URL) async -> HostPermissionSnapshot? {
        await Task.detached(priority: .utility) {
            let process = Process(), output = Pipe()
            process.executableURL = executable
            process.arguments = ["--chordesk-permission-probe"]
            process.standardOutput = output; process.standardError = FileHandle.nullDevice
            do { try process.run() } catch { return nil }
            for _ in 0..<30 {
                if !process.isRunning { break }
                do { try await Task.sleep(for: .milliseconds(100)) } catch { process.terminate(); return nil }
            }
            guard !process.isRunning else { process.terminate(); return nil }
            guard process.terminationStatus == 0 else { return nil }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            guard data.count < 1024 else { return nil }
            return try? JSONDecoder().decode(HostPermissionSnapshot.self, from: data)
        }.value
    }
}

struct PermissionRestartPolicy {
    var needsRestart: Bool
    var attempted: Bool
    func eligible(_ value: HostPermissionSnapshot, automatic: Bool, sharing: Bool) -> Bool {
        automatic && needsRestart && !attempted && value.ready && !sharing
    }
    mutating func claim() { attempted = true }
}

@MainActor
final class HostPermissionSetup: ObservableObject {
    @Published private(set) var permissions: HostPermissionSnapshot
    @Published private(set) var message = ""
    @Published private(set) var countdown: Int?
    @Published private(set) var restarting = false
    @Published var automatic = UserDefaults.standard.object(forKey: "ChordeskAutoPermissionRestartV1") as? Bool ?? true {
        didSet { UserDefaults.standard.set(automatic, forKey: "ChordeskAutoPermissionRestartV1") }
    }
    private var policy: PermissionRestartPolicy
    private var restartTask: Task<Void, Never>?
    private var checking = false
    private let defaults = UserDefaults.standard
    var visible: Bool { !permissions.ready || policy.needsRestart || restarting }
    init() {
        let current = HostPermissionSnapshot.current()
        permissions = current
        let restarted = CommandLine.arguments.contains("--chordesk-permission-relaunch")
        let pending = UserDefaults.standard.bool(forKey: "ChordeskPermissionsPendingV1")
        let attempted = restarted || UserDefaults.standard.bool(forKey: "ChordeskPermissionRestartAttemptedV1")
        policy = .init(needsRestart: !current.ready || (pending && !attempted), attempted: attempted)
        if current.ready && attempted { UserDefaults.standard.set(false, forKey: "ChordeskPermissionsPendingV1") }
        if !current.ready && restarted { message = "重启后仍有权限未通过。请核对系统设置里授权的是当前 Chordesk；不会循环重启。" }
    }
    func monitor(_ host: LANHost) async {
        while !Task.isCancelled {
            await check(host)
            do { try await Task.sleep(for: .seconds(2)) } catch { break }
        }
        restartTask?.cancel(); restartTask = nil
    }
    private func refreshedSnapshot() async -> HostPermissionSnapshot {
        let current = HostPermissionSnapshot.current()
        guard !current.ready, policy.needsRestart, !policy.attempted,
              defaults.bool(forKey: "ChordeskPermissionsPendingV1"),
              let executable = Bundle.main.executableURL else { return current }
        return await HostPermissionProbe.read(executable: executable) ?? current
    }
    func check(_ host: LANHost) async {
        guard !checking, !restarting else { return }
        checking = true
        defer { checking = false }
        let value = await refreshedSnapshot()
        if value != permissions {
            permissions = value
            host.refreshInputPermissions()
            Task { await host.refreshDisplays(); await host.refreshScaleOptions() }
        }
        guard !restarting else { return }
        if policy.eligible(value, automatic: automatic, sharing: host.sharing || host.connected || host.scaleBusy || host.switchingDisplay || host.restoreFailed) {
            guard restartTask == nil else { return }
            message = "权限已通过；将自动重启 Chordesk 使权限完整生效。"
            restartTask = Task { [weak self, weak host] in
                guard let self, let host else { return }
                defer { self.restartTask = nil; self.countdown = nil }
                for remaining in (1...3).reversed() {
                    guard self.policy.eligible(await self.refreshedSnapshot(), automatic: self.automatic, sharing: host.sharing || host.connected || host.scaleBusy || host.switchingDisplay || host.restoreFailed) else { return }
                    self.countdown = remaining
                    do { try await Task.sleep(for: .seconds(1)) } catch { return }
                }
                // Permissions or activity can change during the final sleep.
                guard self.policy.eligible(await self.refreshedSnapshot(), automatic: self.automatic, sharing: host.sharing || host.connected || host.scaleBusy || host.switchingDisplay || host.restoreFailed) else { return }
                await self.restart(host)
            }
        } else if value.ready && policy.needsRestart && (host.sharing || host.connected) {
            message = "权限已通过。结束共享后自动重启，避免中断当前远控。"
        }
    }
    func requestScreen(_ host: LANHost) {
        beginRequest()
        Task { await host.refreshDisplays(requestPermission: true); await check(host) }
    }
    func requestControl(_ host: LANHost) {
        beginRequest()
        _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        if AXIsProcessTrusted() && !CGPreflightPostEventAccess() { _ = CGRequestPostEventAccess() }
        Task { await check(host) }
    }
    private func beginRequest() {
        policy.needsRestart = true; policy.attempted = false
        defaults.set(true, forKey: "ChordeskPermissionsPendingV1")
        defaults.set(false, forKey: "ChordeskPermissionRestartAttemptedV1")
        message = "请在 macOS 系统提示中授权；返回后自动检查。密码／Touch ID 由你本人完成。"
    }
    func postpone() {
        automatic = false; restartTask?.cancel(); restartTask = nil; countdown = nil
        message = "自动重启已关闭，可在方便时手动重启。"
    }
    func restart(_ host: LANHost) async {
        guard !restarting else { return }
        guard !Bundle.main.bundlePath.hasPrefix("/Volumes/"), !Bundle.main.bundlePath.contains("/AppTranslocation/") else {
            automatic = false
            message = "请先把 Chordesk 拖入“应用程序”并从那里打开，再完成授权。"
            return
        }
        restarting = true; policy.claim()
        defaults.set(true, forKey: "ChordeskPermissionRestartAttemptedV1")
        defaults.set(true, forKey: "ChordeskPermissionsPendingV1")
        defaults.synchronize()
        message = "正在释放控制并恢复显示设置…"
        await host.stopAndRestore()
        guard !host.restoreFailed else {
            restarting = false; automatic = false
            message = "原显示设置恢复失败，暂不重启。请先在显示模式区域重试恢复。"
            return
        }
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        config.allowsRunningApplicationSubstitution = false
        config.arguments = ["--chordesk-permission-relaunch"]
        do {
            _ = try await NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: config)
            NSApplication.shared.terminate(nil)
        } catch {
            restarting = false; automatic = false
            message = "未能重新打开 Chordesk：\(error.localizedDescription)。当前窗口保留，可手动退出重开。"
        }
    }
}

struct HostPermissionChecklist: View {
    @ObservedObject var setup: HostPermissionSetup
    @ObservedObject var host: LANHost
    var body: some View {
        GroupBox("首次使用 · 权限检查") {
            VStack(alignment: .leading, spacing: 10) {
                Text("首次开启需要两项系统权限。依次授权后，Chordesk 会检查并重启一次，再开启内置屏服务。无需重启 Mac。")
                    .font(.callout)
                permission("屏幕与系统音频录制（用于传输画面）", passed: setup.permissions.screen)
                permission("控制 Mac（辅助功能／设备控制）", passed: setup.permissions.accessibility && setup.permissions.input)
                HStack {
                    Button("允许屏幕录制") { setup.requestScreen(host) }.disabled(setup.permissions.screen || setup.restarting)
                    Button("允许控制") { setup.requestControl(host) }.disabled((setup.permissions.accessibility && setup.permissions.input) || setup.restarting)
                    Button("重新检查") { Task { await setup.check(host) } }.disabled(setup.restarting)
                }
                Toggle("授权完整后自动重启 Chordesk", isOn: $setup.automatic)
                if let countdown = setup.countdown {
                    HStack { Text("\(countdown) 秒后重启 App"); Button("稍后") { setup.postpone() } }
                }
                if !setup.message.isEmpty { Text(setup.message).font(.callout) }
                Text("这里只检查权限，不能代替你在系统里确认。若系统已允许但检查尚未更新，可重启后再检查；不会重启 Mac 或循环重启。启用“启动后自动开启服务”时，权限通过并重启后共享内置屏。")
                    .font(.caption).foregroundStyle(.secondary)
                Button("已完成授权，重启 Chordesk 并检查") { Task { await setup.restart(host) } }
                    .disabled(setup.restarting || host.sharing || host.connected || host.scaleBusy || host.switchingDisplay || host.restoreFailed)
            }.padding(5)
        }
    }
    private func permission(_ title: String, passed: Bool) -> some View {
        Label("\(title)：\(passed ? "已允许" : "待允许／待生效")", systemImage: passed ? "checkmark.circle.fill" : "circle")
            .foregroundStyle(passed ? Color.green : Color.secondary)
    }
}
#endif

#if os(macOS)
import AppKit
import SwiftUI
import Darwin

enum MacUninstallMode: String, CaseIterable, Identifiable {
    case appOnly = "app-only", full = "full"
    var id: String { rawValue }
    var title: String { self == .appOnly ? "仅卸载 App，保留数据与授权" : "完整卸载，清除本机授权、配对与公网登录" }
    var confirmationInput: String { self == .appOnly ? "4\nUNINSTALL\n" : "5\nREMOVE\n" }
}

enum MacUninstallHelper {
    static let argument = "--chordesk-uninstall-helper"
    static func mode(arguments: [String], bundleID: String?) -> MacUninstallMode? {
        guard ChordeskMaintenanceScope.permits(bundleID), arguments.count == 4,
              arguments[1] == argument, let pid = Int32(arguments[2]), pid > 1 else { return nil }
        return MacUninstallMode(rawValue: arguments[3])
    }
    static func isStandardInstallation(_ url: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Bool {
        [URL(fileURLWithPath: "/Applications/Chordesk.app"), home.appendingPathComponent("Applications/Chordesk.app")]
            .contains(url.standardizedFileURL)
    }

    /// Reuse the sealed maintenance backend after an explicit native GUI
    /// confirmation. No arbitrary script, target, permission or Keychain names
    /// can arrive from the remote protocol. A PTY preserves its terminal guard.
    static func runBackend(script: URL, mode: MacUninstallMode) throws -> (Int32, String) {
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("Chordesk-uninstall-\(UUID()).log")
        FileManager.default.createFile(atPath: outputURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
        defer { try? FileManager.default.removeItem(at: outputURL) }
        let output = try FileHandle(forWritingTo: outputURL), input = Pipe(), child = Process()
        defer { try? output.close(); try? input.fileHandleForWriting.close() }
        child.executableURL = URL(fileURLWithPath: "/usr/bin/script")
        child.arguments = ["-q", "/dev/null", "/bin/zsh", script.path]
        child.currentDirectoryURL = FileManager.default.temporaryDirectory
        child.standardInput = input; child.standardOutput = output; child.standardError = output
        try child.run()
        var confirmed = false
        let deadline = Date().addingTimeInterval(90)
        while child.isRunning && Date() < deadline {
            let data = (try? Data(contentsOf: outputURL)) ?? Data()
            if !confirmed && String(decoding: data.prefix(16_384), as: UTF8.self).contains("选择：") {
                try input.fileHandleForWriting.write(contentsOf: Data(mode.confirmationInput.utf8))
                confirmed = true
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        if child.isRunning { child.terminate(); throw CocoaError(.userCancelled) }
        child.waitUntilExit()
        let data = (try? Data(contentsOf: outputURL)) ?? Data()
        return (confirmed ? child.terminationStatus : 2, String(decoding: data.suffix(8_192), as: UTF8.self))
    }

    @MainActor
    static func schedule(_ mode: MacUninstallMode) async throws {
        guard ChordeskMaintenanceScope.supported, isStandardInstallation(Bundle.main.bundleURL),
              let executable = Bundle.main.executableURL else { throw CocoaError(.featureUnsupported) }
        // A temporary, identically signed copy can finish after the installed
        // host exits, without counting itself as a still-running host.
        let directory = URL(fileURLWithPath: "/private/tmp/ChordeskUninstaller.\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let copy = directory.appendingPathComponent("ChordeskUninstaller.app")
        do {
            try FileManager.default.copyItem(at: Bundle.main.bundleURL, to: copy)
            let child = Process(), ready = Pipe()
            child.executableURL = copy.appendingPathComponent("Contents/MacOS/" + executable.lastPathComponent)
            child.arguments = [argument, String(getpid()), mode.rawValue]
            child.currentDirectoryURL = directory
            child.standardOutput = ready; child.standardError = FileHandle.nullDevice
            try child.run()
            let acknowledged = await Task.detached {
                let data = ready.fileHandleForReading.readData(ofLength: 6)
                return data == Data("READY\n".utf8)
            }.value
            guard acknowledged else { throw CocoaError(.executableLoad) }
        } catch { try? FileManager.default.removeItem(at: directory); throw error }
    }

    @MainActor
    static func run(arguments: [String]) {
        guard let mode = mode(arguments: arguments, bundleID: Bundle.main.bundleIdentifier),
              let parent = Int32(arguments[2]), parent == getppid(),
              let running = NSRunningApplication(processIdentifier: parent),
              running.bundleIdentifier == ChordeskMaintenanceScope.bundleID,
              let source = running.bundleURL, isStandardInstallation(source),
              Bundle.main.bundleURL.lastPathComponent == "ChordeskUninstaller.app",
              Bundle.main.bundleURL.deletingLastPathComponent().path.hasPrefix("/private/tmp/ChordeskUninstaller."),
              let script = Bundle.main.url(forResource: "Chordesk-Maintenance", withExtension: "command") else { return }
        let directory = Bundle.main.bundleURL.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: directory) }
        FileHandle.standardOutput.write(Data("READY\n".utf8))
        for _ in 0..<300 {
            if kill(parent, 0) != 0 && errno == ESRCH {
                let result: (Int32, String)
                do { result = try runBackend(script: script, mode: mode) }
                catch { result = (1, "卸载未完成：" + error.localizedDescription) }
                let app = NSApplication.shared
                app.setActivationPolicy(.accessory); app.activate()
                let alert = NSAlert()
                alert.messageText = result.0 == 0 ? "Chordesk 已卸载" : "Chordesk 卸载未完成"
                alert.informativeText = result.0 == 0
                    ? "App 已移入废纸篓。" + (mode == .full ? "本机 Chordesk 的授权、配对、登录与偏好已清理。Tailscale 管理页中的旧节点可自行移除。" : "配对、登录、偏好与授权已保留。")
                    : "部分步骤可能已完成；不会宣称完整清理。请保留以下结果以便排查：\n" + result.1
                alert.runModal()
                return
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        // If the normal host did not finish quitting, never remove its files.
    }
}

struct HostUninstallSheet: View {
    @ObservedObject var host: LANHost
    let prepare: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var mode = MacUninstallMode.appOnly
    @State private var busy = false
    @State private var error = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("卸载 Chordesk", systemImage: "trash").font(.title2)
            Picker("清理范围", selection: $mode) {
                ForEach(MacUninstallMode.allCases) { Text($0.title).tag($0) }
            }.pickerStyle(.radioGroup)
            Text("先停止远控并恢复显示模式，再退出并卸载。App 与本地文件移入废纸篓；完整卸载删除的登录密钥和系统授权需要重新设置。不会卸载其他软件或重置整个钥匙串。")
                .font(.callout).foregroundStyle(.secondary)
            if !error.isEmpty { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            if busy { ProgressView("正在停止服务并准备卸载…") }
            HStack {
                Spacer()
                Button("取消", role: .cancel) { dismiss() }.disabled(busy)
                Button("卸载并退出", role: .destructive) { uninstall() }.disabled(busy)
            }
        }.padding().fixedSize(horizontal: false, vertical: true)
    }
    private func uninstall() {
        busy = true
        prepare()
        Task {
            await host.stopAndRestore()
            guard !host.restoreFailed else { error = "请先恢复原显示模式，再卸载。"; busy = false; return }
            await EmbeddedTailnet.shared.disconnectAndWait(preservePreference: true)
            do { try await MacUninstallHelper.schedule(mode); NSApp.terminate(nil) }
            catch { self.error = "未开始卸载：" + error.localizedDescription + "。请从 Applications 中打开正式版。"; busy = false }
        }
    }
}
#endif

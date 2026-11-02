#if os(macOS)
import AppKit
import Foundation
import Security
import SwiftUI

/// These identifiers are intentionally fixed. A remote packet, path or user
/// input must never select another app's credentials or privacy permissions.
enum ChordeskMaintenanceScope {
    static let bundleID = "dev.iphoneduo.workbench"
    static let tailnetService = "dev.chordesk.embedded-tailnet"
    static let tailnetAccount = "node-state-v1"
    static func permits(_ identifier: String?) -> Bool { identifier == bundleID }
    static var supported: Bool { permits(Bundle.main.bundleIdentifier) }
    static func permissionArguments(bundleID: String?) -> [String]? {
        permits(bundleID) ? ["reset", "All", Self.bundleID] : nil
    }
    static var tailnetQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: tailnetService,
         kSecAttrAccount as String: tailnetAccount,
         kSecAttrSynchronizable as String: false]
    }
}

struct MacKeychainFailure: Equatable {
    let status: OSStatus
    static func parse(_ error: String?) -> Self? {
        guard let error, let regex = try? NSRegularExpression(pattern: #"^Keychain (?:read|write|delete) failed \((-?[0-9]+)\)$"#),
              let match = regex.firstMatch(in: error, range: NSRange(error.startIndex..., in: error)),
              let range = Range(match.range(at: 1), in: error), let code = Int32(error[range]) else { return nil }
        return .init(status: code)
    }
    var canAuthorize: Bool { [errSecAuthFailed, errSecInteractionNotAllowed, errSecNotAvailable, errSecUserCanceled].contains(status) }
    var message: String { "无法访问本机公网登录记录（钥匙串 \(status)）" }
    var explanation: String {
        "升级后的签名、钥匙串锁定或访问许可变化都可能导致此错误。先授权钥匙串并重试；如系统提供“始终允许”，请确认请求来自 Chordesk 后选择该项，单次允许可能无法保留到主进程。仍失败可重新绑定本机公网身份。屏幕录制／控制权限与此独立。"
    }
}

struct MacKeychainAuthorizationReply: Codable, Equatable {
    var status: OSStatus
    var canRetry: Bool { status == errSecSuccess || status == errSecItemNotFound }
}

/// This fresh process reads exactly one item after a local button press. It
/// neither starts a node nor returns any credential bytes. Do not temporarily
/// enable process-global dialogs in the host: its other Keychain work can race.
enum MacKeychainAuthorizationHelper {
    static let argument = "--chordesk-authorize-tailnet-keychain"
    static func accepts(arguments: [String], bundleID: String?) -> Bool {
        arguments.count == 2 && arguments[1] == argument && ChordeskMaintenanceScope.permits(bundleID)
    }
    static func run(arguments: [String]) {
        var status = errSecParam
        if accepts(arguments: arguments, bundleID: Bundle.main.bundleIdentifier) {
            status = SecKeychainSetUserInteractionAllowed(true)
            if status == errSecSuccess {
                var query = ChordeskMaintenanceScope.tailnetQuery
                query[kSecReturnData as String] = true
                query[kSecMatchLimit as String] = kSecMatchLimitOne
                var value: CFTypeRef?
                status = SecItemCopyMatching(query as CFDictionary, &value)
                value = nil // Never serialize the secret, even on success.
            }
        }
        if let data = try? JSONEncoder().encode(MacKeychainAuthorizationReply(status: status)) {
            FileHandle.standardOutput.write(data)
        }
    }
    static func authorize() async -> MacKeychainAuthorizationReply {
        guard ChordeskMaintenanceScope.supported, let executable = Bundle.main.executableURL else {
            return .init(status: errSecParam)
        }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let child = Process(), output = Pipe(), completed = DispatchSemaphore(value: 0)
                child.executableURL = executable
                child.arguments = [argument]
                child.currentDirectoryURL = FileManager.default.temporaryDirectory
                child.standardOutput = output; child.standardError = FileHandle.nullDevice
                child.terminationHandler = { _ in completed.signal() }
                do { try child.run() } catch {
                    continuation.resume(returning: .init(status: errSecNotAvailable)); return
                }
                guard completed.wait(timeout: .now() + 90) == .success else {
                    child.terminate()
                    continuation.resume(returning: .init(status: errSecUserCanceled)); return
                }
                let data = output.fileHandleForReading.readDataToEndOfFile()
                let reply = (try? JSONDecoder().decode(MacKeychainAuthorizationReply.self, from: data))
                    ?? .init(status: errSecNotAvailable)
                continuation.resume(returning: reply)
            }
        }
    }
    /// Destructive removal is called only after the in-app confirmation and a
    /// completed CRStop. No fallback service, namespace or unencrypted store.
    static func removeLocalTailnetIdentity() async -> OSStatus {
        guard ChordeskMaintenanceScope.supported else { return errSecParam }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: SecItemDelete(ChordeskMaintenanceScope.tailnetQuery as CFDictionary))
            }
        }
    }
}

enum MacPermissionReset {
    static func run() async -> Bool {
        guard let arguments = ChordeskMaintenanceScope.permissionArguments(bundleID: Bundle.main.bundleIdentifier) else { return false }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let child = Process(), completed = DispatchSemaphore(value: 0)
                child.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
                child.arguments = arguments
                child.currentDirectoryURL = FileManager.default.temporaryDirectory
                child.standardOutput = FileHandle.nullDevice; child.standardError = FileHandle.nullDevice
                child.terminationHandler = { _ in completed.signal() }
                do { try child.run() } catch { continuation.resume(returning: false); return }
                guard completed.wait(timeout: .now() + 20) == .success else {
                    child.terminate(); continuation.resume(returning: false); return
                }
                continuation.resume(returning: child.terminationReason == .exit && child.terminationStatus == 0)
            }
        }
    }
}

struct HostMaintenancePanel: View {
    @ObservedObject var host: LANHost
    @State private var confirmPermissions = false
    @State private var busy = false
    @State private var message = ""
    var body: some View {
        DisclosureGroup("维护与卸载") {
            Text("升级请先退出旧版，再在同一 Applications 位置替换 App。临时签名试用版的身份会随构建变化；固定 Developer ID 签名有助于后续版本沿用授权，系统仍决定是否需要重新确认。")
                .font(.caption).foregroundStyle(.secondary)
            Button("重置 Chordesk 系统授权并重启…") { confirmPermissions = true }
                .disabled(busy || !ChordeskMaintenanceScope.supported)
                .accessibilityIdentifier("host-repair-permissions")
            Text("仅在旧授权开着、新版仍无法控制时使用。会清除本 App 的权限决定，重新逐项授权；它不修复公网钥匙串。")
                .font(.caption).foregroundStyle(.secondary)
            Button("保存卸载与维护工具…") { saveTool() }
                .disabled(busy).accessibilityIdentifier("host-export-maintenance")
            Text("工具可检查安装、重置本 App 权限、重新绑定公网，或将 App 移入废纸篓。保留数据／彻底卸载分别确认；使用前请正常退出 Chordesk。")
                .font(.caption).foregroundStyle(.secondary)
            if busy { ProgressView() }
            if !message.isEmpty { Text(message).font(.callout).textSelection(.enabled) }
        }
        .confirmationDialog("重置本 App 的系统授权并重启？", isPresented: $confirmPermissions, titleVisibility: .visible) {
            Button("停止服务、重置并重启", role: .destructive) { resetPermissions() }
        } message: {
            Text("正在进行的远控将断开，显示模式先恢复。屏幕录制、控制及可选桌面切换权限需重新允许。配对和公网登录保留。")
        }
    }
    private func resetPermissions() {
        busy = true
        Task {
            await host.stopAndRestore()
            guard !host.restoreFailed else { message = "请先在设置中恢复原显示模式，再重置授权。"; busy = false; return }
            await EmbeddedTailnet.shared.disconnectAndWait(preservePreference: true)
            guard await MacPermissionReset.run() else {
                message = "系统未完成重置。服务已停止，请在系统隐私设置中手动移除旧 Chordesk 条目后重新添加。"; busy = false; return
            }
            do {
                try HostRelaunchHelper.schedule()
                NSApp.terminate(nil)
            } catch { message = "授权已重置，请手动退出并重新打开 Chordesk。"; busy = false }
        }
    }
    private func saveTool() {
        guard let source = Bundle.main.url(forResource: "Chordesk-Maintenance", withExtension: "command") else {
            message = "当前构建未包含维护工具，请从 Chordesk GitHub 仓库获取。"; return
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Chordesk-Maintenance.command"
        panel.message = "保存项目提供的维护工具；先退出 Chordesk，再运行并选择操作。"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        guard !destination.standardizedFileURL.path.hasPrefix(Bundle.main.bundleURL.standardizedFileURL.path + "/") else {
            message = "请选择 App 安装包以外的保存位置。"; return
        }
        do {
            try Data(contentsOf: source).write(to: destination, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.path)
            message = "工具已保存。先退出 Chordesk，再打开工具；选择操作后还需输入确认词。"
            NSWorkspace.shared.activateFileViewerSelecting([destination])
        } catch { message = "保存失败：" + error.localizedDescription }
    }
}
#endif

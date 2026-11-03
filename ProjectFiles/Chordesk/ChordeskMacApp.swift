#if os(macOS)
import SwiftUI

@MainActor
final class ChordeskHostLifecycle: NSObject, NSApplicationDelegate {
    weak var host: LANHost?
    var reopenWindow: (() -> Void)?
    private var monitorTask: Task<Void, Never>?
    private var startupTask: Task<Void, Never>?
    private let shutdown = HostShutdownCoordinator()
    private var maintenanceCleanupFinished = false
    func pauseAutomaticTasks() { monitorTask?.cancel(); startupTask?.cancel() }
    func exitAfterMaintenance() {
        // The uninstall flow has already stopped/restored the host and node.
        // Do not start the same asynchronous cleanup again during termination.
        maintenanceCleanupFinished = true
        DispatchQueue.main.async { NSApp.terminate(nil) }
    }
    func attach(_ host: LANHost, setup: HostPermissionSetup) {
        self.host = host
        guard monitorTask == nil else { return }
        if host.allowsTailscale { EmbeddedTailnet.shared.resumeIfNeeded() }
        monitorTask = Task { await setup.monitor(host) }
        startupTask = Task {
            while !Task.isCancelled {
                if !host.pairingCredentialLoading && !setup.visible && !host.scaleBusy && !host.restoreFailed {
                    let requested = UserDefaults.standard.bool(forKey: HostPermissionSetup.resumeServiceKey)
                    UserDefaults.standard.set(false, forKey: HostPermissionSetup.resumeServiceKey)
                    if host.autoStartHost || requested { await host.startDefaultDisplay() }
                    return
                }
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
            }
        }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { reopenWindow?() }; return true
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        monitorTask?.cancel(); startupTask?.cancel()
        if maintenanceCleanupFinished { return .terminateNow }
        guard let host else { return .terminateNow }
        let ready = shutdown.request(cleanup: {
            await host.stopAndRestore()
            await EmbeddedTailnet.shared.disconnectAndWait(preservePreference: true)
        }, terminate: { sender.terminate(nil) })
        return ready ? .terminateNow : .terminateCancel
    }
}

private struct HostMenuBar: View {
    @ObservedObject var host: LANHost
    @ObservedObject var setup: HostPermissionSetup
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Text(host.sharing ? (host.connected ? "已连接 · " + host.clientName : "等待已配对设备") : "服务已停止")
        Button("打开 Chordesk") { openWindow(id: "lan-host"); NSApp.activate() }
        if host.sharing { Button("停止服务") { host.stop() } }
        else { Button("开始内置屏服务") {
            if setup.visible { openWindow(id: "lan-host"); NSApp.activate() }
            setup.startService(host)
        }.disabled(setup.restarting) }
        Divider()
        Button("退出 Chordesk") { NSApp.terminate(nil) }
    }
}

private struct HostScene: View {
    @ObservedObject var host: LANHost
    @ObservedObject var setup: HostPermissionSetup
    let lifecycle: ChordeskHostLifecycle
    @Binding var showingUninstall: Bool
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        LANHostView(host: host, permissionSetup: setup).onAppear {
            lifecycle.reopenWindow = { openWindow(id: "lan-host") }
            lifecycle.attach(host, setup: setup)
        }.sheet(isPresented: $showingUninstall) {
            HostUninstallSheet(host: host, prepare: lifecycle.pauseAutomaticTasks, finish: lifecycle.exitAfterMaintenance)
        }
    }
}

@main
enum ChordeskEntry {
    static func main() {
        if [MacUninstallHelper.argument, MacUninstallHelper.probeArgument].contains(CommandLine.arguments.dropFirst().first ?? "") {
            MacUninstallHelper.run(arguments: CommandLine.arguments)
            return
        }
        if CommandLine.arguments.dropFirst().first == HostPermissionProbe.argument {
            HostPermissionProbe.run(arguments: CommandLine.arguments)
            return
        }
        if CommandLine.arguments.dropFirst().first == MacKeychainAuthorizationHelper.argument {
            MacKeychainAuthorizationHelper.run(arguments: CommandLine.arguments)
            return
        }
        if CommandLine.arguments.dropFirst().first == HostRelaunchHelper.argument {
            HostRelaunchHelper.run(arguments: CommandLine.arguments)
            return
        }
        ChordeskMacApp.main()
    }
}

struct ChordeskMacApp: App {
    @NSApplicationDelegateAdaptor(ChordeskHostLifecycle.self) private var lifecycle
    @StateObject private var host = LANHost()
    @StateObject private var setup = HostPermissionSetup()
    @State private var showingUninstall = false
    @Environment(\.openWindow) private var openWindow
    var body: some Scene {
        Window("Chordesk · Mac 主机", id: "lan-host") {
            HostScene(host: host, setup: setup, lifecycle: lifecycle, showingUninstall: $showingUninstall)
        }.defaultSize(width: 540, height: 650)
        .commands {
            CommandGroup(after: .help) {
                Button { openWindow(id: "lan-host"); NSApp.activate(); showingUninstall = true } label: {
                    Label("卸载 Chordesk…", systemImage: "trash")
                }.disabled(!ChordeskMaintenanceScope.supported)
            }
        }
        MenuBarExtra("Chordesk", systemImage: "rectangle.on.rectangle") { HostMenuBar(host: host, setup: setup) }
    }
}
#endif

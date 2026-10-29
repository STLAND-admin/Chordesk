#if os(macOS)
import SwiftUI

enum OuterEdge: String, CaseIterable, Identifiable {
    case right = "右侧"
    case bottom = "下方"
    case left = "左侧"
    case top = "上方"
    var id: String { rawValue }
    var horizontal: Bool { self == .right || self == .left }
}

struct WorkbenchView: View {
    @ObservedObject var host: LANHost
    @Environment(\.openWindow) private var openWindow
    @StateObject private var session = DemoSession()
    @StateObject private var capture = WorkbenchCapture()
    @StateObject private var remote = WindowRemoteSession()
    @State private var edge: OuterEdge = .right
    @State private var showingLog = false

    var body: some View {
        VStack(spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("把屏幕留给内容").font(.title2.weight(.semibold))
                    Text("内屏：Monitor ¾ + 触摸键盘 ¼　·　外屏：独立触控板").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Label(capture.isActive ? "已接管触控板 · Esc 返回 Mac" : "按 P 接管触控板", systemImage: capture.isActive ? "cursorarrow.motionlines" : "cursorarrow")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(capture.isActive ? Color.teal : .secondary)
            }

            GeometryReader { geometry in
                let gap: CGFloat = 14
                let side = max(1, min(edge.horizontal ? (geometry.size.width - gap) / 1.5 : geometry.size.width,
                                      edge.horizontal ? geometry.size.height : (geometry.size.height - gap) / 1.5))
                Group {
                    if edge.horizontal {
                        HStack(spacing: gap) {
                            if edge == .left { outerDisplay.frame(width: side * 0.5, height: side) }
                            innerDisplay.frame(width: side, height: side)
                            if edge == .right { outerDisplay.frame(width: side * 0.5, height: side) }
                        }
                    } else {
                        VStack(spacing: gap) {
                            if edge == .top { outerDisplay.frame(width: side, height: side * 0.5) }
                            innerDisplay.frame(width: side, height: side)
                            if edge == .bottom { outerDisplay.frame(width: side, height: side * 0.5) }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            HStack {
                Label(remote.hasSelection ? remote.status : session.status, systemImage: remote.hasSelection ? "macwindow" : "cursorarrow")
                    .lineLimit(2)
                Spacer()
                Text(remote.hasSelection ? "P 控制所选窗口 · 双指滚动 · Esc / 切换桌面退出" : capture.isActive ? "直接滑动＝移动光标　·　双指＝滚动　·　三指上滑展开 / 下滑还原　·　Esc 退出" : "按 P 接管；双指滚动，三指上滑展开 / 下滑还原文稿")
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
        }
        .padding()
        .foregroundStyle(Color(red: 0.18, green: 0.23, blue: 0.22))
        .background(Color(red: 0.92, green: 0.93, blue: 0.92))
        .background(CaptureWindowReader(controller: capture))
        .onAppear { remote.invalidateInput = { [weak controller = capture] in controller?.stop() } }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in remote.refreshPermission() }
        .onChange(of: remote.status) { _, value in if !remote.hasSelection { session.record(value) } }
        .onDisappear { capture.stop(); remote.disconnect() }
        .toolbar {
            ToolbarItem {
                Button { capture.stop(); remote.disconnect(); openWindow(id: "lan-host") } label: {
                    Label("局域网远控", systemImage: "network").labelStyle(.titleAndIcon)
                }
                .accessibilityIdentifier("open-lan-host")
            }
            ToolbarItem {
                Menu {
                    Button { capture.stop(); remote.chooseWindow() } label: { Label("选择真实窗口", systemImage: "macwindow.badge.plus") }
                    Button { capture.stop(); remote.openTestDocument() } label: { Label("新建 TextEdit 测试文稿", systemImage: "doc.badge.plus") }
                    if remote.hasSelection {
                        Button { capture.stop(); remote.disconnect() } label: { Label("返回本地模拟", systemImage: "rectangle.on.rectangle") }
                    }
                } label: { Label("真实窗口实验", systemImage: "macwindow").labelStyle(.titleAndIcon) }
                .accessibilityLabel("真实窗口实验")
                .help("选择单个真实窗口进行本机实验；不是整个 Mission Control 桌面")
                .disabled(host.sharing)
            }
            ToolbarItem {
                Button {
                    if capture.isActive { capture.stop() } else { capture.start(session: session, remote: remote.hasSelection ? remote : nil) }
                } label: {
                    Label(capture.isActive ? "退出接管 · Esc" : "接管触控板 · P", systemImage: "cursorarrow.motionlines")
                }
                .keyboardShortcut("p", modifiers: [])
                .disabled(remote.isStarting)
            }
            ToolbarItem {
                Picker("外屏位置", selection: $edge) {
                    ForEach(OuterEdge.allCases) { value in Text(value.rawValue).tag(value) }
                }
                .pickerStyle(.segmented)
                .help("按握持方向选择外屏贴靠的边；不会检测设备折叠状态")
            }
            ToolbarItem {
                Button { session.reset() } label: { Label("重置", systemImage: "arrow.counterclockwise") }
                    .disabled(remote.hasSelection)
            }
            ToolbarItem {
                Button { session.setWindowExpanded(!session.windowExpanded) } label: {
                    Label(session.windowExpanded ? "还原文稿" : "展开文稿", systemImage: "arrow.up.left.and.arrow.down.right")
                }
                .disabled(remote.hasSelection)
            }
            ToolbarItem {
                Button { showingLog = true } label: { Label("交互记录", systemImage: "list.bullet.rectangle") }
            }
        }
        .sheet(isPresented: $showingLog) {
            NavigationStack {
                InteractionLog(session: session)
                    .navigationTitle("交互记录")
                    .toolbar { ToolbarItem { Button("完成") { showingLog = false } } }
            }
            .padding()
        }
    }

    private var innerDisplay: some View {
        Group {
            if remote.hasSelection {
                GeometryReader { geometry in
                    VStack(spacing: 0) {
                        RealWindowMonitor(remote: remote).frame(height: geometry.size.height * 0.75)
                        TouchKeyboard(session: session, onKey: { remote.key($0, session: session) })
                            .frame(height: geometry.size.height * 0.25)
                    }
                }
            } else { InnerDisplay(session: session) }
        }
            .background(GeometryReader { size in
                Color.clear
                    .onAppear { capture.monitorSize = CGSize(width: size.size.width, height: size.size.height * 0.75) }
                    .onChange(of: size.size) { _, value in capture.monitorSize = CGSize(width: value.width, height: value.height * 0.75) }
            })
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .padding(6)
            .background(Color(red: 0.08, green: 0.09, blue: 0.11), in: RoundedRectangle(cornerRadius: 24))
            .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
    }

    private var outerDisplay: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.14, green: 0.23, blue: 0.28), Color(red: 0.08, green: 0.13, blue: 0.18)], startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(spacing: 12) {
                HStack {
                    Text("OUTER DISPLAY").font(.caption.monospaced().weight(.semibold)).tracking(2)
                    Spacer(minLength: 0)
                }
                Spacer()
                Image(systemName: "hand.draw").font(.largeTitle)
                Text(capture.isActive ? "已接管" : "Touchpad").font(.title2.weight(.medium))
                Text(remote.hasSelection ? "真实窗口 · 双指滚动" : capture.isActive ? "双指滚动 · 三指上滑展开" : "食指 / 中指").font(.callout).foregroundStyle(.white.opacity(0.6))
                Spacer()
                Text(remote.hasSelection ? "\(remote.title)\n后台输入实验 · Esc 退出" : session.status).font(.caption).foregroundStyle(.white.opacity(0.7))
            }
            .padding()
            .allowsHitTesting(false)
            TouchpadSurface(onEvent: { event in
                if remote.hasSelection { remote.touchpad(event) } else { session.touchpad(event) }
            })
        }
        .foregroundStyle(.white)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .padding(6)
        .background(Color(red: 0.08, green: 0.09, blue: 0.11), in: RoundedRectangle(cornerRadius: 24))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
    }
}

@MainActor
final class WorkbenchLifecycle: NSObject, NSApplicationDelegate {
    weak var host: LANHost?
    var reopenWindow: (() -> Void)?
    private var monitorTask: Task<Void, Never>?
    private var startupTask: Task<Void, Never>?
    func attach(_ host: LANHost, setup: HostPermissionSetup) {
        self.host = host
        guard monitorTask == nil else { return }
        monitorTask = Task { await setup.monitor(host) }
        startupTask = Task {
            while !Task.isCancelled {
                if !host.pairingCredentialLoading && !setup.visible && !host.scaleBusy && !host.restoreFailed {
                    if host.autoStartHost { await host.startDefaultDisplay() }
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
        guard let host else { return .terminateNow }
        Task { @MainActor in
            await host.stopAndRestore()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
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
            else { Task { await host.startDefaultDisplay() } }
        }.disabled(setup.restarting) }
        Divider()
        Button("退出 Chordesk") { NSApp.terminate(nil) }
    }
}

private struct HostScene: View {
    @ObservedObject var host: LANHost
    @ObservedObject var setup: HostPermissionSetup
    let lifecycle: WorkbenchLifecycle
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        LANHostView(host: host, permissionSetup: setup).onAppear {
            lifecycle.reopenWindow = { openWindow(id: "lan-host") }
            lifecycle.attach(host, setup: setup)
        }
    }
}

@main
enum ChordeskEntry {
    static func main() {
        if CommandLine.arguments.contains("--chordesk-permission-probe") {
            HostPermissionProbe.printSnapshot()
            return
        }
        DuoWorkbenchApp.main()
    }
}

struct DuoWorkbenchApp: App {
    @NSApplicationDelegateAdaptor(WorkbenchLifecycle.self) private var lifecycle
    @StateObject private var host = LANHost()
    @StateObject private var setup = HostPermissionSetup()
    var body: some Scene {
        Window("Chordesk · Mac 主机", id: "lan-host") {
            HostScene(host: host, setup: setup, lifecycle: lifecycle)
        }.defaultSize(width: 540, height: 650)
        MenuBarExtra("Chordesk", systemImage: "rectangle.on.rectangle") { HostMenuBar(host: host, setup: setup) }
    }
}
#endif

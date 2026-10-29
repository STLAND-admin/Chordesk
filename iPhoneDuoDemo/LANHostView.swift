#if os(macOS)
import CoreImage.CIFilterBuiltins
import SwiftUI

struct LANHostView: View {
    @ObservedObject var host: LANHost
    @ObservedObject var permissionSetup: HostPermissionSetup
    @State private var showingSettings = false
    @State private var showingAbout = false
    @State private var showingPermissions = false
    @State private var showingPairingResetConfirmation = false
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                HStack(spacing: 14) {
                    ChordBrand.image("Chordesk")?.resizable().scaledToFit().frame(maxWidth: 64, maxHeight: 64)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Chordesk").font(.largeTitle.weight(.semibold))
                        Text("Mac 主机 · 前后协作，像按和弦一样控制").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                VStack(spacing: 16) {
                    Label(host.sharing ? (host.connected ? "已连接 · " + host.clientName : "等待连接") : "服务已停止",
                          systemImage: host.sharing ? "link" : "pause.circle")
                        .font(.title3.weight(.medium)).accessibilityIdentifier("host-service-state")
                    if host.sharing {
                        Text(host.currentDisplayName).foregroundStyle(.secondary)
                        if let pairing = host.pairing { CachedPairingCode(code: pairing.code) }
                        Text("首次扫码绑定；已配对的 Mac 可在手机列表中直接连接。")
                            .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        if host.connected {
                            Toggle("允许这台手机控制 Mac", isOn: Binding(get: { host.controlAllowed }, set: { host.setControl($0) }))
                                .toggleStyle(.switch).accessibilityIdentifier("lan-allow-control")
                        }
                        Button(role: .destructive) { host.stop() } label: { Label("停止服务", systemImage: "stop.circle") }
                            .accessibilityIdentifier("lan-stop-sharing")
                    } else {
                        Text("默认共享内置显示器；没有内置屏时使用主显示器。")
                            .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        Button {
                            if permissionSetup.visible { showingPermissions = true; showingSettings = true }
                            else { Task { await host.startDefaultDisplay() } }
                        } label: { Label("开始服务", systemImage: "play.circle.fill") }
                            .buttonStyle(.borderedProminent).disabled(permissionSetup.restarting || host.pairingCredentialLoading || host.scaleBusy)
                            .accessibilityIdentifier("lan-start-sharing")
                    }
                }.padding(24).frame(maxWidth: .infinity).modifier(HostGlassCard())
                if permissionSetup.visible {
                    Button { showingSettings = true } label: { Label("完成首次权限设置", systemImage: "lock.shield") }
                        .accessibilityIdentifier("host-permission-settings")
                }
                if !host.sharing || host.restoreFailed || permissionSetup.restarting {
                    Text(permissionSetup.restarting ? permissionSetup.message : host.status)
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                Text("关闭窗口后继续在菜单栏运行。退出 Chordesk 或停止服务才会断开连接。")
                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }.padding(24)
        }
        .background(LinearGradient(colors: [Color.primary.opacity(0.035), Color.primary.opacity(0.08), Color.clear], startPoint: .topLeading, endPoint: .bottomTrailing))
        .tint(.gray)
        .disabled(permissionSetup.restarting)
        .toolbar {
            ToolbarItem { Button { showingSettings = true } label: { Label("设置", systemImage: "gearshape") }.accessibilityIdentifier("host-settings") }
            ToolbarItem { Button { showingAbout = true } label: { Label("关于 Chordesk", systemImage: "info.circle") } }
        }
        .sheet(isPresented: $showingSettings) { settings }
        .sheet(isPresented: $showingAbout) { ChordAboutView() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in Task { await permissionSetup.check(host) } }
    }

    private var settings: some View {
        NavigationStack {
            Form {
                Section("运行与连接") {
                    Toggle("启动 Chordesk 后自动开启内置屏服务", isOn: $host.autoStartHost)
                    Toggle("配对后自动控制、切屏并适配 Duo", isOn: $host.autoConfigurePairing)
                    Toggle("共享期间保持系统运行，允许显示器息屏", isOn: $host.keepAwakeWhileSharing)
                    Toggle("已配对手机连接时唤醒显示器", isOn: $host.wakeDisplayOnConnect)
                    Text("息屏不会退出服务；真正睡眠、合盖、退出登录及重启后未登录不保证可连接。唤醒显示器不会跳过锁屏密码。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                DisclosureGroup("共享屏幕与文字大小（通常在手机调整）") {
                    displayControls
                    scalingControls
                }
                DisclosureGroup("系统权限", isExpanded: $showingPermissions) {
                    HostPermissionChecklist(setup: permissionSetup, host: host)
                }
                DisclosureGroup("画质与传输") {
                    Picker("画质", selection: Binding(get: { host.videoQuality }, set: { value in Task { await host.setVideoQuality(value) } })) {
                        ForEach(LANVideoQuality.allCases) { Text($0.title).tag($0) }
                    }.disabled(host.switchingDisplay || host.scaleBusy)
                    Text(host.videoQuality.detail).font(.caption).foregroundStyle(.secondary)
                }
                DisclosureGroup("Duo 远程麦克风") {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("允许已配对 Duo 传入麦克风", isOn: $host.allowsMicrophone)
                        Picker("发送到虚拟音频设备", selection: $host.microphoneDestination) {
                            Text("请选择（默认不路由声音）").tag("")
                            ForEach(host.microphoneDestinations) { Text($0.name).tag($0.id) }
                        }
                        Label(host.microphoneMessage, systemImage: host.microphoneActive ? "mic.fill" : "mic.slash")
                        Button("刷新音频设备") { host.refreshMicrophoneDevices() }
                        Text("安装 BlackHole 2ch 后，在此选择它；会议／语音应用也选择同名麦克风。只改变 Chordesk 的输出，不修改 Mac 默认音频设备。手机端默认关闭；开启时才传输。24 kHz 单声道 PCM，约 0.384 Mbps，不保存录音。")
                            .font(.caption).foregroundStyle(.secondary)
                        Link("BlackHole 官方安装说明", destination: URL(string: "https://existential.audio/blackhole/")!)
                    }.padding(5)
                }

                DisclosureGroup("网络与配对") {
                    Picker("局域网地址", selection: $host.selectedAddress) { ForEach(host.addresses, id: \.self) { Text($0).tag($0) } }.disabled(host.sharing)
                    Button("刷新地址") { host.refreshAddresses() }.disabled(host.sharing)
                    if let pairing = host.pairing {
                        LabeledContent("地址", value: "\(pairing.host):\(pairing.port)")
                        Button("复制配对信息") {
                            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(pairing.code, forType: .string)
                        }
                    }
                    Text(host.pairingCredentialStored ? "配对密钥已保存在钥匙串。二维码图片缓存并每 5 分钟刷新；密钥保持稳定，不使已有配对失效。" : "配对密钥未持久保存，重启后需重新扫码。")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("重置配对密钥", role: .destructive) { showingPairingResetConfirmation = true }
                        .disabled(host.sharing || host.connected || host.pairingCredentialLoading)
                }
                DisclosureGroup("诊断信息") {
                    Text(host.status)
                    Text(host.availabilityMessage)
                    Text("发送 \(host.videoMbps, specifier: "%.1f") Mbps · \(host.videoFPS, specifier: "%.0f") fps")
                    Text("画面 \(host.frameCount) 帧 · 收到 \(host.inputCount) 次 · 投递 \(host.postedInputCount) 次")
                    Text(host.lastInput)
                    Text(Bundle.main.bundlePath).textSelection(.enabled)
                }
            }.formStyle(.grouped).navigationTitle("Chordesk 设置").tint(.gray)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { showingSettings = false } } }
                .task { showingPermissions = permissionSetup.visible; host.refreshMicrophoneDevices(); await host.refreshDisplays(); await host.refreshScaleOptions() }
                .onChange(of: host.selectedDisplay) { _, _ in Task { await host.refreshScaleOptions() } }
                .confirmationDialog("重置配对密钥？", isPresented: $showingPairingResetConfirmation, titleVisibility: .visible) {
                    Button("重置并解除旧设备绑定", role: .destructive) { host.resetPairingCredential() }
                } message: { Text("已保存的手机配对信息将失效。下次需要重新扫码。") }
        }
    }

    private var displayControls: some View {
        GroupBox("选择共享的实体显示器") {
            VStack(alignment: .leading, spacing: 10) {
                Picker("显示器", selection: $host.selectedDisplay) {
                    if host.displays.isEmpty { Text("尚无可用显示器").tag(UInt32(0)) }
                    ForEach(host.displays) { display in
                        Text("\(display.name) · \(Int(display.width))×\(Int(display.height))").tag(display.id)
                    }
                }.disabled(host.switchingDisplay || host.scaleBusy)
                Text(host.displayListMessage).font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button { Task { await host.refreshDisplays(requestPermission: true) } } label: {
                        Label(host.screenCaptureAllowed ? "刷新显示器列表" : "授权屏幕录制并读取列表", systemImage: "display.badge.checkmark")
                    }
                    Button {
                        let id = host.selectedDisplay
                        Task {
                            if !host.screenCaptureAllowed { await host.refreshDisplays(requestPermission: true) }
                            await host.selectDisplay(id)
                        }
                    } label: { Label(host.sharing ? "切换到所选显示器" : "共享所选显示器", systemImage: "play.display") }
                        .buttonStyle(.borderedProminent)
                        .disabled(host.selectedDisplay == 0 || host.switchingDisplay || host.scaleBusy)
                }
                Toggle("允许手机切屏与缩放", isOn: $host.allowsDisplaySwitching)
                    .disabled(!host.screenCaptureAllowed)
                    .accessibilityIdentifier("lan-allow-display-switch")
                Text("开启后，已配对手机可切换显示器；具备手机控制权限时可调整文字大小。默认在配对成功后自动开启，断开或停止共享后关闭。")
                    .font(.caption).foregroundStyle(.secondary)
                if host.switchingDisplay { ProgressView("正在切换显示器…") }
            }.padding(5)
        }
    }

    private var scalingControls: some View {
        GroupBox("显示模式 · 文字大小") {
            VStack(alignment: .leading, spacing: 10) {
                Picker("模式切换方式", selection: Binding(get: { host.scalingBackend }, set: { host.setScalingBackend($0) })) {
                    ForEach(DisplayScalingBackend.allCases, id: \.self) { Text($0.title).tag($0) }
                }.disabled(host.connected || host.scaleBusy || host.switchingDisplay || host.restoreFailed || host.scaleState?.canRestore == true)
                Text("切换方案前先断开手机并恢复原设置；兼容方案仅供已安装 BetterDisplay 的用户使用。")
                    .font(.caption).foregroundStyle(.secondary)
                Text(host.sharing ? "目标：当前共享的 \(host.currentDisplayName)" : "目标：上方选中的实体显示器")
                Text(host.scaleMessage).font(.caption).foregroundStyle(.secondary)
                if let state = host.scaleState {
                    Text("当前：\(state.current)").font(.caption.monospacedDigit())
                    ForEach(state.options) { option in
                        Button { Task { await host.adjustDisplayScale(option.id) } } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(option.title).fontWeight(.medium)
                                    Text(option.detail).font(.caption)
                                }
                                Spacer()
                                Label("应用", systemImage: "arrow.right.circle")
                            }.foregroundStyle(host.scaleBusy || host.switchingDisplay ? Color.secondary : Color.primary)
                                .padding(5).frame(maxWidth: .infinity, alignment: .leading)
                        }.buttonStyle(.bordered).disabled(host.scaleBusy || host.switchingDisplay)
                    }
                    Button("恢复原设置") { Task { await host.adjustDisplayScale("restore") } }
                        .disabled(!state.canRestore || host.scaleBusy || host.switchingDisplay)
                }
                Button { Task { await host.refreshScaleOptions() } } label: {
                    Label("刷新可用模式", systemImage: "arrow.clockwise")
                }.disabled(host.scaleBusy)
                Text("直接改变这块实体屏的逻辑分辨率，Mac 本机也会同步改变文字大小。保存连接前的模式；手机断开、停止共享或正常退出主机时自动恢复。恢复失败保留记录，下次启动重试。不创建虚拟显示器。")
                    .font(.caption).foregroundStyle(.secondary)
                if host.restoreFailed {
                    Button("重试恢复连接前分辨率") { host.restoreSessionSettings() }
                        .disabled(host.scaleBusy || host.connected)
                }
                if host.scaleBusy { ProgressView(host.restoringScale ? "正在恢复连接前分辨率…" : "正在调整…") }
            }.padding(5)
        }
    }

}

/// Isolated from frame/input publication: stable payload, cached image, five-minute refresh.
private struct CachedPairingCode: View {
    let code: String
    @State private var image: NSImage?
    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).interpolation(.none).resizable().scaledToFit()
                    .padding(16).background(.white, in: RoundedRectangle(cornerRadius: 20))
            } else { ProgressView("生成配对码") }
        }.frame(maxHeight: 240).accessibilityLabel("Chordesk 配对二维码")
        .task(id: code) {
            while !Task.isCancelled {
                let filter = CIFilter.qrCodeGenerator(); filter.message = Data(code.utf8)
                if let output = filter.outputImage {
                    let scaled = output.transformed(by: .init(scaleX: 8, y: 8))
                    if let cg = CIContext().createCGImage(scaled, from: scaled.extent) { image = NSImage(cgImage: cg, size: .zero) }
                }
                do { try await Task.sleep(for: .seconds(300)) } catch { return }
            }
        }
    }
}
private struct HostGlassCard: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26, *) { content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28)) }
        else { content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28)) }
    }
}
#endif

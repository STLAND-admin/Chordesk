import Foundation

/// Recovery is driven by session/presentation state, never by how long a user
/// holds still. A folded/unavailable accessory is not a broken touch surface.
struct RearCaptureRecovery {
    enum Action: Equatable { case none, restartSession, rebindAccessory }
    private(set) var attempts = 0
    private var unhealthySamples = 0
    mutating func sample(allowed: Bool, interrupted: Bool, running: Bool,
                         enabled: Bool, available: Bool, presented: Bool) -> Action {
        guard allowed, !interrupted else { unhealthySamples = 0; return .none }
        guard !running || (available && (!enabled || !presented)) else {
            unhealthySamples = 0; return .none
        }
        unhealthySamples += 1
        guard unhealthySamples >= 2, attempts < 3 else { return .none }
        unhealthySamples = 0; attempts += 1
        return running ? .rebindAccessory : .restartSession
    }
}

#if os(iOS)
@preconcurrency import AVFoundation
import SwiftUI
import UIKit

enum OuterControlMode: String, CaseIterable, Identifiable {
    case frontTouch
    var id: String { rawValue }
    var title: String { "背面切换 · 正面操作" }
}

struct RearControlSettings: View {
    @AppStorage("keyboardDefaultModeV2") private var defaultMode = InnerInputMode.touchpad.rawValue
    @AppStorage("rearActivation") private var activation = RearActivation.momentary.rawValue
    @AppStorage("rearTriggerV2") private var trigger = RearTrigger.longPress.rawValue
    var body: some View {
        Section("内屏默认模式") {
            Picker("默认显示", selection: $defaultMode) {
                ForEach(InnerInputMode.allCases) { Text($0.title).tag($0.rawValue) }
            }.pickerStyle(.segmented).accessibilityIdentifier("inner-default-mode")
            Text("触控模式保留完整桌面，通过直接触控或触控板操作；键盘模式以输入法覆盖桌面。右侧控制菜单可随时唤出或收起。")
                .font(.footnote).foregroundStyle(.secondary)
        }
        Section("背面只切换直接触控／触控板") {
            Picker("切换方式", selection: $activation) {
                ForEach(RearActivation.allCases) { Text($0.title).tag($0.rawValue) }
            }.pickerStyle(.segmented).accessibilityIdentifier("rear-activation")
            Picker("触发动作", selection: $trigger) {
                Text(activation == RearActivation.momentary.rawValue ? "双指接触" : "双指轻点").tag(RearTrigger.touch.rawValue)
                Text("双指长按 0.45 秒").tag(RearTrigger.longPress.rawValue)
            }.pickerStyle(.segmented).accessibilityIdentifier("rear-trigger")
            Text(activation == RearActivation.momentary.rawValue
                 ? "触发后临时使用另一种指针模式，松开恢复默认直接触控／触控板。键盘不受影响。"
                 : "触发一次切换直接触控与触控板，再触发一次恢复；切换后可以松开背面。")
                .font(.footnote).foregroundStyle(.secondary)
            Text("双指用于模式切换；一指留作正面双指上下滑的窗口总览组合。背面不发送鼠标移动、点击或拖选；边缘禁触仍生效。")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
}

/// A stable system sheet: mode selection must not rely on a nested live-updating menu.
struct CameraControlSettings: View {
    @ObservedObject var camera: CameraAccessory
    var select: (OuterControlMode) -> Void
    var stop: () -> Void
    @Environment(\.dismiss) private var dismiss
    @AppStorage("rearControlAutoStartV1") private var autoStart = true

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("连接后自动启用背面", isOn: $autoStart)
                    Button { select(.frontTouch) } label: {
                        Label("启用背面模式切换", systemImage: "hand.point.up.left")
                    }.accessibilityIdentifier("camera-mode-front-touch")
                    Text("所有点击、滚动、拖选都在正面完成。背面只负责切换直接触控与触控板。相机保持运行，画面不显示、不保存、不传输。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                RearControlSettings()
                RearAreaSettings(camera: camera)
                if camera.running || camera.starting {
                    Section {
                        Label("当前：\(camera.mode.title)", systemImage: "camera.fill")
                        Button("停止相机外屏控制", role: .destructive, action: stop)
                            .accessibilityIdentifier("camera-control-stop")
                    }
                }
            }
            .navigationTitle("相机外屏控制")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }.accessibilityIdentifier("camera-control-done")
                }
            }
        }
    }
}

/// Keep the public capture session active without displaying, retaining or transmitting pixels.
// The delegate has no mutable state; the immutable queue is safe to pass to capture setup.
private final class DiscardedCameraFrames: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let queue = DispatchQueue(label: "dev.iphoneduo.camera-discard")
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {}
}

@MainActor
final class CameraAccessory: ObservableObject {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "dev.iphoneduo.camera")
    private let discardedFrames = DiscardedCameraFrames()
    @Published var mode: OuterControlMode = .frontTouch
    @Published private(set) var running = false
    @Published private(set) var starting = false
    @Published var enabled = false
    @Published var available = false
    @Published var presented = false
    @Published var reverseX = false
    @Published var reverseY = false
    @Published var status = "相机未开启"
    @Published private(set) var touchCount = 0
    @Published private(set) var lastTouch = "尚未收到外屏触摸"
    @Published var rearViewportSize = CGSize.zero
    @Published private(set) var surfaceEpoch = 0
    @Published private(set) var recoveryMessage = "尚未自动恢复"
    private(set) var requested = false
    var recoveryAllowed = false
    private var recovery = RearCaptureRecovery()
    private var healthTimer: Timer?
    private var checkingHealth = false
    private var interrupted = false
    private var recoveryBlocked = false
    private var rebindTask: Task<Void, Never>?
    private var generation = UUID()
    private var observers: [NSObjectProtocol] = []

    init() {
        let center = NotificationCenter.default
        for name in [AVCaptureSession.wasInterruptedNotification, AVCaptureSession.interruptionEndedNotification,
                     AVCaptureSession.runtimeErrorNotification] {
            observers.append(center.addObserver(forName: name, object: session, queue: .main) { [weak self] notification in
                let reset = (notification.userInfo?[AVCaptureSessionErrorKey] as? AVError)?.code == .mediaServicesWereReset
                Task { @MainActor in
                    guard let self, self.requested else { return }
                    self.surfaceEpoch += 1
                    if name == AVCaptureSession.wasInterruptedNotification {
                        self.interrupted = true; self.running = false
                        self.status = "相机暂时中断 · 等待系统恢复"
                    } else if name == AVCaptureSession.interruptionEndedNotification {
                        self.interrupted = false
                        self.recoveryMessage = "系统中断已结束，正在检查背面接收"
                        self.checkHealth()
                    } else {
                        self.running = false; self.recoveryBlocked = !reset
                        self.status = reset ? "相机服务已重置 · 等待恢复" : "相机发生错误，请重新开启背面控制"
                        self.checkHealth()
                    }
                }
            })
        }
    }

    func start() {
        if !requested {
            requested = true; recovery = RearCaptureRecovery(); recoveryBlocked = false
            let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.checkHealth() }
            }
            healthTimer = timer; RunLoop.main.add(timer, forMode: .common)
        }
        guard !running, !starting, !interrupted, !recoveryBlocked else { return }
        let token = UUID(); generation = token
        starting = true; status = "正在申请相机权限…"
        Task { [self] in
            let allowed = await AVCaptureDevice.requestAccess(for: .video)
            guard generation == token else { return }
            guard allowed else { stop(); status = "相机权限未允许，请在设置中开启"; return }
            guard UIApplication.shared.applicationState == .active else { starting = false; return }
            let session = session
            let discardedFrames = discardedFrames
            queue.async { [weak self, token] in
                do {
                    try { () throws -> Void in
                    session.beginConfiguration()
                    defer { session.commitConfiguration() }
                    if session.inputs.isEmpty {
                        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
                            throw CameraError.unavailable
                        }
                        let input = try AVCaptureDeviceInput(device: camera)
                        guard session.canAddInput(input) else { throw CameraError.unavailable }
                        session.addInput(input)
                    }
                    if session.canSetSessionPreset(.vga640x480) { session.sessionPreset = .vga640x480 }
                    if session.outputs.isEmpty {
                        let output = AVCaptureVideoDataOutput()
                        output.alwaysDiscardsLateVideoFrames = true
                        output.setSampleBufferDelegate(discardedFrames, queue: discardedFrames.queue)
                        guard session.canAddOutput(output) else { throw CameraError.unavailable }
                        session.addOutput(output)
                    }
                    // Video only: no microphone or audio-session activation to suppress haptics.
                    session.automaticallyConfiguresApplicationAudioSession = false
                    }()
                    if !session.isRunning && !session.isInterrupted { session.startRunning() }
                    let running = session.isRunning
                    Task { @MainActor in
                        guard let self, self.generation == token else { return }
                        self.starting = false; self.running = running; self.enabled = running
                        self.surfaceEpoch += 1
                        self.status = running ? "相机运行中 · 画面不显示、不保存、不传输" : "相机未能启动"
                    }
                } catch {
                    Task { @MainActor in
                        guard let self, self.generation == token else { return }
                        self.starting = false; self.status = "相机启动失败：\(error.localizedDescription)"
                    }
                }
            }
        }
    }

    func stop() {
        generation = UUID()
        requested = false; recoveryAllowed = false; interrupted = false; recoveryBlocked = false
        healthTimer?.invalidate(); healthTimer = nil
        rebindTask?.cancel(); rebindTask = nil; checkingHealth = false
        enabled = false; running = false; starting = false; available = false; presented = false
        status = "相机已停止"
        let session = session
        queue.async { if session.isRunning { session.stopRunning() } }
    }

    /// Re-arm a cancelled UIView after foreground/permission transitions. Old
    /// contacts remain cancelled until lifted; this does not synthesize touches.
    func resumeInput() {
        guard requested else { return }
        surfaceEpoch += 1
        checkHealth()
    }

    private func checkHealth() {
        guard requested, recoveryAllowed, !recoveryBlocked, !starting, !checkingHealth,
              rebindTask == nil, UIApplication.shared.applicationState == .active,
              AVCaptureDevice.authorizationStatus(for: .video) == .authorized else { return }
        checkingHealth = true
        let token = generation, session = session
        queue.async { [weak self] in
            let actualRunning = session.isRunning, actualInterrupted = session.isInterrupted
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                self.checkingHealth = false
                guard self.requested, self.recoveryAllowed, UIApplication.shared.applicationState == .active else { return }
                self.running = actualRunning && !actualInterrupted
                let action = self.recovery.sample(allowed: !self.recoveryBlocked,
                    interrupted: self.interrupted || actualInterrupted, running: actualRunning,
                    enabled: self.enabled, available: self.available, presented: self.presented)
                switch action {
                case .none: break
                case .restartSession:
                    self.recoveryMessage = "自动恢复相机会话（\(self.recovery.attempts)/3）"
                    self.start()
                case .rebindAccessory:
                    self.recoveryMessage = "自动重新连接背面界面（\(self.recovery.attempts)/3），请重新落指"
                    self.enabled = false; self.surfaceEpoch += 1
                    self.rebindTask = Task { [weak self] in
                        try? await Task.sleep(for: .milliseconds(250))
                        guard !Task.isCancelled, let self, self.generation == token else { return }
                        self.rebindTask = nil
                        guard self.requested, self.recoveryAllowed, self.running,
                              UIApplication.shared.applicationState == .active else { return }
                        self.enabled = true
                    }
                }
            }
        }
    }

    func record(_ event: TouchpadEvent) {
        touchCount += 1
        switch event {
        case .pointerMoved: lastTouch = "单指移动"
        case .dragMoved, .dragBegan: lastTouch = "按住拖拽"
        case .dragEnded: lastTouch = "拖拽结束"
        case .leftClick: lastTouch = "单指点按"
        case .rightClick: lastTouch = "双指点按"
        case .scrolled: lastTouch = "双指滚动"
        }
    }
    func recordContacts(_ count: Int) {
        touchCount += 1
        lastTouch = count == 0 ? "背面已松开" : "背面有效接触 \(count) 指"
    }
    enum CameraError: Error { case unavailable }

    deinit { healthTimer?.invalidate(); rebindTask?.cancel(); observers.forEach { NotificationCenter.default.removeObserver($0) } }
}

struct OuterRemoteTouchpad: View {
    @ObservedObject var client: LANClient
    @ObservedObject var camera: CameraAccessory
    @ObservedObject var grip: GripInteraction
    @AppStorage("outerTouchEdgeInset") private var outerEdgeInset = TouchpadTuning.defaultEdgeInset
    @AppStorage("rearCustomAreaEnabledV1") private var customArea = false
    @AppStorage("rearActiveBoxV1") private var regionText = ""
    private var region: RearActiveRegion { customArea ? .decode(regionText, inset: outerEdgeInset) : .centered(inset: outerEdgeInset) }
    var isAccessory = true
    private var inputReady: Bool { !grip.controlsPresented && camera.running && camera.enabled && client.acceptsInput }
    var body: some View {
        ZStack {
            Color.black
            GeometryReader { geometry in
                let bounds = CGRect(origin: .zero, size: geometry.size)
                let active = region.rect(in: bounds)
                Path { path in path.addRect(bounds); path.addRect(active) }
                    .fill(.gray.opacity(0.3), style: FillStyle(eoFill: true))
                Path { $0.addRect(active) }.stroke(.mint.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
            }.allowsHitTesting(false)
                .onGeometryChange(for: CGSize.self) { $0.size } action: { camera.rearViewportSize = $0 }
            VStack(spacing: 12) {
                Label("背面模式切换", systemImage: "hand.point.up.left")
                Text(grip.state.requestedFrontMode.title).font(.title2)
                Text("双指 · \(grip.state.activation.title) · \(grip.state.trigger == .longPress ? "长按" : "接触／轻点")")
                Text("点击 · 滚动 · 拖选均在正面完成").font(.caption)
            }.padding().allowsHitTesting(false)
            TouchpadSurface(behavior: .contactsOnly, inputEnabled: inputReady,
                            edgeInsetFraction: outerEdgeInset, activeRegion: region, contactGestureFingers: 2,
                            inputEpoch: camera.surfaceEpoch,
                            inputIsCurrent: { !grip.controlsPresented && camera.running && camera.enabled && client.acceptsInput }, onContactCount: { count in
                camera.recordContacts(count)
                if count == 0 { grip.outerContacts(0) }
                else if camera.running && camera.enabled && client.acceptsInput { grip.outerContacts(count) }
            }, onContactGesture: { gesture in
                guard camera.running, camera.enabled, client.acceptsInput else { return }
                grip.gesture(gesture)
            }) { _ in /* The rear surface never sends mouse or keyboard input. */ }
                .accessibilityIdentifier("camera-rear-mode-switch")
        }
        .foregroundStyle(.white)
        .onAppear { camera.presented = true }
        .onDisappear { camera.presented = false; grip.cancel(); client.release() }
    }
}

@available(iOS 27.1, *)
struct CameraAccessoryWorkspace<Content: View>: View {
    @ObservedObject var camera: CameraAccessory
    @ObservedObject var client: LANClient
    @ObservedObject var grip: GripInteraction
    let content: Content
    var body: some View {
        content.sceneAccessory {
            CameraCaptureAccessory(isEnabled: $camera.enabled) {
                OuterRemoteTouchpad(client: client, camera: camera, grip: grip)
            }
            .onAvailabilityChange { value in
                Task { @MainActor in
                    camera.available = value
                    if !value { grip.cancel(); client.release() }
                }
            }
        }
    }
}

struct QRScannerView: View {
    var scanned: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var allowed = false
    var body: some View {
        NavigationStack {
            Group {
                if allowed { QRScanner(scanned: scanned) }
                else { ContentUnavailableView("需要相机权限", systemImage: "camera", description: Text("用于读取 Mac 上的配对二维码")) }
            }
            .navigationTitle("扫描配对二维码")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
            .task { allowed = await AVCaptureDevice.requestAccess(for: .video) }
        }
    }
}

private struct QRScanner: UIViewControllerRepresentable {
    let scanned: (String) -> Void
    final class Controller: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
        let capture = AVCaptureSession()
        let queue = DispatchQueue(label: "dev.iphoneduo.qr-scan")
        var scanned: ((String) -> Void)?
        private var delivered = false
        private var preview: AVCaptureVideoPreviewLayer?
        override func viewDidLoad() {
            super.viewDidLoad()
            guard let camera = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: camera), capture.canAddInput(input) else { return }
            capture.addInput(input)
            let output = AVCaptureMetadataOutput()
            guard capture.canAddOutput(output) else { return }
            capture.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            output.metadataObjectTypes = [.qr]
            let layer = AVCaptureVideoPreviewLayer(session: capture)
            layer.videoGravity = .resizeAspectFill
            view.layer.addSublayer(layer); preview = layer
            queue.async { [capture] in capture.startRunning() }
        }
        override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); preview?.frame = view.bounds }
        func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput objects: [AVMetadataObject], from connection: AVCaptureConnection) {
            guard !delivered, let value = (objects.first as? AVMetadataMachineReadableCodeObject)?.stringValue else { return }
            delivered = true; stop(); scanned?(value)
        }
        func stop() { queue.async { [capture] in if capture.isRunning { capture.stopRunning() } } }
    }
    func makeUIViewController(context: Context) -> Controller { let view = Controller(); view.scanned = scanned; return view }
    func updateUIViewController(_ view: Controller, context: Context) { view.scanned = scanned }
    static func dismantleUIViewController(_ view: Controller, coordinator: ()) { view.stop() }
}
#endif

#if os(macOS)
import AppKit
import ApplicationServices
import CoreImage
import ScreenCaptureKit
import SwiftUI

/// A user-selected window, captured locally. Input is addressed to its process/window,
/// never posted to the global HID event stream. Background input remains experimental.
@MainActor
final class WindowRemoteSession: NSObject, ObservableObject, SCContentSharingPickerObserver {
    @Published private(set) var image: CGImage?
    @Published private(set) var title = ""
    @Published private(set) var status = "选择一个真实应用窗口"
    @Published private(set) var hasSelection = false
    @Published private(set) var isStarting = false
    @Published private(set) var inputAllowed = false
    @Published private(set) var sourceAvailable = false
    @Published private(set) var capturePaused = false
    @Published private(set) var sourceSize = CGSize(width: 1, height: 1)
    @Published private(set) var cursor = CGPoint(x: 0.5, y: 0.5)
    var displayedSize = CGSize(width: 1, height: 1)
    var invalidateInput: (() -> Void)?

    private var target: SCWindow?
    private var process: NSRunningApplication?
    private var bounds = CGRect.zero
    private var stream: SCStream?
    private var receiver: WindowFrameReceiver?
    private var monitorTimer: Timer?
    private var generation = UUID()
    private var observingPicker = false
    private var mouseIsDown = false
    private var rightMouseIsDown = false
    private var heldKeys: [UInt16: NSEvent] = [:]
    private var heldModifiers: Set<UInt16> = []
    private var lastClickTime: TimeInterval = 0
    private var lastClickPoint = CGPoint.zero
    private var clickCount = 1

    func chooseWindow() {
        guard #available(macOS 15.2, *) else {
            status = "真实窗口实验需要 macOS 15.2 或更新版本"; return
        }
        invalidateInput?()
        NSApp.activate()
        NSApp.mainWindow?.makeKeyAndOrderFront(nil)
        let picker = SCContentSharingPicker.shared
        if !observingPicker { picker.add(self); observingPicker = true }
        var config = SCContentSharingPickerConfiguration()
        config.allowedPickerModes = [.singleWindow]
        config.excludedBundleIDs = [Bundle.main.bundleIdentifier ?? "dev.iphoneduo.workbench"]
        config.allowsChangingSelectedContent = false
        picker.defaultConfiguration = config
        picker.isActive = true
        picker.present(using: .window)
    }

    func requestInputPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        inputAllowed = AXIsProcessTrustedWithOptions(options)
        status = inputAllowed ? "可操作所选窗口 · P 接管 / Esc 退出" : "请在系统设置 → 隐私与安全性 → 辅助功能中允许 Chordesk · Mac 主机，然后返回"
    }

    func refreshPermission() {
        let allowed = AXIsProcessTrusted()
        if allowed && !inputAllowed && hasSelection { status = "辅助功能已允许 · P 接管 / Esc 退出" }
        if !allowed && inputAllowed { invalidateInput?(); releaseInput() }
        inputAllowed = allowed
    }

    func prepareInput() -> Bool {
        refreshPermission()
        guard inputAllowed else { requestInputPermission(); return false }
        refreshTarget()
        guard hasSelection, image != nil, sourceAvailable, !capturePaused, NSApp.isActive else {
            status = "请让目标窗口和原型位于同一桌面，并保持目标窗口未最小化"; return false
        }
        return true
    }

    func disconnect() {
        invalidateInput?()
        releaseInput()
        generation = UUID()
        monitorTimer?.invalidate(); monitorTimer = nil
        let old = stream
        stream = nil; receiver = nil
        if let old { Task { try? await old.stopCapture() } }
        target = nil; process = nil; image = nil
        hasSelection = false; isStarting = false; sourceAvailable = false
        capturePaused = false
        status = "已返回本地模拟"
        if observingPicker {
            SCContentSharingPicker.shared.remove(self)
            SCContentSharingPicker.shared.isActive = false
            observingPicker = false
        }
    }

    func openTestDocument() {
        do {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("DuoWindowExperiment", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent("Duo Window Experiment \(UUID().uuidString.prefix(6)).txt")
            let text = "Duo — 真实窗口实验\n\n这是一份新建的临时 TextEdit 文稿。\n在 Chordesk · Mac 主机 中选择这个窗口，然后按 P 接管触控板。\n试试点按、拖选、双指滚动，以及键盘输入。Esc 返回 Mac。\n\n" + (1...24).map { "第 \($0) 行 · 用双指滚动检查真实文稿。" }.joined(separator: "\n")
            try text.write(to: url, atomically: true, encoding: .utf8)
            guard let textEdit = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.TextEdit") else { return }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.createsNewApplicationInstance = true
            configuration.activates = true
            NSWorkspace.shared.open([url], withApplicationAt: textEdit, configuration: configuration) { [weak self] _, error in
                Task { @MainActor in
                    self?.status = error.map { "打开文稿失败：\($0.localizedDescription)" } ?? "测试文稿已打开 · 返回原型，点击“选择真实窗口”"
                }
            }
        } catch { status = "创建文稿失败：\(error.localizedDescription)" }
    }

    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        Task { @MainActor in self.status = self.hasSelection ? "保留原先窗口" : "未选择窗口" }
    }
    nonisolated func contentSharingPickerStartDidFailWithError(_ error: Error) {
        Task { @MainActor in self.status = "窗口选择失败：\(error.localizedDescription)" }
    }
    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
        Task { @MainActor in await self.connect(filter) }
    }

    private func connect(_ filter: SCContentFilter) async {
        guard #available(macOS 15.2, *), filter.style == .window,
              filter.includedWindows.count == 1, let window = filter.includedWindows.first,
              let owner = window.owningApplication, owner.processID != ProcessInfo.processInfo.processIdentifier else {
            status = "请选择另一个应用的单个窗口"; return
        }
        invalidateInput?(); releaseInput()
        generation = UUID()
        let token = generation
        monitorTimer?.invalidate(); monitorTimer = nil
        let old = stream; stream = nil; receiver = nil
        target = window
        process = NSRunningApplication(processIdentifier: owner.processID)
        title = "\(owner.applicationName) · \(window.title ?? "窗口")"
        bounds = window.frame; sourceSize = bounds.size
        cursor = CGPoint(x: 0.5, y: 0.5)
        image = nil; hasSelection = true; isStarting = true; sourceAvailable = false; capturePaused = true
        status = "正在连接 \(owner.applicationName)…"
        if let old { try? await old.stopCapture() }
        guard token == generation else { return }
        let config = SCStreamConfiguration()
        // Resolution is a capture budget, unrelated to adaptive UI layout.
        let scale = min(2, 1600 / max(1, max(bounds.width, bounds.height)))
        config.width = max(2, Int(bounds.width * scale))
        config.height = max(2, Int(bounds.height * scale))
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.queueDepth = 3
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false
        config.capturesAudio = false
        config.ignoreShadowsSingleWindow = true
        config.scalesToFit = true
        // The view restores the live window's aspect ratio after a resize.
        config.preservesAspectRatio = false
        let sink = WindowFrameReceiver { [weak self] image in
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                self.image = image
                self.capturePaused = false
            }
        } paused: { [weak self] in
            Task { @MainActor in
                guard let self, self.generation == token, !self.capturePaused else { return }
                self.capturePaused = true
                self.invalidateInput?(); self.releaseInput()
                self.status = "窗口画面暂停 · 输入已停止"
            }
        } stopped: { [weak self] reason in
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                self.disconnect()
                self.status = "窗口共享已结束：\(reason)"
            }
        }
        let newStream = SCStream(filter: filter, configuration: config, delegate: sink)
        do {
            try newStream.addStreamOutput(sink, type: .screen, sampleHandlerQueue: sink.queue)
            stream = newStream; receiver = sink
            try await newStream.startCapture()
            guard generation == token else { try? await newStream.stopCapture(); return }
            isStarting = false
            refreshPermission(); refreshTarget()
            status = inputAllowed ? "实时窗口 · 按 P 接管触控板" : "实时预览已连接 · 允许辅助功能后可操作"
            monitorTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshTarget() }
            }
        } catch {
            guard generation == token else { return }
            disconnect()
            status = "无法捕获窗口：\(error.localizedDescription)"
        }
    }

    private func refreshTarget() {
        guard let target, let owner = target.owningApplication else { return }
        guard process?.isTerminated == false,
              let info = (CGWindowListCopyWindowInfo(.optionIncludingWindow, target.windowID) as? [[String: Any]])?.first,
              (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == owner.processID,
              let rect = info[kCGWindowBounds as String] as? [String: Any],
              let frame = CGRect(dictionaryRepresentation: rect as CFDictionary), frame.width > 0, frame.height > 0 else {
            disconnect(); status = "目标窗口已关闭，请重新选择"; return
        }
        bounds = frame; sourceSize = frame.size
        let available = (info[kCGWindowIsOnscreen as String] as? Bool) == true
        if sourceAvailable && !available {
            invalidateInput?(); releaseInput()
            status = "目标窗口不在当前桌面或已最小化 · 输入已暂停"
        }
        sourceAvailable = available
        refreshPermission()
    }

    private var canSend: Bool {
        hasSelection && image != nil && sourceAvailable && !capturePaused && NSApp.isActive && AXIsProcessTrusted() && process?.isTerminated == false
    }

    /// Creating AppKit events with the target window number preserves window routing.
    private func post(_ event: NSEvent?, release: Bool = false) {
        guard (release || canSend), let pid = target?.owningApplication?.processID,
              process?.isTerminated == false, let cg = event?.cgEvent else { return }
        cg.postToPid(pid)
    }

    private func mouse(_ type: NSEvent.EventType, count: Int = 1, release: Bool = false) {
        guard let target else { return }
        let point = CGPoint(x: cursor.x * bounds.width, y: (1 - cursor.y) * bounds.height)
        let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                      windowNumber: Int(target.windowID), context: nil, eventNumber: 0,
                                      clickCount: count, pressure: type == .leftMouseUp || type == .rightMouseUp ? 0 : 1)
        post(event, release: release)
    }

    private func move(dx: CGFloat, dy: CGFloat) {
        cursor = CGPoint(x: min(max(cursor.x + dx, 0), 1), y: min(max(cursor.y + dy, 0), 1))
        mouse(mouseIsDown ? .leftMouseDragged : .mouseMoved)
    }

    func touchpad(_ event: TouchpadEvent) {
        guard canSend else { status = "请先允许辅助功能，并保持目标窗口在当前桌面"; return }
        switch event {
        case let .pointerMoved(dx, dy): move(dx: dx * 1.5, dy: dy * 1.5)
        case let .dragMoved(dx, dy): move(dx: dx * 1.5, dy: dy * 1.5)
        case .leftClick: mouse(.leftMouseDown); mouse(.leftMouseUp)
        case .rightClick: mouse(.rightMouseDown); mouse(.rightMouseUp)
        case .dragBegan: mouseIsDown = true; mouse(.leftMouseDown)
        case .dragEnded: mouse(.leftMouseUp); mouseIsDown = false
        case let .scrolled(amount): scroll(y: amount * displayedSize.height, x: 0)
        }
    }

    private func scroll(y: CGFloat, x: CGFloat) {
        guard canSend, let target, let pid = target.owningApplication?.processID else { return }
        let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                            wheel1: Int32(clamping: Int(y.rounded())), wheel2: Int32(clamping: Int(x.rounded())), wheel3: 0)
        event?.location = CGPoint(x: bounds.minX + cursor.x * bounds.width, y: bounds.minY + cursor.y * bounds.height)
        event?.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(target.windowID))
        event?.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: Int64(target.windowID))
        event?.postToPid(pid)
    }

    func handleCaptured(_ event: NSEvent, session: DemoSession) {
        guard canSend else { invalidateInput?(); return }
        switch event.type {
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged:
            move(dx: event.deltaX / max(1, displayedSize.width), dy: event.deltaY / max(1, displayedSize.height))
        case .leftMouseDown:
            let now = event.timestamp
            let distance = hypot((cursor.x - lastClickPoint.x) * bounds.width, (cursor.y - lastClickPoint.y) * bounds.height)
            clickCount = now - lastClickTime < NSEvent.doubleClickInterval && distance < 5 ? min(clickCount + 1, 3) : 1
            lastClickTime = now; lastClickPoint = cursor
            mouseIsDown = true; mouse(.leftMouseDown, count: clickCount)
        case .leftMouseUp: mouse(.leftMouseUp, count: clickCount); mouseIsDown = false
        case .rightMouseDown: rightMouseIsDown = true; mouse(.rightMouseDown)
        case .rightMouseUp: mouse(.rightMouseUp); rightMouseIsDown = false
        case .scrollWheel:
            let factor: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 12
            scroll(y: event.scrollingDeltaY * factor, x: event.scrollingDeltaX * factor)
        case .keyDown, .keyUp, .flagsChanged:
            // P's key-up may arrive after capture starts, without a matching target key-down.
            if event.type == .keyUp && heldKeys[event.keyCode] == nil { return }
            session.shift = event.modifierFlags.contains(.shift)
            session.command = event.modifierFlags.contains(.command)
            session.option = event.modifierFlags.contains(.option)
            session.control = event.modifierFlags.contains(.control)
            let flagsOnly = event.type == .flagsChanged
            let mapped = keyEvent(type: event.type, code: event.keyCode, flags: event.modifierFlags,
                                  text: flagsOnly ? "" : event.characters ?? "", base: flagsOnly ? "" : event.charactersIgnoringModifiers ?? "",
                                  repeated: flagsOnly ? false : event.isARepeat)
            post(mapped)
            if event.type == .keyDown { heldKeys[event.keyCode] = mapped }
            if event.type == .keyUp { heldKeys.removeValue(forKey: event.keyCode) }
            if flagsOnly {
                let modifiers: [UInt16: NSEvent.ModifierFlags] = [54: .command, 55: .command, 56: .shift, 60: .shift, 58: .option, 61: .option, 59: .control, 62: .control]
                if let flag = modifiers[event.keyCode] {
                    if event.modifierFlags.contains(flag) { heldModifiers.insert(event.keyCode) }
                    else { heldModifiers.remove(event.keyCode) }
                }
            }
        default: break
        }
    }

    private func keyEvent(type: NSEvent.EventType, code: UInt16, flags: NSEvent.ModifierFlags, text: String, base: String, repeated: Bool = false) -> NSEvent? {
        guard let target else { return nil }
        return NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                               windowNumber: Int(target.windowID), context: nil, characters: text, charactersIgnoringModifiers: base,
                               isARepeat: repeated, keyCode: code)
    }

    func key(_ value: String, session: DemoSession) {
        switch value {
        case "shift": session.shift.toggle(); return
        case "cmd": session.command.toggle(); return
        case "ctrl": session.control.toggle(); return
        case "opt": session.option.toggle(); return
        default: break
        }
        guard prepareInput() else { return }
        let codes: [String: UInt16] = ["a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
            "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21,
            "6": 22, "5": 23, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29, "o": 31, "u": 32, "i": 34, "p": 35,
            "return": 36, "l": 37, "j": 38, "'": 39, "k": 40, ",": 43, "n": 45, "m": 46, ".": 47,
            "tab": 48, "space": 49, "delete": 51, "esc": 53, "left": 123, "right": 124, "down": 125, "up": 126]
        guard let code = codes[value] else { return }
        let special: [String: String] = ["return": "\r", "tab": "\t", "space": " ", "delete": "\u{7f}", "esc": "\u{1b}",
                                         "left": "\u{f702}", "right": "\u{f703}", "up": "\u{f700}", "down": "\u{f701}"]
        let base = special[value] ?? value
        let text = session.shift ? base.uppercased() : base
        var flags: NSEvent.ModifierFlags = []
        if session.shift { flags.insert(.shift) }; if session.command { flags.insert(.command) }
        if session.option { flags.insert(.option) }; if session.control { flags.insert(.control) }
        post(keyEvent(type: .keyDown, code: code, flags: flags, text: text, base: base))
        post(keyEvent(type: .keyUp, code: code, flags: flags, text: text, base: base))
        session.shift = false; session.command = false; session.option = false; session.control = false
        status = "按键已发送 · 请在真实窗口中确认结果"
    }

    func releaseInput() {
        if mouseIsDown { mouse(.leftMouseUp, release: true) }
        if rightMouseIsDown { mouse(.rightMouseUp, release: true) }
        mouseIsDown = false; rightMouseIsDown = false
        for (code, event) in heldKeys {
            post(keyEvent(type: .keyUp, code: code, flags: [], text: event.characters ?? "", base: event.charactersIgnoringModifiers ?? ""), release: true)
        }
        heldKeys.removeAll()
        for code in heldModifiers { post(keyEvent(type: .flagsChanged, code: code, flags: [], text: "", base: ""), release: true) }
        heldModifiers.removeAll()
    }
}

/// ScreenCaptureKit callback processing stays off the main thread; no frames are saved.
private final class WindowFrameReceiver: NSObject, SCStreamOutput, SCStreamDelegate {
    let queue = DispatchQueue(label: "dev.iphoneduo.window-frames", qos: .userInitiated)
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let frame: (CGImage) -> Void
    private let paused: () -> Void
    private let stopped: (String) -> Void
    init(frame: @escaping (CGImage) -> Void, paused: @escaping () -> Void, stopped: @escaping (String) -> Void) {
        self.frame = frame; self.paused = paused; self.stopped = stopped
    }
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let rawStatus = attachments.first?[.status] as? Int, let status = SCFrameStatus(rawValue: rawStatus) else { return }
        if status == .blank || status == .suspended || status == .stopped { paused(); return }
        guard status == .complete, let buffer = sampleBuffer.imageBuffer else { return }
        let source = CIImage(cvPixelBuffer: buffer)
        if let image = context.createCGImage(source, from: source.extent) { frame(image) }
    }
    func stream(_ stream: SCStream, didStopWithError error: Error) { stopped(error.localizedDescription) }
}

struct RealWindowMonitor: View {
    @ObservedObject var remote: WindowRemoteSession
    var body: some View {
        GeometryReader { geometry in
            let scale = min(geometry.size.width / max(1, remote.sourceSize.width), geometry.size.height / max(1, remote.sourceSize.height))
            let size = CGSize(width: remote.sourceSize.width * scale, height: remote.sourceSize.height * scale)
            ZStack {
                Color.black
                if let image = remote.image {
                    ZStack(alignment: .topLeading) {
                        Image(decorative: image, scale: 1).resizable()
                        Image(systemName: "arrow.up.left")
                            .font(.title2.bold()).foregroundStyle(.white).shadow(color: .black, radius: 1)
                            .position(x: size.width * remote.cursor.x, y: size.height * remote.cursor.y)
                    }
                    .frame(width: size.width, height: size.height)
                    .clipped()
                    .onAppear { remote.displayedSize = size }
                    .onChange(of: size) { _, value in remote.displayedSize = value }
                    .accessibilityLabel("真实窗口画面：\(remote.title)")
                    .accessibilityIdentifier("real-window-monitor")
                } else { ProgressView("正在接收窗口画面…").tint(.white).foregroundStyle(.white) }
                VStack {
                    HStack {
                        Label("真实窗口 · 本机", systemImage: "record.circle").font(.caption2)
                        Spacer()
                    }
                    Spacer()
                    if !remote.inputAllowed {
                        Button { remote.requestInputPermission() } label: { Label("允许控制此窗口", systemImage: "hand.point.up.left") }
                            .buttonStyle(.borderedProminent)
                    } else if !remote.sourceAvailable || remote.capturePaused {
                        Text("目标窗口或画面不可用 · 输入暂停").font(.caption).padding(8).background(.regularMaterial, in: Capsule())
                    }
                }
                .padding(10)
                .foregroundStyle(.white)
            }
        }
    }
}
#endif

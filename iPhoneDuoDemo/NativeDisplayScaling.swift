#if os(macOS)
import Foundation
import CoreGraphics
import ColorSync
import IOKit.graphics

/// Describes a currently enumerated system mode, not a synthesized resolution.
struct NativeDisplayMode: Codable, Equatable, Sendable {
    var id: Int32
    var width: Int
    var height: Int
    var pixelWidth: Int
    var pixelHeight: Int
    var refresh: Double
    var safe: Bool
    var hiDPI: Bool { pixelWidth > width && pixelHeight > height }
    var title: String { "\(width)×\(height) · \(hiDPI ? "HiDPI" : "标准像素") · \(refresh > 0 ? String(format: "%.0f Hz", refresh) : "动态刷新率")" }
    func matches(_ other: Self) -> Bool {
        width == other.width && height == other.height && pixelWidth == other.pixelWidth && pixelHeight == other.pixelHeight && abs(refresh - other.refresh) < 0.1
    }
}
struct NativeDisplaySnapshot: Sendable {
    var uuid: String
    var id: UInt32
    var current: NativeDisplayMode
    var modes: [NativeDisplayMode]
    var restorationSupported = true
    var modeListSummary = ""
}
struct NativeDisplayAccess: Sendable {
    var snapshot: @Sendable (UInt32) async throws -> NativeDisplaySnapshot
    var resolve: @Sendable (String) async throws -> NativeDisplaySnapshot
    var set: @Sendable (String, NativeDisplayMode) async throws -> Void
    var arrangement: DisplayArrangementAccess
    static let live = Self(snapshot: { try NativeDisplaySystem.snapshot($0) }, resolve: { try NativeDisplaySystem.resolve($0) }, set: { uuid, mode in
        try NativeDisplaySystem.set(uuid, mode: mode)
    }, arrangement: .native)
}

enum NativeDisplaySystem {
    /// The default list omits some built-in panel scaling families. Accept a
    /// safe expanded family on a built-in panel, but never infer that an
    /// external active-only custom HiDPI mode will survive a switch.
    static func supportsBaseline(_ current: NativeDisplayMode, standard: [NativeDisplayMode], expanded: [NativeDisplayMode], builtIn: Bool) -> Bool {
        guard current.safe, expanded.contains(where: { $0.safe && $0.matches(current) }) else { return false }
        if standard.contains(where: { $0.safe && $0.matches(current) }) { return true }
        return builtIn && expanded.contains { candidate in
            candidate.safe && candidate.width == current.width && candidate.height == current.height &&
            candidate.pixelWidth == current.pixelWidth && candidate.pixelHeight == current.pixelHeight &&
            abs(candidate.refresh - current.refresh) > 0.1
        }
    }
    static func failure(_ text: String) -> NSError { NSError(domain: "ChordeskDisplay", code: 1, userInfo: [NSLocalizedDescriptionKey: text]) }
    static func activeIDs() throws -> [UInt32] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0, count <= 32 else { throw failure("无法读取活动显示器") }
        var ids = [UInt32](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { throw failure("无法读取活动显示器") }
        return Array(ids.prefix(Int(count)))
    }
    static func uuid(_ id: UInt32) throws -> String {
        guard let value = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { throw failure("无法读取稳定显示器标识") }
        return CFUUIDCreateString(nil, value) as String
    }
    static func mode(_ value: CGDisplayMode) -> NativeDisplayMode {
        let flags = value.ioFlags
        return .init(id: value.ioDisplayModeID, width: value.width, height: value.height,
                     pixelWidth: value.pixelWidth, pixelHeight: value.pixelHeight, refresh: value.refreshRate,
                     safe: value.isUsableForDesktopGUI() && flags & UInt32(kDisplayModeSafeFlag) != 0
                         && flags & UInt32(kDisplayModeInterlacedFlag | kDisplayModeStretchedFlag) == 0)
    }
    static func snapshot(_ id: UInt32) throws -> NativeDisplaySnapshot {
        guard try activeIDs().contains(id), CGDisplayIsInMirrorSet(id) == 0, let current = CGDisplayCopyDisplayMode(id) else {
            throw failure("请使用当前连接的非镜像显示器")
        }
        let list = CGDisplayCopyAllDisplayModes(id, [kCGDisplayShowDuplicateLowResolutionModes: true] as CFDictionary) as? [CGDisplayMode] ?? []
        let standard = CGDisplayCopyAllDisplayModes(id, nil) as? [CGDisplayMode] ?? []
        let expanded = list.map(mode), baseline = mode(current)
        let supported = supportsBaseline(baseline, standard: standard.map(mode), expanded: expanded, builtIn: CGDisplayIsBuiltin(id) != 0)
        return .init(uuid: try uuid(id), id: id, current: baseline, modes: expanded,
                     restorationSupported: supported,
                     modeListSummary: "系统列出 \(expanded.count) 个模式，其中 \(expanded.filter(\.safe).count) 个安全模式。")
    }
    static func resolve(_ uuid: String) throws -> NativeDisplaySnapshot {
        guard UUID(uuidString: uuid) != nil, let id = try activeIDs().first(where: { try self.uuid($0) == uuid }) else {
            throw failure("原显示器暂未连接，恢复记录已保留")
        }
        return try snapshot(id)
    }
    static func set(_ uuid: String, mode desired: NativeDisplayMode) throws {
        let display = try resolve(uuid)
        let list = CGDisplayCopyAllDisplayModes(display.id, [kCGDisplayShowDuplicateLowResolutionModes: true] as CFDictionary) as? [CGDisplayMode] ?? []
        // IDs can change across reconnects. Match the saved geometry and timing too.
        guard let match = list.first(where: { mode($0).safe && mode($0).matches(desired) && $0.ioDisplayModeID == desired.id })
                ?? list.first(where: { mode($0).safe && mode($0).matches(desired) }) else {
            throw failure("系统不再提供该安全显示模式；未创建或强制新档位")
        }
        guard CGDisplaySetDisplayMode(display.id, match, nil) == .success else { throw failure("macOS 未接受显示模式切换；可在主机选择 BetterDisplay 兼容方案") }
    }
    static func placements() throws -> [(DisplayPlacement, UInt32)] {
        try activeIDs().map { id in
            guard CGDisplayIsInMirrorSet(id) == 0 else { throw failure("镜像配置不支持自动调整") }
            let origin = CGDisplayBounds(id).origin
            return (DisplayPlacement(uuid: try uuid(id), x: Int32(origin.x), y: Int32(origin.y)), id)
        }
    }
}

extension DisplayArrangementAccess {
    static let native = Self(capture: { try NativeDisplaySystem.placements().map(\.0) }, restore: { saved in
        let records = try NativeDisplaySystem.placements()
        guard saved.count <= 32, Set(saved.map(\.uuid)).count == saved.count,
              saved.allSatisfy({ item in records.contains { $0.0.uuid == item.uuid } }) else {
            throw NativeDisplaySystem.failure("原排列的显示器未全部连接，恢复记录已保留")
        }
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success else { throw NativeDisplaySystem.failure("无法开始排列恢复") }
        for item in saved {
            guard let record = records.first(where: { $0.0.uuid == item.uuid }),
                  CGConfigureDisplayOrigin(config, record.1, item.x, item.y) == .success else {
                CGCancelDisplayConfiguration(config); throw NativeDisplaySystem.failure("无法恢复显示器位置")
            }
        }
        guard CGCompleteDisplayConfiguration(config, .forSession) == .success else { throw NativeDisplaySystem.failure("系统未接受原排列") }
        for _ in 0..<8 {
            let actual = try NativeDisplaySystem.placements().map(\.0)
            if saved.allSatisfy({ actual.contains($0) }) { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw NativeDisplaySystem.failure("排列尚未恢复，请重试；原记录仍保留")
    })
}

actor NativeDisplayBridge {
    private struct Baseline: Codable {
        var modes: [String: NativeDisplayMode] = [:]
        var layout: [DisplayPlacement] = []
    }
    private let access: NativeDisplayAccess
    private let defaults: UserDefaults
    private var session: Baseline
    private var manual: Baseline
    private var changing = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    init(defaults: UserDefaults = .standard, access: NativeDisplayAccess = .live) {
        self.defaults = defaults; self.access = access
        session = defaults.data(forKey: "ChordeskNativeSessionDisplay").flatMap { try? JSONDecoder().decode(Baseline.self, from: $0) } ?? Baseline()
        manual = defaults.data(forKey: "ChordeskNativeManualDisplay").flatMap { try? JSONDecoder().decode(Baseline.self, from: $0) } ?? Baseline()
    }
    static func presets(_ display: NativeDisplaySnapshot) -> [(String, String, NativeDisplayMode)] {
        let current = display.current, ratio = Double(current.width) / Double(current.height)
        let safe = display.modes.filter { $0.safe && $0.width > 0 && $0.height > 0 && abs(Double($0.width) / Double($0.height) - ratio) < 0.02 }
        func best(_ width: Int) -> NativeDisplayMode? {
            safe.min { a, b in
                let da = abs(a.width - width), db = abs(b.width - width)
                if da != db { return da < db }
                if a.hiDPI != b.hiDPI { return a.hiDPI }
                if abs(a.refresh - current.refresh) != abs(b.refresh - current.refresh) { return abs(a.refresh - current.refresh) < abs(b.refresh - current.refresh) }
                return a.id < b.id
            }
        }
        return [("fit", "默认 1600×900", 1600), ("larger", "更大文字", 1024), ("largest", "最大文字", 800), ("space", "更多空间", 1920)].compactMap { id, title, width in
            guard let mode = best(width) else { return nil }
            let name = id == "fit" && (mode.width != 1600 || mode.height != 900) ? "接近 1600 宽（保持比例）" : title
            return (id, name, mode)
        }
    }
    func state(displayID: UInt32) async throws -> LANScaleState {
        let display = try await access.snapshot(displayID)
        let canReturn = display.restorationSupported || session.modes[display.uuid] != nil || manual.modes[display.uuid] != nil
        let options = canReturn ? Self.presets(display) : []
        let fit = options.first { $0.0 == "fit" }?.2
        return .init(displayID: displayID, current: display.current.title,
            options: options.map { .init(id: $0.0, title: $0.1, detail: $0.2.title) },
            canRestore: session.modes[display.uuid] != nil || manual.modes[display.uuid] != nil, canAdjust: false,
            message: (!canReturn ? "当前模式的恢复条件未满足，暂不改动屏幕。可先在 macOS 显示设置选系统默认分辨率再刷新；自定义 HiDPI 可用 BetterDisplay 兼容方案。" : options.isEmpty ? "系统没有提供同画幅的安全档位；保留当前模式。可检查显示器是否镜像，或在 macOS 显示设置选择默认分辨率后刷新。" :
                fit?.width == 1600 && fit?.height == 900 ? "内置模式切换 · 默认 1600×900；不需要 BetterDisplay。" : "系统未提供同画幅 1600×900，使用最接近 1600 宽的安全模式；不拉伸画面。") + " " + display.modeListSummary)
    }
    func apply(displayID: UInt32, choice: String, sessionScoped: Bool = false) async throws {
        await acquire(); defer { release() }
        let display = try await access.snapshot(displayID)
        let target: NativeDisplayMode
        if choice == "restore" {
            guard let original = session.modes[display.uuid] ?? manual.modes[display.uuid] else { throw NativeDisplaySystem.failure("没有需要恢复的内置模式记录") }
            target = original
        } else {
            guard display.restorationSupported || session.modes[display.uuid] != nil || manual.modes[display.uuid] != nil else {
                throw NativeDisplaySystem.failure("当前模式无法确认可恢复，尚未修改屏幕；请使用 BetterDisplay 兼容方案")
            }
            guard let preset = Self.presets(display).first(where: { $0.0 == choice }) else { throw NativeDisplaySystem.failure("该系统模式不可用，请刷新；可改用兼容方案") }
            target = preset.2
        }
        let useSession = sessionScoped || session.modes[display.uuid] != nil
        if choice != "restore" {
            if useSession && session.modes[display.uuid] == nil {
                if session.layout.isEmpty { session.layout = try await access.arrangement.capture() }
                session.modes[display.uuid] = display.current
            } else if !useSession && manual.modes[display.uuid] == nil {
                if manual.layout.isEmpty { manual.layout = try await access.arrangement.capture() }
                manual.modes[display.uuid] = display.current
            }
            persist() // Before any mutation, including a failing or interrupted switch.
        }
        try await setAndVerify(display.uuid, target)
        let layout = useSession ? session.layout : manual.layout
        // Smaller screens may need new origins to remain edge-adjacent. macOS
        // normalizes gaps, so restore exact origins only after original sizes.
        if choice == "restore" && !layout.isEmpty { try await access.arrangement.restore(layout) }
        if choice == "restore" && !useSession {
            manual.modes.removeValue(forKey: display.uuid)
            if manual.modes.isEmpty { manual.layout = [] }
            persist()
        }
    }
    func restoreSessionModes() async -> [String] {
        await acquire(); defer { release() }
        var errors: [String] = []
        for (uuid, mode) in session.modes.sorted(by: { $0.key < $1.key }) {
            do { try await setAndVerify(uuid, mode) } catch { errors.append(error.localizedDescription) }
        }
        if errors.isEmpty && !session.layout.isEmpty {
            do { try await access.arrangement.restore(session.layout) } catch { errors.append(error.localizedDescription) }
        }
        // Retain the complete baseline until every mode and the arrangement match.
        if errors.isEmpty { session = Baseline(); persist() }
        return errors
    }
    private func setAndVerify(_ uuid: String, _ mode: NativeDisplayMode) async throws {
        let current = try await access.resolve(uuid)
        guard current.modes.contains(where: { $0.safe && $0.matches(mode) }) else { throw NativeDisplaySystem.failure("原安全模式暂不可用，恢复记录已保留") }
        if current.current.matches(mode) { return }
        try await access.set(uuid, mode)
        for _ in 0..<8 {
            if try await access.resolve(uuid).current.matches(mode) { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw NativeDisplaySystem.failure("模式切换尚未确认，记录已保留")
    }
    private func persist() {
        for (key, value) in [("ChordeskNativeSessionDisplay", session), ("ChordeskNativeManualDisplay", manual)] {
            if value.modes.isEmpty && value.layout.isEmpty { defaults.removeObject(forKey: key) }
            else if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
        }
    }
    private func acquire() async {
        if changing { await withCheckedContinuation { waiters.append($0) } } else { changing = true }
    }
    private func release() {
        if waiters.isEmpty { changing = false } else { waiters.removeFirst().resume() }
    }
}

enum DisplayScalingBackend: String, CaseIterable {
    case native, betterDisplay
    var title: String { self == .native ? "内置（无需额外软件）" : "BetterDisplay（兼容回退）" }
}
struct DisplayScalingService {
    private let native = NativeDisplayBridge()
    private let legacy = BetterDisplayBridge()
    func state(displayID: UInt32, backend: DisplayScalingBackend) async throws -> LANScaleState {
        if backend == .native { return try await native.state(displayID: displayID) }
        return try await legacy.state(displayID: displayID)
    }
    func apply(displayID: UInt32, choice: String, sessionScoped: Bool, backend: DisplayScalingBackend) async throws {
        if backend == .native { try await native.apply(displayID: displayID, choice: choice, sessionScoped: sessionScoped) }
        else { try await legacy.apply(displayID: displayID, choice: choice, sessionScoped: sessionScoped) }
    }
    func restoreSessionModes() async -> [String] {
        // Old CLI journals are retained across upgrade. New native journals never
        // overwrite them; backend selection is locked while a session is active.
        let old = await legacy.restoreSessionModes()
        guard old.isEmpty else { return old }
        return await native.restoreSessionModes()
    }
}
#endif

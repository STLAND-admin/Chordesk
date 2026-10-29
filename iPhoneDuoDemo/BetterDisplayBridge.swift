#if os(macOS)
import Foundation
import CoreGraphics

/// Uses BetterDisplay's documented local CLI. No shell, HTTP listener, private display API,
/// virtual display creation, or arbitrary commands received from a phone.
struct DisplayPlacement: Codable, Equatable {
    var uuid: String
    var x: Int32
    var y: Int32
}

struct DisplayArrangementAccess: Sendable {
    var capture: @Sendable () async throws -> [DisplayPlacement]
    var restore: @Sendable ([DisplayPlacement]) async throws -> Void
    static let none = Self(capture: { [] }, restore: { _ in })
    static let live = Self(capture: { try await current() }, restore: { saved in
        let records = try await currentRecords()
        guard saved.count <= 32, Set(saved.map(\.uuid)).count == saved.count,
              saved.allSatisfy({ record in records.contains(where: { $0.0.uuid == record.uuid }) }) else {
            throw failure("原排列中的显示器暂未全部连接，恢复记录已保留")
        }
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success else { throw failure("无法开始恢复显示器排列") }
        for item in saved {
            guard let record = records.first(where: { $0.0.uuid == item.uuid }),
                  CGConfigureDisplayOrigin(config, record.1, item.x, item.y) == .success else {
                CGCancelDisplayConfiguration(config); throw failure("无法恢复显示器位置")
            }
        }
        guard CGCompleteDisplayConfiguration(config, .forSession) == .success else { throw failure("系统未接受原显示器排列") }
        for _ in 0..<8 {
            let actual = try await current()
            if saved.allSatisfy({ actual.contains($0) }) { return }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        throw failure("显示器排列尚未恢复，记录已保留，请重试")
    })
    private static func current() async throws -> [DisplayPlacement] { try await currentRecords().map(\.0) }
    private static func currentRecords() async throws -> [(DisplayPlacement, UInt32)] {
        let output = try await BetterDisplayBridge.run(["get", "-identifiers"]).trimmingCharacters(in: .whitespacesAndNewlines)
        let json = output.hasPrefix("[") ? output : "[\(output)]"
        guard let data = json.data(using: .utf8), let records = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw failure("无法读取稳定的显示器标识")
        }
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success else { throw failure("无法读取显示器排列") }
        var ids = [UInt32](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { throw failure("无法读取显示器排列") }
        return try ids.prefix(Int(count)).map { id in
            guard CGDisplayMirrorsDisplay(id) == kCGNullDirectDisplay,
                  let record = records.first(where: { String(describing: $0["displayID"] ?? "") == String(id) }),
                  let uuid = record["UUID"] as? String, UUID(uuidString: uuid) != nil else {
                throw failure("当前镜像显示配置不支持自动调整；请先使用扩展显示")
            }
            let origin = CGDisplayBounds(id).origin
            return (DisplayPlacement(uuid: uuid, x: Int32(origin.x), y: Int32(origin.y)), id)
        }
    }
    private static func failure(_ text: String) -> NSError { NSError(domain: "DuoDisplayLayout", code: 1, userInfo: [NSLocalizedDescriptionKey: text]) }
}

actor BetterDisplayBridge {
    private struct Mode {
        let number: Int
        let width: Int
        let height: Int
        let signature: String
        let current: Bool
        let hiDPI: Bool
        let unsafe: Bool
    }
    private struct Display {
        let id: UInt32
        let uuid: String
    }
    private let defaults: UserDefaults
    private let command: @Sendable ([String]) async throws -> String
    private var originals: [String: String]
    private var sessionOriginals: [String: String]
    private let arrangement: DisplayArrangementAccess
    private var sessionLayout: [DisplayPlacement]?
    private var manualLayout: [DisplayPlacement]?
    private var changing = false
    private var changeWaiters: [CheckedContinuation<Void, Never>] = []

    init(defaults: UserDefaults = .standard, arrangement: DisplayArrangementAccess = .live,
         command: @escaping @Sendable ([String]) async throws -> String = { try await BetterDisplayBridge.run($0) }) {
        self.defaults = defaults; self.command = command; self.arrangement = arrangement
        sessionLayout = defaults.data(forKey: "DuoSessionDisplayLayout").flatMap { try? JSONDecoder().decode([DisplayPlacement].self, from: $0) }
        manualLayout = defaults.data(forKey: "DuoManualDisplayLayout").flatMap { try? JSONDecoder().decode([DisplayPlacement].self, from: $0) }
        originals = defaults.dictionary(forKey: "DuoOriginalDisplayModes") as? [String: String] ?? [:]
        sessionOriginals = defaults.dictionary(forKey: "DuoSessionDisplayModes") as? [String: String] ?? [:]
    }
    private static let executable = "/Applications/BetterDisplay.app/Contents/MacOS/BetterDisplay"

    func state(displayID: UInt32) async throws -> LANScaleState {
        let display = try await physicalDisplay(displayID)
        let modes = try await modes(display)
        guard let current = modes.first(where: \.current) else { throw failure("无法读取当前显示模式") }
        let choices = presets(modes, current: current)
        return LANScaleState(displayID: displayID, current: current.signature,
            options: choices.map { LANScaleOption(id: $0.0, title: $0.1, detail: $0.2.signature) },
            canRestore: sessionOriginals[display.uuid] != nil || originals[display.uuid] != nil, canAdjust: false,
            message: choices.isEmpty ? "该屏暂无可用的 HiDPI 缩放档位，请先在 BetterDisplay 配置" : "调整实体屏的逻辑分辨率；Mac 本机也会同步改变文字大小")
    }

    func apply(displayID: UInt32, choice: String, sessionScoped: Bool = false) async throws {
        await acquireChange()
        defer { releaseChange() }
        let display = try await physicalDisplay(displayID)
        let available = try await modes(display)
        guard let current = available.first(where: \.current) else { throw failure("无法读取当前显示模式") }
        if sessionScoped && sessionLayout == nil {
            sessionLayout = try await arrangement.capture()
            defaults.set(try JSONEncoder().encode(sessionLayout), forKey: "DuoSessionDisplayLayout")
        } else if !sessionScoped && choice != "restore" && manualLayout == nil {
            manualLayout = try await arrangement.capture()
            defaults.set(try JSONEncoder().encode(manualLayout), forKey: "DuoManualDisplayLayout")
        }
        if sessionScoped && sessionOriginals[display.uuid] == nil {
            sessionOriginals[display.uuid] = current.signature
            saveSessionOriginals()
        }
        let desired: Mode
        if choice == "restore" {
            guard let original = sessionOriginals[display.uuid] ?? originals[display.uuid], let match = available.first(where: { $0.signature == original }) else {
                throw failure("原显示模式暂不可用；恢复记录已保留，请在 BetterDisplay 检查该屏")
            }
            desired = match
        } else {
            guard let preset = presets(available, current: current).first(where: { $0.0 == choice }) else {
                throw failure("该缩放档位不可用，请刷新列表")
            }
            desired = preset.2
            if desired.signature == current.signature { return }
            if !sessionScoped && originals[display.uuid] == nil {
                originals[display.uuid] = current.signature
                saveOriginals()
            }
        }
        try await setMode(desired, display: display)
        if choice == "restore" && sessionOriginals[display.uuid] == nil {
            if originals.keys.filter({ $0 != display.uuid }).isEmpty, let layout = manualLayout {
                try await arrangement.restore(layout)
                manualLayout = nil; defaults.removeObject(forKey: "DuoManualDisplayLayout")
            }
            originals.removeValue(forKey: display.uuid); saveOriginals()
        }
    }

    /// Serializes against an in-flight fit/change. Keep failed records for retry on
    /// the next launch; a reconnect must never replace the pre-session baseline.
    func restoreSessionModes() async -> [String] {
        await acquireChange()
        defer { releaseChange() }
        var errors: [String] = []
        for (uuid, signature) in sessionOriginals.sorted(by: { $0.key < $1.key }) {
            do {
                guard UUID(uuidString: uuid) != nil else { throw failure("恢复记录中的显示器标识无效") }
                let display = Display(id: 0, uuid: uuid)
                let available = try await modes(display)
                guard let original = available.first(where: { $0.signature == signature && !$0.unsafe }) else {
                    throw failure("连接前的显示模式暂不可用，恢复记录已保留")
                }
                try await setMode(original, display: display)
                sessionOriginals.removeValue(forKey: uuid); saveSessionOriginals()
            } catch { errors.append(error.localizedDescription) }
        }
        if errors.isEmpty, let layout = sessionLayout {
            do {
                try await arrangement.restore(layout)
                sessionLayout = nil; defaults.removeObject(forKey: "DuoSessionDisplayLayout")
            } catch { errors.append(error.localizedDescription) }
        }
        return errors
    }

    private func setMode(_ desired: Mode, display: Display) async throws {
        if try await modes(display).first(where: \.current)?.signature == desired.signature { return }
        _ = try await command(["set", "-UUID=\(display.uuid)", "-displayModeNumber=\(desired.number)"])
        for _ in 0..<5 {
            if try await modes(display).first(where: \.current)?.signature == desired.signature { return }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        throw failure("BetterDisplay 未切到所选模式；原记录已保留，可重试恢复")
    }

    private func acquireChange() async {
        if changing { await withCheckedContinuation { changeWaiters.append($0) } }
        else { changing = true }
    }
    private func releaseChange() {
        if changeWaiters.isEmpty { changing = false }
        else { changeWaiters.removeFirst().resume() }
    }
    private func saveOriginals() { defaults.set(originals, forKey: "DuoOriginalDisplayModes") }
    private func saveSessionOriginals() { defaults.set(sessionOriginals, forKey: "DuoSessionDisplayModes") }

    private func physicalDisplay(_ id: UInt32) async throws -> Display {
        let output = try await command(["get", "-identifiers"])
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        let json = trimmed.hasPrefix("[") ? trimmed : "[\(trimmed)]"
        guard let data = json.data(using: .utf8),
              let records = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let record = records.first(where: { String(describing: $0["displayID"] ?? "") == String(id) }),
              record["deviceType"] as? String == "Display",
              let uuid = record["UUID"] as? String, UUID(uuidString: uuid) != nil else {
            throw failure("请选择 BetterDisplay 当前识别的实体显示器；不需要虚拟屏")
        }
        return Display(id: id, uuid: uuid)
    }

    private func modes(_ display: Display) async throws -> [Mode] {
        let output = try await command(["get", "-UUID=\(display.uuid)", "-displayModeList"])
        let pattern = try NSRegularExpression(pattern: #"^\s*(\d+)\s+-\s+(\d+)x(\d+)\s+(.+)$"#)
        let result = output.split(whereSeparator: \.isNewline).compactMap { line -> Mode? in
            let text = String(line)
            guard let match = pattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
            func part(_ n: Int) -> String { Range(match.range(at: n), in: text).map { String(text[$0]) } ?? "" }
            guard let number = Int(part(1)), let width = Int(part(2)), let height = Int(part(3)), width > 0, height > 0 else { return nil }
            let flags = part(4).split(whereSeparator: \.isWhitespace).map(String.init)
            let details = flags.filter { !["Current", "Default", "Native", "Unsafe"].contains($0) }.joined(separator: " ")
            return Mode(number: number, width: width, height: height, signature: "\(width)x\(height) \(details)",
                        current: flags.contains("Current"), hiDPI: flags.contains("HiDPI"), unsafe: flags.contains("Unsafe"))
        }
        guard !result.isEmpty else { throw failure("BetterDisplay 未返回可识别的显示模式；请确认命令行集成已启用") }
        return result
    }

    private func presets(_ modes: [Mode], current: Mode) -> [(String, String, Mode)] {
        let ratio = Double(current.width) / Double(current.height)
        let candidates = modes.filter { $0.hiDPI && !$0.unsafe && abs(Double($0.width) / Double($0.height) - ratio) < 0.02 }
        let timing = current.signature.split(separator: " ").filter { $0.contains("Hz") || $0 == "ProMotion" }.first
        func score(_ mode: Mode, target: Int) -> Double {
            Double(abs(mode.width - target)) + (timing.map { mode.signature.contains(String($0)) } == true ? 0 : 0.5)
        }
        return [("fit", "默认 1600 宽", 1600), ("larger", "更大文字", 800), ("largest", "最大文字", 640), ("space", "更多空间", 1600)].compactMap { id, name, width in
            guard let mode = candidates.min(by: { score($0, target: width) < score($1, target: width) }) else { return nil }
            return (id, name, mode)
        }
    }

    private func failure(_ message: String) -> NSError {
        NSError(domain: "DuoBetterDisplay", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    fileprivate static func run(_ arguments: [String]) async throws -> String {
        try await Task.detached(priority: .userInitiated) { try runSynchronous(arguments) }.value
    }

    private static func runSynchronous(_ arguments: [String]) throws -> String {
            guard FileManager.default.isExecutableFile(atPath: executable) else {
                throw NSError(domain: "DuoBetterDisplay", code: 2, userInfo: [NSLocalizedDescriptionKey: "请先在应用程序目录安装并打开 BetterDisplay"])
            }
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("duo-display-\(UUID().uuidString).log")
            FileManager.default.createFile(atPath: file.path, contents: nil)
            let output = try FileHandle(forWritingTo: file)
            defer { try? output.close(); try? FileManager.default.removeItem(at: file) }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.standardOutput = output; process.standardError = output
            let exited = DispatchSemaphore(value: 0)
            process.terminationHandler = { _ in exited.signal() }
            try process.run()
            guard exited.wait(timeout: .now() + 8) == .success else {
                process.terminate()
                throw NSError(domain: "DuoBetterDisplay", code: 3, userInfo: [NSLocalizedDescriptionKey: "BetterDisplay 响应超时；请确认应用运行且命令行集成开启"])
            }
            let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.intValue ?? 0
            guard size <= 512 * 1024 else { throw NSError(domain: "DuoBetterDisplay", code: 4, userInfo: [NSLocalizedDescriptionKey: "显示模式列表超过大小限制"] ) }
            let text = String(decoding: try Data(contentsOf: file), as: UTF8.self).replacingOccurrences(of: "\0", with: "")
            guard process.terminationStatus == 0 else {
                throw NSError(domain: "DuoBetterDisplay", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "BetterDisplay：\(text.prefix(180))"])
            }
            return text
    }
}
#endif

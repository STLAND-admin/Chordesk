#if os(macOS)
import AppKit
import Carbon

/// Public System Events scripting dictionary: prcs/kcod, faal, Kctl.
/// Build descriptors directly: no shell, AppleScript source, arbitrary key or target
/// supplied by a phone. Ordinary remote keyboard/mouse events keep private state.
struct DesktopSwitchCommand {
    let keyCode: Int32
    init?(_ action: WindowOverviewAction) {
        switch action {
        case .previousDesktop: keyCode = 123
        case .nextDesktop: keyCode = 124
        default: return nil
        }
    }
    static let targetID = "com.apple.systemevents"
    static let eventClass: AEEventClass = 0x70726373 // prcs
    static let eventID: AEEventID = 0x6b636f64 // kcod
    static let usingKeyword: AEKeyword = 0x6661616c // faal
    static let controlDown: OSType = 0x4b63746c // Kctl
    static var target: NSAppleEventDescriptor { NSAppleEventDescriptor(bundleIdentifier: targetID) }
    func descriptor() -> NSAppleEventDescriptor {
        let event = NSAppleEventDescriptor(eventClass: Self.eventClass, eventID: Self.eventID,
            targetDescriptor: Self.target, returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        event.setParam(NSAppleEventDescriptor(int32: keyCode), forKeyword: keyDirectObject)
        let modifiers = NSAppleEventDescriptor.list()
        modifiers.insert(NSAppleEventDescriptor(enumCode: Self.controlDown), at: 1)
        event.setParam(modifiers, forKeyword: Self.usingKeyword)
        return event
    }
    static func permission(ask: Bool = false) -> OSStatus {
        AEDeterminePermissionToAutomateTarget(target.aeDesc, eventClass, eventID, ask)
    }
}

enum DesktopSwitchResult: Equatable {
    case submitted, permissionRequired, cancelled, failed(Int)
    static func error(_ code: Int) -> Self {
        [-1743, -1744].contains(code) ? .permissionRequired : .failed(code)
    }
    var message: String {
        switch self {
        case .submitted: "桌面指令已交给 System Events；效果以屏幕为准"
        case .permissionRequired: "切换桌面需要在 Mac 的 Chordesk 设置 → 桌面切换，允许控制 System Events"
        case .cancelled: "会话或控制状态已改变，取消桌面切换"
        case .failed(let code): "桌面切换未确认（系统错误 \(code)）；不会自动重试，请检查系统快捷键后重试"
        }
    }
}

@MainActor
enum DesktopSwitcher {
    static func prepare() async throws {
        guard NSRunningApplication.runningApplications(withBundleIdentifier: DesktopSwitchCommand.targetID).isEmpty else { return }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: DesktopSwitchCommand.targetID) else {
            throw NSError(domain: NSOSStatusErrorDomain, code: -600)
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }
    /// Called ONLY by a local permission button, never by remote input. Permission
    /// consent must not block the main run loop or replay the previous remote action.
    static func requestPermission() async -> OSStatus {
        do { try await prepare() } catch { return OSStatus((error as NSError).code) }
        return await Task.detached(priority: .userInitiated) { DesktopSwitchCommand.permission(ask: true) }.value
    }
    static func perform(_ action: WindowOverviewAction, isCurrent: () -> Bool) async -> DesktopSwitchResult {
        guard let command = DesktopSwitchCommand(action), isCurrent() else { return .cancelled }
        do { try await prepare() } catch { return .failed((error as NSError).code) }
        return submit(command, isCurrent: isCurrent,
            permission: { DesktopSwitchCommand.permission() },
            send: { event in
                let reply = try event.sendEvent(options: [.waitForReply, .neverInteract, .dontRecord], timeout: 2)
                return Int(reply.paramDescriptor(forKeyword: keyErrorNumber)?.int32Value ?? 0)
            })
    }
    /// No suspension between the final session guard and dispatch. The OS call is
    /// bounded to two seconds; a timeout is unconfirmed, never retried (no double switch).
    static func submit(_ command: DesktopSwitchCommand, isCurrent: () -> Bool,
                       permission: () -> OSStatus,
                       send: (NSAppleEventDescriptor) throws -> Int) -> DesktopSwitchResult {
        guard isCurrent() else { return .cancelled }
        let access = permission()
        guard access == noErr else { return .error(Int(access)) }
        guard isCurrent() else { return .cancelled }
        do {
            let result = try send(command.descriptor())
            return result == 0 ? .submitted : .error(result)
        } catch { return .error((error as NSError).code) }
    }
}
#endif

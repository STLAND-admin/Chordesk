import Foundation
import CoreGraphics

/// A paused stream can restore the same authorization, but never one revoked later.
struct CaptureRecovery {
    private(set) var paused = false
    private var authorizedRevision: Int?
    mutating func pause(allowed: Bool, revision: Int) {
        guard !paused else { return }
        paused = true; authorizedRevision = allowed ? revision : nil
    }
    mutating func invalidate() { authorizedRevision = nil }
    mutating func receivedFrame(revision: Int, eligible: Bool) -> Bool {
        let resume = paused && authorizedRevision == revision && eligible
        self = CaptureRecovery()
        return resume
    }
}

#if os(macOS)
import IOKit.pwr_mgt

/// Only a running shared host keeps the system awake. Displays may still sleep.
final class HostAwakeLease {
    private var token: NSObjectProtocol?
    private let begin: () -> NSObjectProtocol
    private let end: (NSObjectProtocol) -> Void
    init(begin: @escaping () -> NSObjectProtocol = {
        ProcessInfo.processInfo.beginActivity(options: [.idleSystemSleepDisabled], reason: "Duo remote host is available")
    }, end: @escaping (NSObjectProtocol) -> Void = { ProcessInfo.processInfo.endActivity($0) }) {
        self.begin = begin; self.end = end
    }
    func update(sharing: Bool, enabled: Bool) {
        if sharing && enabled {
            if token == nil { token = begin() }
        } else if let old = token { token = nil; end(old) }
    }
    deinit { if let token { end(token) } }
}
#endif

/// Display preference is based on public display properties, not names or model IDs.
enum DefaultHostDisplay {
    static func choose(_ ids: [UInt32], builtIn: (UInt32) -> Bool, main: UInt32) -> UInt32? {
        ids.first(where: builtIn) ?? ids.first(where: { $0 == main }) ?? ids.first
    }
}
struct DisplayWakeGate {
    private var last = -Double.infinity
    mutating func claim(authenticated: Bool, enabled: Bool, now: Double) -> Bool {
        guard authenticated, enabled, now.isFinite, now - last >= 5 else { return false }
        last = now; return true
    }
}
enum CaptureRestartDecision {
    static func permits(isCaptureError: Bool, code: Int, screenPermission: Bool, displayOnline: Bool = true) -> Bool {
        screenPermission && isCaptureError && ([-3804, -3805, -3811].contains(code)
            || (displayOnline && [-3813, -3814, -3815].contains(code)))
    }
}
#if os(macOS)
final class AuthenticatedDisplayWake {
    private var gate = DisplayWakeGate()
    private var assertion: IOPMAssertionID = 0
    @discardableResult
    func request(authenticated: Bool, enabled: Bool) -> Bool {
        let now = ProcessInfo.processInfo.systemUptime
        guard gate.claim(authenticated: authenticated, enabled: enabled, now: now) else { return false }
        return IOPMAssertionDeclareUserActivity("Chordesk paired remote connection" as CFString,
            kIOPMUserActiveRemote, &assertion) == kIOReturnSuccess
    }
}
#endif

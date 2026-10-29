import XCTest
import Carbon
@testable import DuoWorkbench

final class DesktopSwitchTests: XCTestCase {
    func testOnlyTwoFixedDirectionsReachTheSystemEventsDictionary() throws {
        XCTAssertNil(DesktopSwitchCommand(.show)); XCTAssertNil(DesktopSwitchCommand(.hide))
        for (action, code): (WindowOverviewAction, Int32) in [(.previousDesktop, 123), (.nextDesktop, 124)] {
            let command = try XCTUnwrap(DesktopSwitchCommand(action))
            let event = command.descriptor()
            XCTAssertEqual(event.eventClass, DesktopSwitchCommand.eventClass)
            XCTAssertEqual(event.eventID, DesktopSwitchCommand.eventID)
            XCTAssertEqual(event.paramDescriptor(forKeyword: keyDirectObject)?.int32Value, code)
            let modifiers = try XCTUnwrap(event.paramDescriptor(forKeyword: DesktopSwitchCommand.usingKeyword))
            XCTAssertEqual(modifiers.numberOfItems, 1)
            XCTAssertEqual(modifiers.atIndex(1)?.enumCodeValue, DesktopSwitchCommand.controlDown)
            XCTAssertEqual(String(data: try XCTUnwrap(event.attributeDescriptor(forKeyword: keyAddressAttr)?.data), encoding: .utf8), "com.apple.systemevents")
        }
    }
    @MainActor
    func testMissingPermissionDoesNotDispatchOrReplay() throws {
        let command = try XCTUnwrap(DesktopSwitchCommand(.nextDesktop))
        for denial: OSStatus in [-1743, -1744] {
            var sent = 0
            let result = DesktopSwitcher.submit(command, isCurrent: { true }, permission: { denial }, send: { _ in sent += 1; return 0 })
            XCTAssertEqual(result, .permissionRequired); XCTAssertEqual(sent, 0)
        }
    }
    @MainActor
    func testSessionRevokedDuringPreflightCannotSend() throws {
        let command = try XCTUnwrap(DesktopSwitchCommand(.nextDesktop))
        var current = true, sent = false
        let result = DesktopSwitcher.submit(command, isCurrent: { current }, permission: { current = false; return 0 }, send: { _ in sent = true; return 0 })
        XCTAssertEqual(result, .cancelled); XCTAssertFalse(sent)
        XCTAssertEqual(DesktopSwitcher.submit(command, isCurrent: { false }, permission: { XCTFail("stale command should stop before permission query"); return 0 }, send: { _ in XCTFail("stale command posted"); return 0 }), .cancelled)
    }
    @MainActor
    func testTimeoutAndOSReplyErrorNeverAcknowledgeSuccessOrRetry() throws {
        let command = try XCTUnwrap(DesktopSwitchCommand(.previousDesktop))
        var sends = 0
        let timeout = DesktopSwitcher.submit(command, isCurrent: { true }, permission: { 0 }, send: { _ in
            sends += 1; throw NSError(domain: NSOSStatusErrorDomain, code: -1712)
        })
        XCTAssertEqual(timeout, .failed(-1712)); XCTAssertEqual(sends, 1)
        XCTAssertEqual(DesktopSwitcher.submit(command, isCurrent: { true }, permission: { 0 }, send: { _ in -1743 }), .permissionRequired)
        XCTAssertEqual(DesktopSwitcher.submit(command, isCurrent: { true }, permission: { 0 }, send: { _ in -10004 }), .failed(-10004))
        XCTAssertEqual(DesktopSwitcher.submit(command, isCurrent: { true }, permission: { 0 }, send: { _ in 0 }), .submitted)
    }
}

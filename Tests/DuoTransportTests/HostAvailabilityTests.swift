import XCTest
@testable import DuoWorkbench

final class HostAvailabilityTests: XCTestCase {
    func testNetworkLeaseRequiresAuthenticatedViewerACAndOptIn() {
        var starts = 0, ends = 0
        let lease = HostNetworkLease(begin: { starts += 1; return 42 }, end: { _ in ends += 1 })
        lease.update(viewerActive: false, enabled: true, onACPower: true, now: 0)
        lease.update(viewerActive: true, enabled: false, onACPower: true, now: 0)
        lease.update(viewerActive: true, enabled: true, onACPower: false, now: 0)
        XCTAssertEqual(starts, 0)
        lease.update(viewerActive: true, enabled: true, onACPower: true, now: 1)
        lease.update(viewerActive: true, enabled: true, onACPower: true, now: 2)
        XCTAssertEqual(starts, 1); XCTAssertTrue(lease.active)
        lease.update(viewerActive: true, enabled: true, onACPower: false, now: 3)
        XCTAssertEqual(ends, 1); XCTAssertFalse(lease.active)
        lease.update(viewerActive: true, enabled: true, onACPower: true, now: 4)
        lease.update(viewerActive: false, enabled: true, onACPower: true, now: 5)
        lease.update(viewerActive: false, enabled: true, onACPower: true, now: 6)
        XCTAssertEqual(starts, 2); XCTAssertEqual(ends, 2)
    }
    func testFailedNetworkLeaseIsRateLimitedAndTeardownReleasesIt() {
        var starts = 0, ends = 0
        var lease: HostNetworkLease? = HostNetworkLease(begin: { starts += 1; return starts == 1 ? nil : 7 }, end: { _ in ends += 1 })
        lease?.update(viewerActive: true, enabled: true, onACPower: true, now: 0)
        lease?.update(viewerActive: true, enabled: true, onACPower: true, now: 1)
        XCTAssertEqual(starts, 1)
        lease?.update(viewerActive: true, enabled: true, onACPower: true, now: 15)
        XCTAssertEqual(starts, 2); XCTAssertTrue(lease?.active == true)
        lease = nil
        XCTAssertEqual(ends, 1)
    }
    func testAbsentDisplayWaitsAndReturningSourceTriggersOneRecovery() {
        var presence = HostDisplayPresence()
        XCTAssertEqual(presence.update(online: true), .none)
        XCTAssertEqual(presence.update(online: false), .disappeared)
        XCTAssertEqual(presence.update(online: false), .none)
        XCTAssertEqual(presence.update(online: true), .returned)
        XCTAssertEqual(presence.update(online: true), .none)
        for code in [-3813, -3814, -3815] {
            XCTAssertTrue(CaptureRestartDecision.waitsForDisplay(isCaptureError: true, code: code, screenPermission: true, displayOnline: false))
            XCTAssertFalse(CaptureRestartDecision.waitsForDisplay(isCaptureError: true, code: code, screenPermission: false, displayOnline: false))
            XCTAssertFalse(CaptureRestartDecision.waitsForDisplay(isCaptureError: true, code: code, screenPermission: true, displayOnline: true))
        }
        // User stop, system stop and denied permission retain their stop boundary.
        for code in [-3801, -3817, -3821] {
            XCTAssertFalse(CaptureRestartDecision.waitsForDisplay(isCaptureError: true, code: code, screenPermission: true, displayOnline: false))
        }
        XCTAssertFalse(CaptureRestartDecision.waitsForDisplay(isCaptureError: false, code: -3814, screenPermission: true, displayOnline: false))
    }
    func testFreshFrameResumesOnlyTheOriginalAuthorizationOnce() {
        var recovery = CaptureRecovery()
        recovery.pause(allowed: true, revision: 4)
        recovery.pause(allowed: false, revision: 4)
        XCTAssertTrue(recovery.receivedFrame(revision: 4, eligible: true))
        XCTAssertFalse(recovery.receivedFrame(revision: 4, eligible: true))
    }
    func testManualRevokeWhilePausedCannotBeUndoneByFrame() {
        var recovery = CaptureRecovery()
        recovery.pause(allowed: true, revision: 4)
        recovery.invalidate()
        XCTAssertFalse(recovery.receivedFrame(revision: 4, eligible: true))
    }
    func testNewSessionOrPermissionsCannotReuseOldAuthorization() {
        var recovery = CaptureRecovery()
        recovery.pause(allowed: true, revision: 4)
        XCTAssertFalse(recovery.receivedFrame(revision: 5, eligible: true))
        recovery.pause(allowed: true, revision: 5)
        XCTAssertFalse(recovery.receivedFrame(revision: 5, eligible: false))
    }
    func testViewOnlyStreamDoesNotGainControlOnResume() {
        var recovery = CaptureRecovery()
        recovery.pause(allowed: false, revision: 0)
        XCTAssertFalse(recovery.receivedFrame(revision: 0, eligible: true))
    }
    func testAwakeLeaseExistsOnlyWhileSharingAndEnabled() {
        var starts = 0, ends = 0
        let lease = HostAwakeLease(begin: { starts += 1; return NSObject() }, end: { _ in ends += 1 })
        lease.update(sharing: false, enabled: true)
        XCTAssertEqual(starts, 0)
        lease.update(sharing: true, enabled: true)
        lease.update(sharing: true, enabled: true)
        XCTAssertEqual(starts, 1)
        lease.update(sharing: true, enabled: false)
        XCTAssertEqual(ends, 1)
        lease.update(sharing: true, enabled: true)
        lease.update(sharing: false, enabled: true)
        XCTAssertEqual(starts, 2); XCTAssertEqual(ends, 2)
    }
    func testAwakeLeaseReleasesOnTeardown() {
        var ends = 0
        var lease: HostAwakeLease? = HostAwakeLease(begin: { NSObject() }, end: { _ in ends += 1 })
        lease?.update(sharing: true, enabled: true)
        lease = nil
        XCTAssertEqual(ends, 1)
    }
}

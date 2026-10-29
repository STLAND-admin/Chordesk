import XCTest
@testable import DuoWorkbench

final class HostAvailabilityTests: XCTestCase {
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

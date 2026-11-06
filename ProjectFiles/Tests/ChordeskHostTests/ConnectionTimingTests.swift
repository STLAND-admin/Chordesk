import XCTest
@testable import ChordeskHost

final class ConnectionTimingTests: XCTestCase {
    func testPublicRouteOfferSurvivesOriginalAbsoluteTwelveSecondDeadline() {
        var deadline = LANAdmissionDeadline(network: .tailscale, now: 0)
        deadline.authenticated(at: 8)
        deadline.offered(at: 11)
        XCTAssertEqual(deadline.phase, .offered)
        XCTAssertFalse(deadline.expired(at: 14), "A valid offer must not die at the old accept+12 deadline before hello arrives")
        XCTAssertTrue(deadline.expired(at: 26))
    }
    func testRepeatedOrExpiredProgressCannotKeepCandidateAliveForever() {
        var deadline = LANAdmissionDeadline(network: .tailscale, now: 0)
        deadline.authenticated(at: 1)
        let requestLimit = deadline.expiresAt
        deadline.authenticated(at: 10)
        XCTAssertEqual(deadline.expiresAt, requestLimit)
        deadline.offered(at: 11)
        let offerLimit = deadline.expiresAt
        deadline.offered(at: 20)
        deadline.authenticated(at: 21)
        XCTAssertEqual(deadline.expiresAt, offerLimit)
        var expired = LANAdmissionDeadline(network: .tailscale, now: 0)
        expired.authenticated(at: 31); expired.offered(at: 32)
        XCTAssertTrue(expired.expired(at: 32))
        XCTAssertEqual(expired.phase, .transport)
    }
    func testRelayedSilenceReleasesHeldInputQuicklyButAllowsLinkToRecover() {
        var watch = RemoteSessionWatchdog()
        watch.received(at: 100)
        XCTAssertEqual(watch.check(at: 104, network: .tailscale), .none)
        XCTAssertEqual(watch.check(at: 104.1, network: .tailscale), .releaseInputs)
        XCTAssertEqual(watch.check(at: 110, network: .tailscale), .none)
        watch.received(at: 111)
        XCTAssertEqual(watch.check(at: 115.1, network: .tailscale), .releaseInputs)
        XCTAssertEqual(watch.check(at: 141.1, network: .tailscale), .disconnect)
    }
    func testLANRetainsShortDisconnectBoundaryAndPublicWaitIsFinite() {
        var watch = RemoteSessionWatchdog(); watch.received(at: 0)
        XCTAssertEqual(watch.check(at: 4.1, network: .lan), .disconnect)
        XCTAssertEqual(RemoteConnectionPolicy.clientSilence(.lan), 6)
        XCTAssertEqual(RemoteConnectionPolicy.clientSilence(.tailscale), 30)
        XCTAssertGreaterThan(RemoteConnectionPolicy.probe(.tailscale), RemoteConnectionPolicy.transport(.tailscale))
        XCTAssertTrue(LANAdmissionDeadline(network: .tailscale, now: 0).expired(at: 30))
    }
}

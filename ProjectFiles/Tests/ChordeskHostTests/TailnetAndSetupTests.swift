import XCTest
@testable import ChordeskHost

final class TailnetAndSetupTests: XCTestCase {
    private let key = "00112233445566778899aabbccddeeff"
    func testModeIsRequiredAndCannotBroadenLANPairingValidation() throws {
        for value in ["100.64.0.1", "100.100.10.20", "100.127.255.254"] {
            XCTAssertFalse(LANPairing(host: value, port: 49173, secret: key).isValid)
            let ts = LANPairing(host: value, port: 49173, secret: key, network: .tailscale)
            XCTAssertTrue(ts.isValid); XCTAssertEqual(LANPairing.parse(ts.code), ts)
            XCTAssertEqual(ts.version, 2)
        }
        for value in ["100.63.255.255", "100.128.0.0", "8.8.8.8", "192.168.1.2", "127.0.0.1", "0.0.0.0", "100.064.0.1", "100..64.0.1", "mac.ts.net", "100.64.0.1.evil.test", "::ffff:100.64.0.1"] {
            XCTAssertFalse(LANPairing(host: value, port: 49173, secret: key, network: .tailscale).isValid, value)
        }
        let legacy = Data("{\"version\":1,\"host\":\"192.168.1.2\",\"port\":49173,\"secret\":\"\(key)\"}".utf8)
        let old = try JSONDecoder().decode(LANPairing.self, from: legacy)
        XCTAssertTrue(old.isValid); XCTAssertEqual(old.connectionNetwork, .lan)
        var forged = LANPairing(host: "100.64.1.2", port: 49173, secret: key, network: .tailscale)
        forged.version = 1; XCTAssertFalse(forged.isValid)
    }
    func testBothAuthenticatedEndpointsSurviveModeChangesAndKeyRotationRetiresOldKey() throws {
        let id = UUID().uuidString
        let lan = LANPairing(host: "192.168.1.3", port: 49173, secret: key)
        let ts = LANPairing(host: "100.77.1.3", port: 49173, secret: key, network: .tailscale)
        var library = PairedMacLibrary()
        library.remember(lan, name: "Mac", hostID: id)
        let row = library.hosts[0].id
        library.remember(ts, name: "Mac", hostID: id)
        XCTAssertEqual(library.hosts.count, 1)
        XCTAssertEqual(library.hosts[0].id, row)
        XCTAssertEqual(library.hosts[0].pairing(for: .lan), lan)
        XCTAssertEqual(library.hosts[0].pairing(for: .tailscale), ts)
        library = try JSONDecoder().decode(PairedMacLibrary.self, from: JSONEncoder().encode(library))
        library.remember(lan, name: "Mac", hostID: id)
        XCTAssertEqual(library.hosts[0].pairing(for: .tailscale), ts)
        library.remember(.init(host: "192.168.1.3", port: 49173, secret: "ffeeddccbbaa99887766554433221100"), name: "Mac", hostID: id)
        XCTAssertNil(library.hosts[0].pairing(for: .tailscale))
        XCTAssertEqual(library.hosts.count, 1)
    }
    func testTwoManualPermissionRoundsSurviveSystemRestartAndRevocation() {
        var firstLaunch = ManualPermissionPolicy()
        firstLaunch.didRequestPermission()
        let screenOnly = HostPermissionSnapshot(screen: true, accessibility: false, input: false)
        XCTAssertFalse(firstLaunch.canStart(screenOnly, busy: false))
        var secondLaunch = ManualPermissionPolicy()
        XCTAssertFalse(secondLaunch.canStart(screenOnly, busy: false))
        secondLaunch.didRequestPermission()
        let ready = HostPermissionSnapshot(screen: true, accessibility: true, input: true)
        XCTAssertFalse(secondLaunch.canStart(ready, busy: false))
        let thirdLaunch = ManualPermissionPolicy()
        XCTAssertTrue(thirdLaunch.canStart(ready, busy: false))
        XCTAssertFalse(thirdLaunch.canStart(screenOnly, busy: false), "Revocation must still block service")
    }
    func testOnlyOfficialHTTPSLoginURLCanBePresented() {
        XCTAssertNotNil(TailnetSnapshot(authURL: "https://login.tailscale.com/a/example").loginURL)
        for url in ["http://login.tailscale.com/a/x", "https://login.tailscale.com.evil.test/a/x", "file:///tmp/a", "https://user:pass@login.tailscale.com/a/x", "https://login.tailscale.com:8443/a/x", "javascript:alert(1)"] {
            XCTAssertNil(TailnetSnapshot(authURL: url).loginURL)
        }
        XCTAssertFalse(TailnetSnapshot(state: "NeedsLogin", addresses: ["100.64.1.1"]).ready)
        XCTAssertFalse(TailnetSnapshot(state: "Running", addresses: ["8.8.8.8"]).ready)
        XCTAssertTrue(TailnetSnapshot(state: "Running", addresses: ["100.64.1.1"]).ready)
    }
    func testBrowserLoginAloneCannotCompleteDeviceEnrollment() {
        let login = TailnetSnapshot(state: "NeedsLogin", authURL: "https://login.tailscale.com/a/example", addresses: ["100.64.1.1"])
        XCTAssertTrue(login.canAuthorize)
        XCTAssertFalse(login.ready)
        XCTAssertFalse(login.shouldCloseAuthentication)
        let pending = TailnetSnapshot(state: "NeedsMachineAuth", authURL: login.authURL, addresses: login.addresses)
        XCTAssertFalse(pending.canAuthorize, "Do not reopen stale account login while waiting for device approval")
        XCTAssertFalse(pending.ready)
        XCTAssertTrue(pending.shouldCloseAuthentication)
        let runningWithoutAddress = TailnetSnapshot(state: "Running", authURL: login.authURL)
        XCTAssertFalse(runningWithoutAddress.canAuthorize)
        XCTAssertFalse(runningWithoutAddress.shouldCloseAuthentication)
        XCTAssertFalse(runningWithoutAddress.ready)
        let running = TailnetSnapshot(state: "Running", addresses: login.addresses)
        XCTAssertTrue(running.ready)
        XCTAssertTrue(running.shouldCloseAuthentication)
        let error = TailnetSnapshot(state: "Running", addresses: login.addresses, error: "status unavailable")
        XCTAssertFalse(error.ready)
        XCTAssertFalse(error.shouldCloseAuthentication)
    }
    func testOnlyPendingInteractiveAuthenticationCanReceiveBackgroundGrace() {
        let login = TailnetSnapshot(state: "NeedsLogin")
        XCTAssertTrue(login.permitsAuthenticationGrace(browserVisible: true))
        XCTAssertFalse(login.permitsAuthenticationGrace(browserVisible: false))
        for state in ["Stopped", "Running", "NeedsMachineAuth", "Starting", ""] {
            XCTAssertFalse(TailnetSnapshot(state: state).permitsAuthenticationGrace(browserVisible: true), state)
        }
        XCTAssertFalse(TailnetSnapshot(state: "NeedsLogin", error: "failure").permitsAuthenticationGrace(browserVisible: true))
    }
}

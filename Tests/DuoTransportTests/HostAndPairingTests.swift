import XCTest
@testable import DuoWorkbench

final class HostAndPairingTests: XCTestCase {
    private func pairing(_ host: String = "192.168.1.2", secret: String = "00112233445566778899aabbccddeeff") -> LANPairing {
        .init(host: host, port: 49173, secret: secret)
    }
    func testSameNameAndAddressDoNotReplaceDifferentComputers() throws {
        var library = PairedMacLibrary()
        library.remember(pairing(), name: "MacBook", hostID: UUID().uuidString)
        library.remember(pairing(secret: "ffeeddccbbaa99887766554433221100"), name: "MacBook", hostID: UUID().uuidString)
        XCTAssertEqual(library.hosts.count, 2)
        let restored = try JSONDecoder().decode(PairedMacLibrary.self, from: JSONEncoder().encode(library))
        XCTAssertEqual(restored, library)
        library.forget(library.hosts[0].id)
        XCTAssertEqual(library.hosts.count, 1)
        XCTAssertEqual(library.hosts[0].pairing, pairing())
    }
    func testAuthenticatedIdentityUpdatesAddressAndRotatedKeyInPlace() {
        let identity = UUID().uuidString
        var library = PairedMacLibrary()
        library.remember(pairing(), name: "Old name", hostID: identity)
        let rowID = library.hosts[0].id
        library.remember(pairing("192.168.1.19", secret: "ffeeddccbbaa99887766554433221100"), name: "New name", hostID: identity)
        XCTAssertEqual(library.hosts.count, 1)
        XCTAssertEqual(library.hosts[0].id, rowID)
        XCTAssertEqual(library.hosts[0].pairing.host, "192.168.1.19")
    }
    func testLegacyRecordPromotesBySecretWithoutLosingOtherHosts() {
        var library = PairedMacLibrary(hosts: [.init(pairing: pairing(), hostName: "Legacy")])
        let id = library.hosts[0].id
        library.remember(pairing("192.168.1.8", secret: "ffeeddccbbaa99887766554433221100"), name: "Other", hostID: nil)
        let hostID = UUID().uuidString
        library.remember(pairing("192.168.1.7"), name: "Legacy renamed", hostID: hostID)
        XCTAssertEqual(library.hosts.count, 2)
        XCTAssertEqual(library.hosts[0].id, id)
        XCTAssertEqual(library.hosts[0].hostID, hostID)
        library.remember(pairing("8.8.8.8"), name: "Invalid", hostID: nil)
        XCTAssertEqual(library.hosts[0].pairing.host, "192.168.1.7")
    }
    func testPairingCodeStaysStableAcrossUnrelatedRefreshes() {
        let code = pairing().code
        for _ in 0..<100 { XCTAssertEqual(pairing().code, code) }
        XCTAssertEqual(LANPairing.parse(code), pairing())
    }
    func testBuiltInPreferredOverExternallySelectedMainDisplay() {
        XCTAssertEqual(DefaultHostDisplay.choose([10, 20], builtIn: { $0 == 20 }, main: 10), 20)
        XCTAssertEqual(DefaultHostDisplay.choose([10, 20], builtIn: { _ in false }, main: 20), 20)
        XCTAssertNil(DefaultHostDisplay.choose([], builtIn: { _ in false }, main: 20))
    }
    func testWakeRequiresAuthenticationAndOptInAndIsRateLimited() {
        var gate = DisplayWakeGate()
        XCTAssertFalse(gate.claim(authenticated: false, enabled: true, now: 10))
        XCTAssertFalse(gate.claim(authenticated: true, enabled: false, now: 10))
        XCTAssertTrue(gate.claim(authenticated: true, enabled: true, now: 10))
        XCTAssertFalse(gate.claim(authenticated: true, enabled: true, now: 11))
        XCTAssertTrue(gate.claim(authenticated: true, enabled: true, now: 15))
    }
    func testCaptureRetryNeverOverridesUserStopOrPermissionDenial() {
        for code in [-3801, -3803, -3817, -3821] {
            XCTAssertFalse(CaptureRestartDecision.permits(isCaptureError: true, code: code, screenPermission: true))
        }
        XCTAssertTrue(CaptureRestartDecision.permits(isCaptureError: true, code: -3815, screenPermission: true, displayOnline: true))
        XCTAssertFalse(CaptureRestartDecision.permits(isCaptureError: true, code: -3815, screenPermission: true, displayOnline: false))
        XCTAssertTrue(CaptureRestartDecision.permits(isCaptureError: true, code: -3805, screenPermission: true))
        XCTAssertFalse(CaptureRestartDecision.permits(isCaptureError: true, code: -3805, screenPermission: false))
        XCTAssertFalse(CaptureRestartDecision.permits(isCaptureError: false, code: -3805, screenPermission: true))
    }
}

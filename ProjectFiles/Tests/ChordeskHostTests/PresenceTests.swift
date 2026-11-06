import Foundation
import Network
import XCTest
@testable import ChordeskHost

final class PresenceTests: XCTestCase {
    func testExplicitRouteOfferOnlyJoinsOnHelloAndRechecksBusy() throws {
        let offer = try JSONEncoder().encode(LANPresenceRequest(nonce: UUID(), wantsSession: true))
        let hello = try JSONEncoder().encode(LANHello(name: "phone"))
        var gate = LANAdmission()
        guard case .probe = gate.receive(.presenceRequest, data: offer, busy: false) else { return XCTFail() }
        XCTAssertEqual(gate.receive(.hello, data: hello, busy: false), .join)
        for blocked: LANPacket in [.input, .ping, .textInput, .presenceRequest] {
            var invalid = LANAdmission()
            _ = invalid.receive(.presenceRequest, data: offer, busy: false)
            XCTAssertEqual(invalid.receive(blocked, data: hello, busy: false), .reject)
        }
        var contested = LANAdmission()
        _ = contested.receive(.presenceRequest, data: offer, busy: false)
        XCTAssertEqual(contested.receive(.hello, data: hello, busy: true), .reject)
        var busyFromStart = LANAdmission()
        _ = busyFromStart.receive(.presenceRequest, data: offer, busy: true)
        XCTAssertEqual(busyFromStart.receive(.hello, data: hello, busy: false), .reject)
    }

    @MainActor
    func testFastConnectReusesOneTLSHandshakeAndTransfersCleanupOnce() async throws {
        try await offeredConnection(reuse: true, cancel: false)
    }
    @MainActor
    func testLegacyOfferResponseFallsBackWithoutLeakingConnection() async throws {
        try await offeredConnection(reuse: false, cancel: false)
    }
    @MainActor
    func testLosingOfferedRouteCancelsWithoutJoiningOrLosingCleanup() async throws {
        try await offeredConnection(reuse: true, cancel: true)
    }
    @MainActor
    private func offeredConnection(reuse: Bool, cancel: Bool) async throws {
        let secret = "00112233445566778899aabbccddeeff", identity = UUID().uuidString
        let listener = try LANTransport.listener(secret: secret, localAddress: "127.0.0.1", port: .any)
        let done = expectation(description: "offer completed")
        var servers: [LANLink] = [], probe: LANPresenceProbe?, handed: LANLink?
        var cleanup: (() -> Void)?, cleaned = 0, joins = 0, connections = 0
        defer { probe?.cancel(); handed?.close(); cleanup?(); listener.cancel(); servers.forEach { $0.close() } }
        listener.newConnectionHandler = { connection in
            Task { @MainActor in
                connections += 1
                let server = LANLink(connection); servers.append(server)
                var gate = LANAdmission()
                server.onPacket = { kind, data in
                    Task { @MainActor in
                        switch gate.receive(kind, data: data, busy: false) {
                        case .probe(let request):
                            XCTAssertEqual(request.wantsSession, true)
                            server.send(.presenceResponse, value: LANPresenceResponse(nonce: request.nonce, hostID: identity,
                                busy: false, displayAvailable: true, sessionActive: true, canJoin: reuse ? true : nil))
                        case .join:
                            joins += 1
                            server.send(.ping)
                        default: XCTFail("No input permitted before selecting and joining the winning route")
                        }
                    }
                }
                server.start()
            }
        }
        listener.stateUpdateHandler = { state in
            if case .ready = state, let port = listener.port {
                Task { @MainActor in
                    let check = LANPresenceProbe(hostID: identity, wantsSession: true) { reply in
                        XCTAssertNotNil(reply)
                        if reuse && !cancel {
                            let transferred = probe?.takeTransport()
                            XCTAssertNotNil(transferred)
                            handed = transferred?.link; cleanup = transferred?.cleanup
                            probe?.cancel()
                            XCTAssertEqual(cleaned, 0, "Cancellation must not close the winner after handoff")
                            handed?.onPacket = { kind, _ in
                                Task { @MainActor in
                                    XCTAssertEqual(kind, .ping); done.fulfill()
                                }
                            }
                            handed?.send(.hello, value: LANHello(name: "test"))
                        } else {
                            probe?.cancel()
                            XCTAssertNil(probe?.takeTransport()); XCTAssertEqual(cleaned, 1)
                            done.fulfill()
                        }
                    }
                    probe = check; check.cleanup = { cleaned += 1 }; check.start()
                    check.attach(NWConnection(host: "127.0.0.1", port: port, using: LANTransport.parameters(secret: secret)))
                }
            }
        }
        listener.start(queue: DispatchQueue(label: "chordesk-fast-route-test"))
        await fulfillment(of: [done], timeout: 5)
        XCTAssertEqual(connections, 1); XCTAssertEqual(joins, reuse && !cancel ? 1 : 0)
        handed?.close(); handed = nil; cleanup?(); cleanup = nil
        XCTAssertEqual(cleaned, 1)
    }

    func testProbeCannotClaimControlOrUpgradeToHelloWhileHostIsBusy() throws {
        var gate = LANAdmission()
        let request = LANPresenceRequest(nonce: UUID())
        XCTAssertEqual(gate.receive(.presenceRequest, data: try JSONEncoder().encode(request), busy: true), .probe(request))
        XCTAssertEqual(gate.receive(.hello, data: Data("iPhone".utf8), busy: false), .reject)
        XCTAssertEqual(gate.receive(.input, data: Data(), busy: false), .reject)
    }
    func testOldHelloStillJoinsButBusyOrUnsolicitedInputCannotClaimSession() throws {
        var legacy = LANAdmission()
        XCTAssertEqual(legacy.receive(.hello, data: Data("legacy iPhone".utf8), busy: false), .join)
        XCTAssertEqual(legacy.receive(.ping, data: Data(), busy: true), .remote)
        var modern = LANAdmission()
        XCTAssertEqual(modern.receive(.hello, data: try JSONEncoder().encode(LANHello(name: "phone")), busy: false), .join)
        var busy = LANAdmission()
        XCTAssertEqual(busy.receive(.hello, data: Data("phone".utf8), busy: true), .reject)
        for kind: LANPacket in [.input, .release, .ping, .textInput, .presenceResponse] {
            var gate = LANAdmission()
            XCTAssertEqual(gate.receive(kind, data: Data(), busy: false), .reject)
        }
    }
    func testMalformedAndRepeatedProbeRejected() throws {
        for data in [Data(), Data("{}".utf8), Data(repeating: 65, count: 256)] {
            var gate = LANAdmission()
            XCTAssertEqual(gate.receive(.presenceRequest, data: data, busy: false), .reject)
        }
        var gate = LANAdmission()
        let data = try JSONEncoder().encode(LANPresenceRequest(nonce: UUID()))
        _ = gate.receive(.presenceRequest, data: data, busy: false)
        XCTAssertEqual(gate.receive(.presenceRequest, data: data, busy: false), .reject)
    }
    func testLegacySavedHostDoesNotGainProbeCapabilityFromNameOrIP() throws {
        let pairing = LANPairing(host: "192.168.1.4", port: 49491, secret: "00112233445566778899aabbccddeeff")
        let legacy = RememberedMac(pairing: pairing, hostName: "Mac")
        let decoded = try JSONDecoder().decode(RememberedMac.self, from: JSONEncoder().encode(legacy))
        XCTAssertNil(decoded.supportsPresenceProbe)
        var library = PairedMacLibrary(hosts: [decoded])
        let identity = UUID().uuidString
        library.remember(pairing, name: "Mac", hostID: identity, supportsPresenceProbe: true)
        XCTAssertEqual(library.hosts.count, 1)
        XCTAssertEqual(library.hosts[0].id, legacy.id)
        XCTAssertEqual(library.hosts[0].supportsPresenceProbe, true)
        library.remember(pairing, name: "Mac", hostID: identity)
        XCTAssertNil(library.hosts[0].supportsPresenceProbe, "Downgraded hosts must not be probed.")
    }

    @MainActor
    func testProbeTimeoutAndLateRouteCleanupCompleteOnlyOnce() async {
        var callbacks = 0, cleaned = 0
        let done = expectation(description: "bounded timeout")
        let probe = LANPresenceProbe(hostID: UUID().uuidString) { reply in
            XCTAssertNil(reply); callbacks += 1; done.fulfill()
        }
        probe.reportProgress("TLS 已建立，等待 Mac 在线响应")
        probe.start(timeout: 0.03)
        await fulfillment(of: [done], timeout: 1)
        XCTAssertTrue(probe.failureReason?.contains("等待 Mac 在线响应") == true)
        let failure = probe.failureReason
        probe.cleanup = { cleaned += 1 }
        probe.cancel(); probe.fail()
        XCTAssertTrue(probe.finished); XCTAssertEqual(callbacks, 1); XCTAssertEqual(cleaned, 1)
        XCTAssertEqual(probe.failureReason, failure, "Cancellation must not replace the actionable timeout stage")
    }
    @MainActor
    func testCancellationReleasesRouteWithoutWaitingForHandshake() {
        var callbacks = 0, cleaned = 0
        let probe = LANPresenceProbe(hostID: UUID().uuidString) { _ in callbacks += 1 }
        probe.cleanup = { cleaned += 1 }; probe.start(); probe.cancel(); probe.cancel()
        XCTAssertTrue(probe.finished); XCTAssertEqual(callbacks, 1); XCTAssertEqual(cleaned, 1)
    }

    @MainActor
    func testEncryptedProbeReportsBusyWithoutJoiningOrSendingFrames() async throws {
        try await roundTrip(alterNonce: false, alterIdentity: false)
    }
    @MainActor
    func testEncryptedProbeRejectsWrongIdentity() async throws {
        try await roundTrip(alterNonce: false, alterIdentity: true)
    }
    @MainActor
    func testEncryptedProbeRejectsStaleResponse() async throws {
        try await roundTrip(alterNonce: true, alterIdentity: false)
    }
    @MainActor
    private func roundTrip(alterNonce: Bool, alterIdentity: Bool) async throws {
        let secret = "00112233445566778899aabbccddeeff", identity = UUID().uuidString
        let listener = try LANTransport.listener(secret: secret, localAddress: "127.0.0.1", port: .any)
        let done = expectation(description: "authenticated presence result")
        var servers: [LANLink] = [], probe: LANPresenceProbe?
        defer { probe?.cancel(); listener.cancel(); servers.forEach { $0.close() } }
        listener.newConnectionHandler = { connection in
            Task { @MainActor in
                let server = LANLink(connection); servers.append(server)
                var gate = LANAdmission()
                server.onPacket = { kind, data in
                    Task { @MainActor in
                        XCTAssertEqual(kind, .presenceRequest, "No hello, input, release, or frame request.")
                        guard case .probe(let request) = gate.receive(kind, data: data, busy: true) else {
                            XCTFail("Probe must remain read-only even while another peer is connected"); return
                        }
                        server.send(.presenceResponse, value: LANPresenceResponse(
                            nonce: alterNonce ? UUID() : request.nonce, hostID: alterIdentity ? UUID().uuidString : identity,
                            busy: true, displayAvailable: false, sessionActive: false))
                    }
                }
                server.start()
            }
        }
        listener.stateUpdateHandler = { state in
            if case .ready = state, let port = listener.port {
                Task { @MainActor in
                    let check = LANPresenceProbe(hostID: identity) { reply in
                        if alterNonce || alterIdentity { XCTAssertNil(reply) }
                        else { XCTAssertEqual(reply?.busy, true); XCTAssertEqual(reply?.displayAvailable, false); XCTAssertEqual(reply?.sessionActive, false) }
                        done.fulfill()
                    }
                    probe = check; check.start()
                    check.attach(NWConnection(host: "127.0.0.1", port: port, using: LANTransport.parameters(secret: secret)))
                }
            }
        }
        listener.start(queue: DispatchQueue(label: "chordesk-presence-test"))
        await fulfillment(of: [done], timeout: 8)
        XCTAssertTrue(probe?.finished == true)
    }

    func testInputSourceResetDoesNotInheritModifiersOrPostGlobalEvents() throws {
        let factory = RemoteEventFactory()
        _ = try XCTUnwrap(factory.keyboard(code: 12, modifiers: 15))
        factory.reset()
        let keys = try XCTUnwrap(factory.keyboard(code: 0, modifiers: 0))
        XCTAssertEqual(keys.count, 2)
        XCTAssertEqual(keys.map(\.flags), [[], []])
        XCTAssertEqual(factory.mouse(.leftMouseDown, at: .zero)?.flags, [])
    }
}

import XCTest
import Network
@testable import ChordeskHost

@MainActor
final class LANRebindingTests: XCTestCase {
    private let secret = "00112233445566778899aabbccddeeff"

    func testChangedAddressChoosesCurrentInterfaceWithoutWildcardOrTailnet() {
        let current: [RemoteInterfaceAddress] = [
            .init(name: "en0", address: "10.0.0.9", isUp: true),
            .init(name: "en0", address: "fe80::1%en0", isUp: true),
            .init(name: "en0", address: "fd12::1", isUp: true),
            .init(name: "en1", address: "192.168.1.12", isUp: true),
            .init(name: "utun3", address: "100.100.1.1", isUp: true),
            .init(name: "lo0", address: "127.0.0.1", isUp: true),
            .init(name: "en2", address: "192.168.2.1", isUp: false)
        ]
        let addresses = LANListeners.addresses(selected: "192.168.31.65", interfaces: current)
        XCTAssertEqual(addresses.first, "10.0.0.9")
        XCTAssertEqual(Set(addresses), ["10.0.0.9", "fe80::1%en0", "fd12::1"])
        XCTAssertEqual(LANListeners.addresses(selected: "192.168.1.12", interfaces: current), ["192.168.1.12"])
        XCTAssertEqual(LANListeners.addresses(selected: "10.0.0.9", interfaces: []), [])
    }

    func testRebindingPreservesAuthenticatedSessionAndPairingKey() async throws {
        let pool = LANListeners(primaryPort: .any)
        var links: [LANLink] = []
        defer { pool.stop(); links.forEach { $0.close() } }
        pool.onConnection = { connection in
            let server = LANLink(connection)
            links.append(server)
            server.onPacket = { kind, data in server.send(kind, data: data) }
            server.start()
        }
        let firstReady = expectation(description: "initial exact-address listener")
        var firstReported = false
        pool.onChange = { values in
            if values.first?.host == "127.0.0.1", !firstReported { firstReported = true; firstReady.fulfill() }
        }
        pool.reconcile(addresses: ["127.0.0.1"], secret: secret)
        await fulfillment(of: [firstReady], timeout: 5)
        let first = try XCTUnwrap(pool.pairings.first)
        pool.reconcile(addresses: ["127.0.0.1"], secret: secret)
        XCTAssertEqual(pool.pairings, [first], "Unchanged snapshots must not rotate the port or QR.")
        let client = LANLink(NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: first.port)!, using: LANTransport.parameters(secret: secret)))
        links.append(client)
        let initialEcho = expectation(description: "TLS authenticated before rebind")
        let retainedEcho = expectation(description: "existing authenticated connection survives listener change")
        client.onReady = { client.send(.ping, data: Data([1])) }
        client.onPacket = { _, data in
            if data == Data([1]) { initialEcho.fulfill() }
            if data == Data([2]) { retainedEcho.fulfill() }
        }
        client.start()
        await fulfillment(of: [initialEcho], timeout: 5)
        let rebound = expectation(description: "new IPv6 exact-address listener")
        var reboundReported = false
        pool.onChange = { values in
            if values.first?.host == "::1", !reboundReported { reboundReported = true; rebound.fulfill() }
        }
        pool.reconcile(addresses: ["::1"], secret: secret)
        await fulfillment(of: [rebound], timeout: 5)
        let second = try XCTUnwrap(pool.pairings.first)
        XCTAssertEqual(second.secret, first.secret)
        XCTAssertEqual(pool.pairings.map(\.host), ["::1"])
        client.send(.ping, data: Data([2]))
        let freshEcho = expectation(description: "same pairing authenticates on new listener")
        let fresh = LANLink(NWConnection(host: "::1", port: NWEndpoint.Port(rawValue: second.port)!, using: LANTransport.parameters(secret: secret)))
        links.append(fresh)
        fresh.onReady = { fresh.send(.ping, data: Data([3])) }
        fresh.onPacket = { _, data in if data == Data([3]) { freshEcho.fulfill() } }
        fresh.start()
        await fulfillment(of: [retainedEcho, freshEcho], timeout: 5)
        pool.reconcile(addresses: [], secret: secret)
        XCTAssertTrue(pool.pairings.isEmpty, "Offline snapshots must immediately withdraw stale endpoints.")
    }

    func testQueuedReadyEventsCannotRepublishStoppedOrReplacedListeners() async {
        let pool = LANListeners(primaryPort: .any)
        defer { pool.stop() }
        let stale = expectation(description: "removed address is never published"); stale.isInverted = true
        let current = expectation(description: "replacement address is published")
        var reported = false
        pool.onChange = { values in
            if values.contains(where: { $0.host == "127.0.0.1" }) { stale.fulfill() }
            if values.first?.host == "::1", !reported { reported = true; current.fulfill() }
        }
        pool.reconcile(addresses: ["127.0.0.1"], secret: secret)
        pool.reconcile(addresses: ["::1"], secret: secret)
        await fulfillment(of: [current], timeout: 5)
        pool.stop()
        await fulfillment(of: [stale], timeout: 0.3)
        XCTAssertTrue(pool.pairings.isEmpty)
    }

    func testPublicAndWildcardTargetsCannotCreateAnAdvertisedListener() {
        let pool = LANListeners(primaryPort: .any)
        pool.reconcile(addresses: ["0.0.0.0", "::", "8.8.8.8", "100.100.1.1"], secret: secret)
        XCTAssertTrue(pool.pairings.isEmpty)
        pool.stop()
    }
}

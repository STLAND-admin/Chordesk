import Foundation
import Network
import XCTest
@testable import ChordeskHost

final class IPv6Tests: XCTestCase {
    private let key = "00112233445566778899aabbccddeeff"
    private let mask = "ffff:ffff:ffff:ffff::"
    private var interfaces: [RemoteInterfaceAddress] {
        [.init(name: "en7", address: "2001:db8:42:1::10", isUp: true, netmask: mask),
         .init(name: "en7", address: "fd12:3456:789a:1::10", isUp: true, netmask: mask),
         .init(name: "en7", address: "fe80::10%en7", isUp: true, netmask: mask)]
    }
    func testStrictIPv6RangesAndPairingRoundTrip() {
        for host in ["::1", "fe80::1234", "fd12:3456:789a::12", "2001:db8:42:1::11"] {
            let value = LANPairing(host: host, port: 49173, secret: key)
            XCTAssertTrue(value.isValid, host)
            XCTAssertEqual(LANPairing.parse(value.code), value)
        }
        for host in ["::", "ff02::1", "::ffff:192.168.1.1", "[::1]", "fe80::1%", "fe80::1%en0/..", "2001:db8::1%en0", "2001:db8::1.evil.test", "fd7a:115c:a1e0::1"] {
            XCTAssertFalse(LANPairing.isLocalHost(host), host)
        }
        for host in ["fd7a:115c:a1e0::1", "FD7A:115C:A1E0::abcd"] {
            let value = LANPairing(host: host, port: 49173, secret: key, network: .tailscale)
            XCTAssertTrue(value.isValid); XCTAssertEqual(LANPairing.parse(value.code), value)
            XCTAssertTrue(TailnetSnapshot(state: "Running", addresses: [host]).ready)
        }
        for host in ["fd7a:115c:a1e1::1", "fd00::1", "fe80::1", "2001:db8::1", "fd7a:115c:a1e0::1%en0", "::ffff:100.64.0.1"] {
            XCTAssertFalse(LANPairing.isTailscaleHost(host), host)
        }
    }
    func testGlobalLANIPv6CannotDialOffLinkAndLinkScopeBelongsToReceiver() {
        XCTAssertEqual(LANAddress.connectionHosts("2001:db8:42:1::99", interfaces: interfaces), ["2001:db8:42:1::99"])
        XCTAssertTrue(LANAddress.connectionHosts("2001:db8:42:2::99", interfaces: interfaces).isEmpty)
        XCTAssertTrue(LANAddress.connectionHosts("2001:4860:4860::8888", interfaces: interfaces).isEmpty)
        XCTAssertEqual(LANAddress.connectionHosts("fe80::99", interfaces: interfaces), ["fe80::99%en7"])
        XCTAssertTrue(LANAddress.connectionHosts("fe80::99%en0", interfaces: interfaces).isEmpty)
        XCTAssertTrue(LANAddress.connectionHosts("fd12:3456:789a:1::99", interfaces: interfaces.map { .init(name: $0.name, address: $0.address, isUp: false, netmask: $0.netmask) }).isEmpty)
        let unsafeMask = [RemoteInterfaceAddress(name: "en7", address: "2001:db8:42:1::10", isUp: true, netmask: "::")]
        XCTAssertTrue(LANAddress.connectionHosts("2001:db8:42:1::11", interfaces: unsafeMask).isEmpty)
    }
    func testIncomingGlobalPeerMustMatchExactBoundSubnet() {
        XCTAssertTrue(LANAddress.permitsPeer("2001:db8:42:1::11", boundAddress: "2001:db8:42:1::10", interfaces: interfaces))
        XCTAssertFalse(LANAddress.permitsPeer("2001:db8:42:2::11", boundAddress: "2001:db8:42:1::10", interfaces: interfaces))
        XCTAssertFalse(LANAddress.permitsPeer("::1", boundAddress: "2001:db8:42:1::10", interfaces: interfaces))
        XCTAssertTrue(LANAddress.permitsPeer("::1", boundAddress: "::1", interfaces: []))
        XCTAssertFalse(LANAddress.permitsPeer("fe80::10", boundAddress: "::1", interfaces: interfaces))
    }
    func testAuthenticatedDualStackAddressesSurviveStorageAndRotation() throws {
        let id = UUID().uuidString
        let lan = LANPairing(host: "192.168.1.10", port: 49173, secret: key)
        let endpoints: [LANEndpoint] = [
            .init(host: "fd12:3456:789a:1::10", port: 49173, network: .lan),
            .init(host: "fe80::10", port: 49173, network: .lan),
            .init(host: "100.64.1.10", port: 49173, network: .tailscale),
            .init(host: "fd7a:115c:a1e0::10", port: 49173, network: .tailscale)]
        var library = PairedMacLibrary()
        library.remember(lan, name: "Mac", hostID: id, endpoints: endpoints)
        XCTAssertEqual(library.hosts[0].pairings(for: .lan).count, 3)
        XCTAssertEqual(library.hosts[0].pairings(for: .tailscale).count, 2)
        library = try JSONDecoder().decode(PairedMacLibrary.self, from: JSONEncoder().encode(library))
        XCTAssertEqual(library.hosts[0].pairings(for: .tailscale).last?.host, endpoints.last?.host)
        library.remember(.init(host: lan.host, port: lan.port, secret: "ffeeddccbbaa99887766554433221100"), name: "Mac", hostID: id)
        XCTAssertEqual(library.hosts[0].pairings(for: .lan).count, 1)
        XCTAssertTrue(library.hosts[0].pairings(for: .tailscale).isEmpty)
    }
    func testDualStackServicesAdvertiseTheirIndependentPortsAndAuthenticate() throws {
        let ready = expectation(description: "both advertised IP families authenticate concurrently")
        ready.expectedFulfillmentCount = 2
        let v4 = try LANTransport.listener(secret: key, localAddress: "127.0.0.1", port: .any)
        let v6 = try LANTransport.listener(secret: key, localAddress: "::1", port: .any)
        var links: [LANLink] = []; let lock = NSLock()
        func keep(_ wire: LANLink) { lock.lock(); links.append(wire); lock.unlock() }
        defer { v4.cancel(); v6.cancel(); lock.lock(); let current = links; lock.unlock(); current.forEach { $0.close() } }
        for (server, host) in [(v4, "127.0.0.1"), (v6, "::1")] {
            server.newConnectionHandler = { connection in
                let wire = LANLink(connection); keep(wire)
                wire.onPacket = { kind, data in wire.send(kind, data: data) }; wire.start()
            }
            server.stateUpdateHandler = { state in
                if case .ready = state, let port = server.port {
                    let wire = LANLink(NWConnection(host: NWEndpoint.Host(host), port: port, using: LANTransport.parameters(secret: self.key)))
                    keep(wire); wire.onReady = { wire.send(.ping) }
                    wire.onPacket = { kind, _ in if kind == .ping { ready.fulfill() } }; wire.start()
                }
                if case .failed(let error) = state { XCTFail("Dual-stack listener failed: \(error)") }
            }
            server.start(queue: DispatchQueue(label: "chordesk.dualstack." + host))
        }
        wait(for: [ready], timeout: 10)
    }
    func testIPv6TLSPairingReallyExchangesPacketsOverLoopback() throws {
        let echo = expectation(description: "paired TLS works over IPv6, not only an address parser")
        let server = try LANTransport.listener(secret: key, localAddress: "::1", port: .any)
        var links: [LANLink] = []
        let lock = NSLock()
        func keep(_ link: LANLink) { lock.lock(); links.append(link); lock.unlock() }
        defer { server.cancel(); lock.lock(); let current = links; lock.unlock(); current.forEach { $0.close() } }
        server.newConnectionHandler = { connection in
            let wire = LANLink(connection); keep(wire)
            wire.onPacket = { kind, data in wire.send(kind, data: data) }; wire.start()
        }
        server.stateUpdateHandler = { state in
            if case .ready = state, let port = server.port {
                let wire = LANLink(NWConnection(host: "::1", port: port, using: LANTransport.parameters(secret: self.key)))
                keep(wire); wire.onReady = { wire.send(.ping, data: Data("IPv6".utf8)) }
                wire.onPacket = { kind, data in
                    XCTAssertEqual(kind, .ping); XCTAssertEqual(data, Data("IPv6".utf8)); echo.fulfill()
                }
                wire.start()
            }
        }
        server.start(queue: DispatchQueue(label: "chordesk.ipv6.test"))
        wait(for: [echo], timeout: 10)
    }
}

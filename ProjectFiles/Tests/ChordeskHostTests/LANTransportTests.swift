import Foundation
import Network
import XCTest
@testable import ChordeskHost

final class LANTransportTests: XCTestCase {
    private let secret = "00112233445566778899aabbccddeeff"
    private var listener: NWListener?
    private var links: [LANLink] = []
    private let lock = NSLock()

    override func tearDown() {
        listener?.cancel()
        lock.lock(); let current = links; links = []; lock.unlock()
        current.forEach { $0.close() }
        super.tearDown()
    }

    private func keep(_ link: LANLink) { lock.lock(); links.append(link); lock.unlock() }

    private func listen(port: NWEndpoint.Port = .any, pairingSecret: String? = nil, handshakeTimeout: Double = 12, accepted: @escaping (LANLink) -> Void, ready: @escaping (NWEndpoint.Port) -> Void, failed: @escaping (NWError) -> Void = { _ in }) throws {
        let server = try LANTransport.listener(secret: pairingSecret ?? secret, localAddress: "127.0.0.1", port: port)
        listener = server
        server.newConnectionHandler = { [weak self] connection in
            let link = LANLink(connection); self?.keep(link); accepted(link); link.start(timeout: handshakeTimeout)
        }
        server.stateUpdateHandler = { state in
            if case .ready = state, let port = server.port { ready(port) }
            if case .failed(let error) = state { failed(error) }
        }
        server.start(queue: DispatchQueue(label: "duo-test-listener"))
    }

    func testPublicTLSHandshakeSurvivesDelayBeyondOldTwelveSecondBudget() throws {
        // A transparent loopback proxy delays the first server TLS flight. It
        // never decrypts packets, changes credentials, or touches the live host.
        let echoed = expectation(description: "paired TLS survives 12.5 seconds of relay delay")
        let queue = DispatchQueue(label: "chordesk-delayed-tls-test")
        let connectionsLock = NSLock()
        var rawConnections: [NWConnection] = []
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let proxy = try NWListener(using: params)
        defer {
            proxy.cancel()
            connectionsLock.lock(); let current = rawConnections; connectionsLock.unlock()
            current.forEach { $0.cancel() }
        }
        func copy(_ source: NWConnection, _ target: NWConnection, firstDelay: Double) {
            source.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, complete, error in
                guard let data, !data.isEmpty, error == nil else { source.cancel(); target.cancel(); return }
                queue.asyncAfter(deadline: .now() + firstDelay) {
                    target.send(content: data, completion: .contentProcessed { error in
                        if error == nil && !complete { copy(source, target, firstDelay: 0) }
                        else { source.cancel(); target.cancel() }
                    })
                }
            }
        }
        try listen(handshakeTimeout: RemoteConnectionPolicy.transport(.tailscale), accepted: { server in
            server.onPacket = { kind, data in server.send(kind, data: data) }
        }, ready: { port in
            proxy.newConnectionHandler = { inbound in
                let outbound = NWConnection(host: "127.0.0.1", port: port, using: .tcp)
                connectionsLock.lock(); rawConnections += [inbound, outbound]; connectionsLock.unlock()
                inbound.start(queue: queue); outbound.start(queue: queue)
                copy(inbound, outbound, firstDelay: 0)
                copy(outbound, inbound, firstDelay: 12.5)
            }
            proxy.stateUpdateHandler = { state in
                guard case .ready = state, let port = proxy.port else { return }
                let client = LANLink(NWConnection(host: "127.0.0.1", port: port, using: LANTransport.parameters(secret: self.secret)))
                self.keep(client)
                client.onReady = { client.send(.ping, data: Data("delayed-but-authenticated".utf8)) }
                client.onPacket = { kind, data in
                    XCTAssertEqual(kind, .ping); XCTAssertEqual(data, Data("delayed-but-authenticated".utf8)); echoed.fulfill()
                }
                client.start(timeout: RemoteConnectionPolicy.transport(.tailscale))
            }
            proxy.start(queue: queue)
        })
        wait(for: [echoed], timeout: 22)
    }

    func testProductionFixedPortStartsAndAuthenticates() throws {
        let echoed = expectation(description: "fixed-port TLS service accepts a paired phone")
        let fixed = NWEndpoint.Port(rawValue: LANPairing.defaultPort)!
        var listenerError: NWError?
        try listen(port: fixed, accepted: { server in
            server.onPacket = { kind, data in server.send(kind, data: data) }
        }, ready: { port in
            XCTAssertEqual(port, fixed)
            let client = LANLink(NWConnection(host: "127.0.0.1", port: port, using: LANTransport.parameters(secret: self.secret)))
            self.keep(client)
            client.onReady = { client.send(.ping) }
            client.onPacket = { kind, _ in if kind == .ping { echoed.fulfill() } }
            client.start()
        }, failed: { error in listenerError = error; echoed.fulfill() })
        wait(for: [echoed], timeout: 10)
        if let error = listenerError {
            // Do not stop a user's running remote host just to claim its port.
            if case .posix(.EADDRINUSE) = error { throw XCTSkip("Production port is already in use; rerun this integration test with the live host stopped.") }
            XCTFail("Production listener failed: \(error)")
        }
    }

    func testAuthenticatedRoundTripPreservesLargeAndEmptyPacketBoundaries() throws {
        let echoed = expectation(description: "old and new correctly framed encrypted messages")
        echoed.expectedFulfillmentCount = 8
        let payloads: [(LANPacket, Data)] = [(.hello, Data("iPhone".utf8)), (.frame, Data(repeating: 0xa5, count: 700_000)),
            (.release, Data()), (.input, Data("after-large-frame".utf8)),
            (.microphoneAudio, MicrophonePacket(streamID: UUID(), sequence: 7, pcm: Data(repeating: 0x3f, count: 960)).encoded),
            (.streamSettings, try JSONEncoder().encode(StreamSettings(resolution: .p2160, fps: 120, bitrate: 25_000_000))),
            (.bandwidthChunk, BandwidthProbe.chunk(id: UUID())), (.input, Data("after-bandwidth-sample".utf8))]
        var index = 0
        try listen(accepted: { server in server.onPacket = { kind, data in server.send(kind, data: data) } }, ready: { port in
            let client = LANLink(NWConnection(host: "127.0.0.1", port: port, using: LANTransport.parameters(secret: self.secret)))
            self.keep(client)
            client.onReady = { client.send(payloads[0].0, data: payloads[0].1) }
            client.onPacket = { kind, data in
                XCTAssertLessThan(index, payloads.count)
                if index < payloads.count { XCTAssertEqual(kind.rawValue, payloads[index].0.rawValue); XCTAssertEqual(data, payloads[index].1) }
                index += 1; echoed.fulfill()
                if index < payloads.count { client.send(payloads[index].0, data: payloads[index].1) }
            }
            client.start()
        })
        wait(for: [echoed], timeout: 10)
    }

    func testIncorrectPairingKeyCannotEstablishTLS() throws {
        let rejected = expectation(description: "wrong key rejected")
        let ready = expectation(description: "wrong key must not authenticate"); ready.isInverted = true
        try listen(accepted: { _ in }, ready: { port in
            let client = LANLink(NWConnection(host: "127.0.0.1", port: port,
                using: LANTransport.parameters(secret: "ffeeddccbbaa99887766554433221100")))
            self.keep(client)
            client.onReady = { ready.fulfill() }
            client.onClose = { _ in rejected.fulfill() }
            client.start()
        })
        wait(for: [rejected], timeout: 15)
        wait(for: [ready], timeout: 0.2)
    }

    func testRotatedKeyRejectsOldViewerBeforeDeliveringAnyDesktopPacket() throws {
        let rotated = "ffeeddccbbaa99887766554433221100"
        let rejected = expectation(description: "old pairing cannot authenticate")
        let current = expectation(description: "new pairing can receive the desktop")
        let leaked = expectation(description: "old pairing must never receive desktop contents")
        leaked.isInverted = true
        let payload = Data("synthetic desktop, no personal data".utf8)
        try listen(pairingSecret: rotated, accepted: { server in
            server.onReady = { server.send(.frame, data: payload) }
        }, ready: { port in
            for key in [self.secret, rotated] {
                let client = LANLink(NWConnection(host: "127.0.0.1", port: port, using: LANTransport.parameters(secret: key)))
                self.keep(client)
                if key == self.secret {
                    client.onPacket = { _, _ in leaked.fulfill() }
                    client.onClose = { _ in rejected.fulfill() }
                } else {
                    client.onPacket = { kind, data in
                        XCTAssertEqual(kind, .frame); XCTAssertEqual(data, payload); current.fulfill()
                    }
                }
                client.start()
            }
        })
        wait(for: [rejected, current], timeout: 15)
        wait(for: [leaked], timeout: 0.2)
    }

    func testPlainTCPHasNoFallbackThatCanExposeApplicationPackets() throws {
        let rejected = expectation(description: "plaintext socket rejected")
        let accepted = expectation(description: "plaintext must not reach the authenticated application")
        accepted.isInverted = true
        var raw: NWConnection?
        defer { raw?.cancel() }
        try listen(accepted: { server in
            server.onReady = { accepted.fulfill() }
            server.onPacket = { _, _ in accepted.fulfill() }
            server.onClose = { _ in rejected.fulfill() }
        }, ready: { port in
            let client = NWConnection(host: "127.0.0.1", port: port, using: .tcp)
            raw = client
            client.stateUpdateHandler = { state in
                if case .ready = state {
                    client.send(content: Data([LANPacket.hello.rawValue, 0, 0, 0, 1, 65]), completion: .contentProcessed { _ in })
                }
            }
            client.start(queue: DispatchQueue(label: "chordesk-plaintext-rejection-test"))
        })
        wait(for: [rejected], timeout: 15)
        wait(for: [accepted], timeout: 0.2)
    }

    func testOversizedHeaderIsRejectedBeforeReadingPayload() throws {
        let rejected = expectation(description: "length limit enforced before allocation")
        var rawClient: NWConnection?
        defer { rawClient?.cancel() }
        try listen(accepted: { server in
            server.onClose = { reason in if reason == "数据包超过上限" { rejected.fulfill() } }
        }, ready: { port in
            let connection = NWConnection(host: "127.0.0.1", port: port, using: LANTransport.parameters(secret: self.secret))
            rawClient = connection
            connection.stateUpdateHandler = { state in
                if case .ready = state {
                    var header = Data([LANPacket.frame.rawValue])
                    var length = UInt32(LANLink.maximumPacketSize + 1).bigEndian
                    withUnsafeBytes(of: &length) { header.append(contentsOf: $0) }
                    connection.send(content: header, completion: .contentProcessed { _ in })
                }
            }
            connection.start(queue: DispatchQueue(label: "duo-test-oversize"))
        })
        wait(for: [rejected], timeout: 10)
    }

    func testPairingRejectsPublicAndAmbiguousAddresses() {
        for host in ["8.8.8.8", "192.168.1.1.example.com", "10..0.0.1", "010.0.0.1", "localhost", "127.0.0.1:80"] {
            XCTAssertFalse(LANPairing(host: host, port: 1234, secret: secret).isValid, host)
        }
        let valid = LANPairing(host: "192.168.1.10", port: 1234, secret: secret)
        XCTAssertEqual(LANPairing.parse(valid.code), valid)
    }
}

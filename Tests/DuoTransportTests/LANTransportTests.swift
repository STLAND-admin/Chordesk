import Foundation
import Network
import XCTest
@testable import DuoWorkbench

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

    private func listen(port: NWEndpoint.Port = .any, accepted: @escaping (LANLink) -> Void, ready: @escaping (NWEndpoint.Port) -> Void) throws {
        let server = try LANTransport.listener(secret: secret, localAddress: "127.0.0.1", port: port)
        listener = server
        server.newConnectionHandler = { [weak self] connection in
            let link = LANLink(connection); self?.keep(link); accepted(link); link.start()
        }
        server.stateUpdateHandler = { state in if case .ready = state, let port = server.port { ready(port) } }
        server.start(queue: DispatchQueue(label: "duo-test-listener"))
    }

    func testProductionFixedPortStartsAndAuthenticates() throws {
        let echoed = expectation(description: "fixed-port TLS service accepts a paired phone")
        let fixed = NWEndpoint.Port(rawValue: LANPairing.defaultPort)!
        try listen(port: fixed, accepted: { server in
            server.onPacket = { kind, data in server.send(kind, data: data) }
        }, ready: { port in
            XCTAssertEqual(port, fixed)
            let client = LANLink(NWConnection(host: "127.0.0.1", port: port, using: LANTransport.parameters(secret: self.secret)))
            self.keep(client)
            client.onReady = { client.send(.ping) }
            client.onPacket = { kind, _ in if kind == .ping { echoed.fulfill() } }
            client.start()
        })
        wait(for: [echoed], timeout: 10)
    }

    func testAuthenticatedRoundTripPreservesLargeAndEmptyPacketBoundaries() throws {
        let echoed = expectation(description: "five correctly framed encrypted messages")
        echoed.expectedFulfillmentCount = 5
        let payloads: [(LANPacket, Data)] = [(.hello, Data("iPhone".utf8)), (.frame, Data(repeating: 0xa5, count: 700_000)),
            (.release, Data()), (.input, Data("after-large-frame".utf8)),
            (.microphoneAudio, MicrophonePacket(streamID: UUID(), sequence: 7, pcm: Data(repeating: 0x3f, count: 960)).encoded)]
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

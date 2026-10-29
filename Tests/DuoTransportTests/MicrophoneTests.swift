import XCTest
@testable import DuoWorkbench

final class MicrophoneTests: XCTestCase {
    func testPacketRoundTripAndExactFormatBounds() throws {
        let id = UUID(), pcm = Data((0..<960).map { UInt8($0 % 256) })
        let packet = MicrophonePacket(streamID: id, sequence: 0x12345678, pcm: pcm)
        let decoded = try XCTUnwrap(MicrophonePacket(packet.encoded))
        XCTAssertEqual(decoded.streamID, id)
        XCTAssertEqual(decoded.sequence, 0x12345678)
        XCTAssertEqual(decoded.pcm, pcm)
        XCTAssertEqual(packet.encoded.count, MicrophonePacket.byteCount)
        XCTAssertNil(MicrophonePacket(Data(packet.encoded.dropLast())))
        XCTAssertNil(MicrophonePacket(packet.encoded + Data([0])))
        XCTAssertNil(MicrophonePacket(Data()))
    }
    func testDisabledOldAndReplayedStreamsCannotEnterAudioDevice() {
        let id = UUID(), other = UUID(), pcm = Data(repeating: 0, count: 960)
        var gate = MicrophoneReceiveGate()
        let first = MicrophonePacket(streamID: id, sequence: 0, pcm: pcm)
        XCTAssertFalse(gate.accept(first))
        gate.start(id)
        XCTAssertFalse(gate.accept(.init(streamID: other, sequence: 0, pcm: pcm)))
        XCTAssertTrue(gate.accept(first))
        XCTAssertFalse(gate.accept(first))
        XCTAssertTrue(gate.accept(.init(streamID: id, sequence: 3, pcm: pcm))) // network drops are OK
        XCTAssertFalse(gate.accept(.init(streamID: id, sequence: 2, pcm: pcm)))
        gate.stop()
        XCTAssertFalse(gate.accept(.init(streamID: id, sequence: 4, pcm: pcm)))
        gate.start(other)
        XCTAssertFalse(gate.accept(.init(streamID: id, sequence: 5, pcm: pcm)))
        XCTAssertTrue(gate.accept(.init(streamID: other, sequence: 0, pcm: pcm)))
    }
    func testLegacyPeersDoNotAdvertiseMicrophone() throws {
        let hello = try JSONDecoder().decode(LANHello.self, from: Data(#"{"name":"Old Mac","displaySelection":true}"#.utf8))
        XCTAssertNil(hello.microphone)
        let status = try JSONDecoder().decode(LANStatus.self, from: Data(#"{"version":1,"name":"Old Mac","width":800,"height":600,"canControl":false,"message":""}"#.utf8))
        XCTAssertNil(status.supportsMicrophone)
    }
    func testStopRequestRoundTripPreservesStreamIdentity() throws {
        // Real TLS transport boundaries are covered in LANTransportTests.
        let id = UUID()
        let request = LANMicrophoneRequest(streamID: id, enabled: false)
        let decoded = try JSONDecoder().decode(LANMicrophoneRequest.self, from: JSONEncoder().encode(request))
        XCTAssertEqual(decoded.streamID, id); XCTAssertFalse(decoded.enabled)
    }
}

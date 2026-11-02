import XCTest
import CoreVideo
import CoreMedia
@testable import ChordeskHost

final class VideoAndRouteTests: XCTestCase {
    private let key = "00112233445566778899aabbccddeeff"
    func testVideoBackpressureDropsDependenciesUntilAnUnblockedKeyframe() {
        var gate = VideoSendGate()
        XCTAssertTrue(gate.admit(interFrame: true, keyframe: true))
        XCTAssertFalse(gate.admit(interFrame: true, keyframe: false))
        XCTAssertEqual(gate.pending, 1)
        gate.completed()
        XCTAssertFalse(gate.admit(interFrame: true, keyframe: false))
        XCTAssertTrue(gate.admit(interFrame: true, keyframe: true))
        XCTAssertFalse(gate.admit(interFrame: true, keyframe: true)) // IDR can be dropped, too.
        gate.completed()
        XCTAssertFalse(gate.admit(interFrame: true, keyframe: false))
        XCTAssertTrue(gate.admit(interFrame: false, keyframe: true)) // JPEG is self-contained.
        gate.completed()
        XCTAssertTrue(gate.admit(interFrame: true, keyframe: true))
        gate.completed()
        XCTAssertTrue(gate.admit(interFrame: true, keyframe: false))
    }
    func testTailscalePreferenceWithBoundedLANFallbackAndNoLateReplacement() {
        var race = AutomaticRouteRace([.lan, .tailscale])
        XCTAssertFalse(race.complete(.lan, reachable: false))
        XCTAssertFalse(race.exhausted)
        XCTAssertTrue(race.complete(.tailscale, reachable: true))
        XCTAssertFalse(race.complete(.lan, reachable: true))
        XCTAssertEqual(race.winner, .tailscale)
        var another = AutomaticRouteRace([.lan, .tailscale])
        XCTAssertFalse(another.complete(.lan, reachable: true))
        XCTAssertTrue(another.complete(.tailscale, reachable: true))
        XCTAssertEqual(another.winner, .tailscale)
        var fallback = AutomaticRouteRace([.lan, .tailscale])
        XCTAssertFalse(fallback.complete(.lan, reachable: true))
        XCTAssertTrue(fallback.allowFallback())
        XCTAssertFalse(fallback.complete(.tailscale, reachable: true))
        XCTAssertEqual(fallback.winner, .lan)
        var rejected = AutomaticRouteRace([.lan, .tailscale])
        XCTAssertFalse(rejected.complete(.lan, reachable: true))
        XCTAssertTrue(rejected.complete(.tailscale, reachable: false))
        XCTAssertEqual(rejected.winner, .lan)
        var localOnly = AutomaticRouteRace([.lan])
        XCTAssertTrue(localOnly.complete(.lan, reachable: true))
        var failed = AutomaticRouteRace([.lan, .tailscale])
        XCTAssertFalse(failed.complete(.lan, reachable: false)); XCTAssertFalse(failed.complete(.tailscale, reachable: false))
        XCTAssertTrue(failed.exhausted)
    }
    func testAuthenticatedCatalogAddsBothPathsWithoutMergingNamesOrAcceptingPublicIPs() {
        let lan = LANPairing(host: "192.168.1.2", port: 49173, secret: key)
        let endpoints = [LANEndpoint(host: "100.65.1.2", port: 49173, network: .tailscale),
                         LANEndpoint(host: "8.8.8.8", port: 49173, network: .lan)]
        var library = PairedMacLibrary()
        library.remember(lan, name: "Same name", hostID: UUID().uuidString, supportsPresenceProbe: true, endpoints: endpoints)
        XCTAssertEqual(library.hosts[0].pairing(for: .tailscale)?.host, "100.65.1.2")
        XCTAssertEqual(library.hosts[0].alternativePairings?.count, 1)
        library.remember(LANPairing(host: lan.host, port: lan.port, secret: "ffeeddccbbaa99887766554433221100"), name: "Same name", hostID: UUID().uuidString)
        XCTAssertEqual(library.hosts.count, 2)
    }
    func testCombinedInvitationRetainsLegacyPairingAndValidatesEndpointRanges() throws {
        var invite = LANPairing(host: "192.168.1.2", port: 49173, secret: key)
        invite.invitationHostID = UUID().uuidString
        invite.invitationEndpoints = [.init(host: "100.65.1.2", port: 49173, network: .tailscale)]
        let decoded = try XCTUnwrap(LANPairing.parse(invite.code))
        XCTAssertEqual(decoded.version, 1)
        XCTAssertEqual(decoded.invitationHostID, invite.invitationHostID)
        XCTAssertTrue(decoded.invitationEndpoints?[0].pairing(secret: key)?.isValid == true)
        XCTAssertNil(LANEndpoint(host: "example.com", port: 443, network: .tailscale).pairing(secret: key))
        XCTAssertNil(LANEndpoint(host: "8.8.8.8", port: 443, network: .tailscale).pairing(secret: key))
    }
    func testH264WireRejectsTruncationOversizedGeometryAndMalformedNALUnits() throws {
        let packet = VideoPacket(header: .init(stream: UUID(), sequence: 1, keyframe: true, width: 320, height: 180,
            parameterSets: [Data([0x67, 1]), Data([0x68, 1])]), bytes: Data([0, 0, 0, 2, 0x65, 0]))
        let wire = try XCTUnwrap(packet.data)
        XCTAssertEqual(VideoPacket(wire)?.header, packet.header)
        XCTAssertNil(VideoPacket(wire.dropLast()))
        XCTAssertNil(VideoPacket(Data([255, 255, 255, 255, 1])))
        var bad = packet; bad.header.width = 50000; XCTAssertNil(bad.data)
        bad = packet; bad.header.parameterSets = []; XCTAssertNil(bad.data)
        XCTAssertFalse(VideoPacket.nalUnitsValid(Data([0, 0, 0, 255, 1])))
        XCTAssertFalse(VideoPacket.nalUnitsValid(Data([0, 0, 0, 0])))
    }
    private func pixel() throws -> CVPixelBuffer {
        var output: CVPixelBuffer?
        let attrs = [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary
        XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, 320, 180, kCVPixelFormatType_32BGRA, attrs, &output), kCVReturnSuccess)
        let value = try XCTUnwrap(output)
        CVPixelBufferLockBaseAddress(value, [])
        let address = try XCTUnwrap(CVPixelBufferGetBaseAddress(value))
        memset(address, 100, CVPixelBufferGetBytesPerRow(value) * 180)
        CVPixelBufferUnlockBaseAddress(value, [])
        return value
    }
    func testHardwareH264RoundTripAndMissingFrameRecovery() throws {
        try hardwareRoundTrip(.h264)
    }
    func testHardwareHEVCRoundTripAndMissingFrameRecovery() throws {
        try hardwareRoundTrip(.hevc)
    }
    private func hardwareRoundTrip(_ codec: LANVideoCodec) throws {
        let encoder = HardwareVideoEncoder(codec: codec), decoder = HardwareVideoDecoder(), pixels = try pixel()
        let first = try XCTUnwrap(encoder.encode(pixels, time: CMTime(value: 0, timescale: 15), quality: .efficient), "Hardware H.264 must encode a generated frame on this Mac")
        XCTAssertTrue(first.header.keyframe)
        XCTAssertEqual(first.header.resolvedCodec, codec)
        XCTAssertEqual(first.header.parameterSets.count, codec.parameterSetCount)
        XCTAssertEqual(VideoPacket(try XCTUnwrap(first.data))?.header, first.header)
        let image = try XCTUnwrap(decoder.decode(first))
        XCTAssertEqual(image.width, 320); XCTAssertEqual(image.height, 180)
        _ = try XCTUnwrap(encoder.encode(pixels, time: CMTime(value: 1, timescale: 15), quality: .efficient))
        let third = try XCTUnwrap(encoder.encode(pixels, time: CMTime(value: 2, timescale: 15), quality: .efficient))
        if !third.header.keyframe {
            XCTAssertNil(decoder.decode(third)); XCTAssertTrue(decoder.needsKeyframe)
        }
        encoder.forceKeyframe = true
        let fourth = try XCTUnwrap(encoder.encode(pixels, time: CMTime(value: 3, timescale: 15), quality: .efficient))
        XCTAssertTrue(fourth.header.keyframe); XCTAssertNotNil(decoder.decode(fourth)); XCTAssertFalse(decoder.failed)
        encoder.invalidate()
        let renewed = try XCTUnwrap(encoder.encode(pixels, time: CMTime(value: 4, timescale: 15), quality: .efficient))
        XCTAssertNotEqual(renewed.header.stream, first.header.stream)
        XCTAssertNotNil(decoder.decode(renewed))
    }

    func testCodecNegotiationLegacyPreferenceAndMalformedHEVC() throws {
        XCTAssertEqual(LANVideoCodec.negotiate(preferred: "hevc", supported: ["h264", "jpeg"]), .h264)
        XCTAssertEqual(LANVideoCodec.negotiate(preferred: "hevc", supported: ["jpeg"]), .jpeg)
        XCTAssertEqual(LANVideoCodec.negotiate(preferred: "jpeg", supported: ["hevc", "h264", "jpeg"]), .jpeg)
        XCTAssertEqual(LANVideoCodec.negotiate(preferred: "hevc", supported: ["hevc", "h264", "jpeg"]), .hevc)
        let suite = "chordesk-codec-test-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(LANVideoCodec.storedPreference(defaults), .hevc)
        defaults.set(false, forKey: "preferH264V1")
        XCTAssertEqual(LANVideoCodec.storedPreference(defaults), .jpeg)
        defaults.set("hevc", forKey: "videoCodecV2")
        XCTAssertEqual(LANVideoCodec.storedPreference(defaults), .hevc)
        var packet = try XCTUnwrap(HardwareVideoEncoder(codec: .hevc).encode(try pixel(), time: .zero, quality: .efficient))
        packet.header.parameterSets.removeLast(); XCTAssertNil(packet.data)
        packet.header.codec = .jpeg; XCTAssertNil(packet.data)
    }

    func testLiveCodecChangesRequireNewKeyframeAndRebuildDecoder() throws {
        let decoder = HardwareVideoDecoder(), pixels = try pixel()
        for codec: LANVideoCodec in [.h264, .hevc, .h264] {
            let encoder = HardwareVideoEncoder(codec: codec)
            let packet = try XCTUnwrap(encoder.encode(pixels, time: .zero, quality: .efficient))
            XCTAssertNotNil(decoder.decode(packet)); XCTAssertFalse(decoder.failed)
        }
    }
}

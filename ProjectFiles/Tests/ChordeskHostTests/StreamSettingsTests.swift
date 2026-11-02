import XCTest
import CoreVideo
import CoreMedia
@testable import ChordeskHost

final class StreamSettingsTests: XCTestCase {
    func testIdleServiceAndPresenceQueriesDoNotAcquireCaptureAndOldViewerCannotRestartIt() throws {
        var lifetime = ViewerCaptureLifetime()
        XCTAssertNil(lifetime.begin(authenticatedViewer: false))
        XCTAssertNil(lifetime.lease)
        let first = try XCTUnwrap(lifetime.begin(authenticatedViewer: true))
        XCTAssertTrue(lifetime.accepts(first))
        lifetime.end()
        XCTAssertFalse(lifetime.accepts(first))
        XCTAssertFalse(lifetime.accepts(nil))
        let second = try XCTUnwrap(lifetime.begin(authenticatedViewer: true))
        XCTAssertNotEqual(second, first)
        XCTAssertFalse(lifetime.accepts(first))
        XCTAssertTrue(lifetime.accepts(second))
    }
    func testIndependentControlsKeepAspectRatioAndNeverUpscale() {
        var value = StreamSettings()
        XCTAssertEqual(value.captureSize(pixels: CGSize(width: 3840, height: 2160)), CGSize(width: 1280, height: 720))
        value.fps = 120; value.bitrate = 20_000_000
        XCTAssertEqual(value.resolution, .p720)
        XCTAssertEqual(value.captureSize(pixels: CGSize(width: 3840, height: 2160)), CGSize(width: 1280, height: 720))
        for resolution in StreamResolution.allCases {
            value.resolution = resolution
            let source = CGSize(width: 6144, height: 4096), size = value.captureSize(pixels: source)
            XCTAssertEqual(size.width / size.height, 1.5, accuracy: 0.006)
            XCTAssertLessThanOrEqual(size.height, CGFloat(resolution.rawValue))
            XCTAssertLessThanOrEqual(size.width, CGFloat(resolution.longEdge))
            XCTAssertEqual(value.captureSize(pixels: CGSize(width: 160, height: 90)), CGSize(width: 160, height: 90))
        }
        value.resolution = .p1080
        XCTAssertEqual(value.captureSize(pixels: CGSize(width: 2160, height: 3840)), CGSize(width: 1080, height: 1920))
        XCTAssertEqual(value.captureSize(pixels: CGSize(width: CGFloat.infinity, height: 100)), CGSize(width: 2, height: 2))
    }

    func testUntrustedSettingsRejectExcessiveRatesAndLegacyDecodeStillWorks() throws {
        for fps in [-1, 0, 144, 240, Int.max] { XCTAssertFalse(StreamSettings(fps: fps).isValid) }
        for bitrate in [-1, 0, 499_999, 80_000_001, Int.max] { XCTAssertFalse(StreamSettings(bitrate: bitrate).isValid) }
        let old = try JSONDecoder().decode(LANStatus.self, from: Data(#"{"version":1,"name":"Old Mac","width":1920,"height":1080,"canControl":false,"message":""}"#.utf8))
        XCTAssertNil(old.streamSettings); XCTAssertNil(old.supportsBandwidthProbe)
        XCTAssertLessThanOrEqual(StreamSettings.legacy(.experimental144).fps, 120)
    }

    func testPreferencesMigrateWithoutReplacingExplicitSelections() throws {
        let name = "chordesk-stream-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertEqual(StreamSettings.stored(defaults), StreamSettings())
        defaults.set("ultra", forKey: "DuoVideoQuality")
        XCTAssertEqual(StreamSettings.stored(defaults).resolution, .p2160)
        let chosen = StreamSettings(resolution: .p480, fps: 90, bitrate: 2_000_000)
        chosen.save(defaults)
        XCTAssertEqual(StreamSettings.stored(defaults), chosen)
        defaults.set("h264", forKey: "videoCodecV2")
        XCTAssertEqual(LANVideoCodec.storedPreference(defaults), .h264)
    }

    func testBandwidthSampleRejectsForeignIDAndRecommendsWithHeadroom() throws {
        let id = UUID(), bytes = BandwidthProbe.chunk(id: id)
        XCTAssertEqual(BandwidthProbe.payloadCount(bytes, id: id), BandwidthProbe.chunkBytes)
        XCTAssertNil(BandwidthProbe.payloadCount(bytes, id: UUID()))
        XCTAssertNil(BandwidthProbe.payloadCount(bytes + Data([0]), id: id))
        XCTAssertNil(StreamRecommendation.make(bytes: Int.max, elapsed: 1, resolution: .p720, rtt: nil))
        XCTAssertNil(StreamRecommendation.make(bytes: BandwidthProbe.maximumBytes, elapsed: .nan, resolution: .p720, rtt: nil))
        let fast = try XCTUnwrap(StreamRecommendation.make(bytes: BandwidthProbe.maximumBytes, elapsed: 0.1, resolution: .p1080, rtt: 20))
        let slow = try XCTUnwrap(StreamRecommendation.make(bytes: BandwidthProbe.maximumBytes, elapsed: 2, resolution: .p1080, rtt: 20))
        XCTAssertLessThan(fast.bitrate, Int(fast.measuredMbps * 1_000_000))
        XCTAssertGreaterThan(fast.fps, slow.fps)
        let laggy = try XCTUnwrap(StreamRecommendation.make(bytes: BandwidthProbe.maximumBytes, elapsed: 0.1, resolution: .p720, rtt: 200))
        XCTAssertLessThanOrEqual(laggy.fps, 30)
        let displayLimited = try XCTUnwrap(StreamRecommendation.make(bytes: BandwidthProbe.maximumBytes, elapsed: 0.01,
            resolution: .p720, rtt: 10, sourceFPS: 60))
        XCTAssertLessThanOrEqual(displayLimited.fps, 60)
    }

    func testHardwareCodecReconfigurationStartsNewStreamAtNewBitrateAndFPS() throws {
        var output: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, 320, 180, kCVPixelFormatType_32BGRA,
            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &output), kCVReturnSuccess)
        let pixel = try XCTUnwrap(output), encoder = HardwareVideoEncoder(codec: .hevc), decoder = HardwareVideoDecoder()
        var previous: UUID?
        for (index, fps) in [15, 60, 120].enumerated() {
            let packet = try XCTUnwrap(encoder.encode(pixel, time: CMTime(value: Int64(index), timescale: 1),
                quality: StreamSettings(fps: fps, bitrate: 1_000_000 * (index + 1))))
            XCTAssertTrue(packet.header.keyframe)
            XCTAssertNotEqual(packet.header.stream, previous)
            previous = packet.header.stream
            XCTAssertNotNil(decoder.decode(packet))
        }
    }
}

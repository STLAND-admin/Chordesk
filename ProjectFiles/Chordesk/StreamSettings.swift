import Foundation
import CoreGraphics
import SwiftUI

enum StreamResolution: Int, Codable, CaseIterable, Identifiable {
    case p480 = 480, p720 = 720, p1080 = 1080, p1440 = 1440, p2160 = 2160
    var id: Int { rawValue }
    var title: String { "\(rawValue)p" }
    var longEdge: Int { switch self { case .p480: 854; case .p720: 1280; case .p1080: 1920; case .p1440: 2560; case .p2160: 3840 } }
}

/// Transmission dimensions, not the Mac's logical display resolution or DPI.
/// Keep all three controls independent and validate again at the remote boundary.
struct StreamSettings: Codable, Equatable {
    static let storageKey = "ChordeskStreamSettingsV1"
    static let frameRates = [15, 24, 30, 60, 90, 120]
    static let bitrateRange = 500_000...80_000_000
    var resolution: StreamResolution = .p720
    var fps: Int = 15
    var bitrate: Int = 1_500_000
    var isValid: Bool { Self.frameRates.contains(fps) && Self.bitrateRange.contains(bitrate) }
    var framesPerSecond: Int32 { Int32(fps) }
    var jpegQuality: Double { resolution.rawValue >= 1080 ? 0.86 : 0.65 }
    var detail: String { "\(resolution.title) · 上限 \(fps) fps · 目标 \(String(format: "%.1f", Double(bitrate) / 1_000_000)) Mbps" }
    func captureSize(pixels: CGSize) -> CGSize {
        guard pixels.width.isFinite, pixels.height.isFinite, pixels.width > 0, pixels.height > 0 else { return CGSize(width: 2, height: 2) }
        let scale = min(1, CGFloat(resolution.longEdge) / max(pixels.width, pixels.height), CGFloat(resolution.rawValue) / min(pixels.width, pixels.height))
        return CGSize(width: max(2, Int(pixels.width * scale) / 2 * 2), height: max(2, Int(pixels.height * scale) / 2 * 2))
    }
    static func legacy(_ value: LANVideoQuality) -> Self {
        let resolution: StreamResolution = value.maximumEdge >= 3840 ? .p2160 : value.maximumEdge >= 2560 ? .p1440 : .p720
        return .init(resolution: resolution, fps: min(120, Int(value.framesPerSecond)), bitrate: value.h264Bitrate)
    }
    static func stored(_ defaults: UserDefaults) -> Self {
        if let data = defaults.data(forKey: storageKey), let value = try? JSONDecoder().decode(Self.self, from: data), value.isValid { return value }
        if let raw = defaults.string(forKey: "DuoVideoQuality"), let old = LANVideoQuality(rawValue: raw) { return .legacy(old) }
        return .init()
    }
    func save(_ defaults: UserDefaults) { if isValid, let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.storageKey) } }
}

struct BandwidthProbeRequest: Codable { var id: UUID }
struct BandwidthProbeEnd: Codable { var id: UUID; var bytes: Int }
enum BandwidthProbe {
    static let maximumBytes = 512 * 1024
    static let chunkBytes = 16 * 1024
    static let maximumDuration: TimeInterval = 2
    static func chunk(id: UUID) -> Data { Data(id.uuidString.utf8) + Data(repeating: 0x5a, count: chunkBytes) }
    static func payloadCount(_ data: Data, id: UUID) -> Int? {
        guard data.count == 36 + chunkBytes, data.prefix(36) == Data(id.uuidString.utf8) else { return nil }
        return chunkBytes
    }
}

/// A bounded end-to-end sample over the authenticated Mac→phone route, including
/// RTT and competing video traffic. A conservative recommendation, not ISP speed.
struct StreamRecommendation: Equatable {
    var measuredMbps: Double
    var bitrate: Int
    var fps: Int
    static func make(bytes: Int, elapsed: TimeInterval, resolution: StreamResolution, rtt: Double?, sourceFPS: Double? = nil) -> Self? {
        guard bytes >= BandwidthProbe.chunkBytes, bytes <= BandwidthProbe.maximumBytes, elapsed.isFinite, elapsed >= 0.005 else { return nil }
        let measured = Double(bytes) * 8 / elapsed / 1_000_000
        let budget = min(40, max(0.5, measured * 0.6))
        let base: Double = switch resolution { case .p480: 1; case .p720: 2; case .p1080: 4; case .p1440: 7; case .p2160: 14 }
        let sourceCeiling = sourceFPS.flatMap { $0.isFinite && $0 > 0 ? min(120, max(15, Int(min(120, $0).rounded()))) : nil } ?? 120
        let ceiling = min(sourceCeiling, (rtt ?? 0) > 150 ? 30 : 120)
        let fps = [15, 30, 60, 90, 120].last { $0 <= ceiling && base * Double($0) / 30 <= budget } ?? 15
        let target = min(budget, base * Double(fps) / 30)
        return .init(measuredMbps: measured, bitrate: max(500_000, Int(target * 1_000_000 / 100_000) * 100_000), fps: fps)
    }
}

struct StreamSettingsControls: View {
    let settings: StreamSettings
    var onChange: (StreamSettings) -> Void
    @State private var pendingBitrate: Double?
    var body: some View {
        Picker("传输分辨率", selection: Binding(get: { settings.resolution }, set: { var value = settings; value.resolution = $0; onChange(value) })) {
            ForEach(StreamResolution.allCases) { Text($0.title).tag($0) }
        }
#if os(iOS)
        .pickerStyle(.navigationLink)
#else
        .pickerStyle(.menu)
#endif
        .accessibilityIdentifier("stream-resolution")
        Picker("帧率上限", selection: Binding(get: { settings.fps }, set: { var value = settings; value.fps = $0; onChange(value) })) {
            ForEach(StreamSettings.frameRates, id: \.self) { Text("\($0) fps").tag($0) }
        }
#if os(iOS)
        .pickerStyle(.navigationLink)
#else
        .pickerStyle(.menu)
#endif
        .accessibilityIdentifier("stream-fps")
        VStack(alignment: .leading) {
            Text("目标码率 \(pendingBitrate ?? Double(settings.bitrate) / 1_000_000, specifier: "%.1f") Mbps")
            Slider(value: Binding(get: { pendingBitrate ?? Double(settings.bitrate) / 1_000_000 }, set: { pendingBitrate = $0 }), in: 0.5...80, step: 0.5,
                   onEditingChanged: { editing in
                       if !editing, let pendingBitrate {
                           var value = settings; value.bitrate = Int(pendingBitrate * 1_000_000)
                           self.pendingBitrate = nil; onChange(value)
                       }
                   }) { Text("目标码率") }
                .accessibilityIdentifier("stream-bitrate")
        }
        Text("等比缩放且不放大源画面；分辨率不改变 Mac 的文字大小。实际帧率受源屏、硬件编解码、网络和 ProMotion 限制；静止画面会减少帧数。码率为目标均值，JPEG 回退不支持固定码率。")
            .font(.caption).foregroundStyle(.secondary)
    }
}

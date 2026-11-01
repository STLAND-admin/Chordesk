import Foundation
import VideoToolbox
import CoreImage

/// AVCC access unit plus bounded metadata; no video is base64 encoded.
struct H264Packet {
    struct Header: Codable, Equatable {
        var version = 1
        var stream: UUID
        var sequence: UInt64
        var keyframe: Bool
        var width: Int
        var height: Int
        var parameterSets: [Data]
    }
    var header: Header
    var bytes: Data
    static let maximumBytes = 4 * 1024 * 1024 - 180_004
    static func nalUnitsValid(_ bytes: Data) -> Bool {
        var offset = 0, count = 0
        while offset < bytes.count {
            guard bytes.count - offset >= 4, count < 1024 else { return false }
            let length = bytes[offset..<(offset + 4)].reduce(0) { ($0 << 8) | Int($1) }
            offset += 4; count += 1
            guard length > 0, length <= bytes.count - offset else { return false }
            offset += length
        }
        return count > 0
    }
    var valid: Bool {
        header.version == 1 && header.width > 0 && header.height > 0 && header.width <= 4096 && header.height <= 4096
        && bytes.count <= Self.maximumBytes && Self.nalUnitsValid(bytes)
        && (header.keyframe ? header.parameterSets.count == 2 : header.parameterSets.isEmpty)
        && header.parameterSets.allSatisfy { !$0.isEmpty && $0.count < 65536 }
    }
    var data: Data? {
        guard valid, let metadata = try? JSONEncoder().encode(header), metadata.count < 180_000 else { return nil }
        var output = Data(), length = UInt32(metadata.count).bigEndian
        withUnsafeBytes(of: &length) { output.append(contentsOf: $0) }
        output.append(metadata); output.append(bytes)
        return output
    }
    init(header: Header, bytes: Data) { self.header = header; self.bytes = bytes }
    init?(_ data: Data) {
        guard data.count >= 5, data.count <= Self.maximumBytes + 180_004 else { return nil }
        let length = data.prefix(4).reduce(0) { ($0 << 8) | Int($1) }
        guard length > 0, length < 180_000, length < data.count - 4,
              let header = try? JSONDecoder().decode(Header.self, from: data.subdata(in: 4..<(4 + length))) else { return nil }
        self.header = header; bytes = data.subdata(in: (4 + length)..<data.count)
        guard valid else { return nil }
    }
}

/// Call only on the capture queue. A single input is completed before accepting
/// the next one, keeping the hardware pipeline bounded and callback lifetimes safe.
#if os(macOS)
final class H264Encoder {
    private var session: VTCompressionSession?
    private var dimensions = CGSize.zero
    private var quality: LANVideoQuality?
    private var stream = UUID()
    private var sequence: UInt64 = 0
    private(set) var failed = false
    var forceKeyframe = true
    func invalidate() {
        if let session { VTCompressionSessionInvalidate(session) }
        session = nil; dimensions = .zero; quality = nil; stream = UUID(); sequence = 0; forceKeyframe = true
    }
    deinit { invalidate() }
    private func prepare(width: Int, height: Int, quality: LANVideoQuality) -> Bool {
        if session != nil, dimensions == CGSize(width: width, height: height), self.quality == quality { return true }
        invalidate()
        var created: VTCompressionSession?
        let spec = [kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder: true,
                    kVTVideoEncoderSpecification_EnableLowLatencyRateControl: true] as CFDictionary
        guard VTCompressionSessionCreate(allocator: kCFAllocatorDefault, width: Int32(width), height: Int32(height),
            codecType: kCMVideoCodecType_H264, encoderSpecification: spec, imageBufferAttributes: nil,
            compressedDataAllocator: nil, outputCallback: nil, refcon: nil, compressionSessionOut: &created) == noErr,
              let created else { failed = true; return false }
        session = created
        let properties: [(CFString, CFTypeRef)] = [
            (kVTCompressionPropertyKey_RealTime, kCFBooleanTrue),
            (kVTCompressionPropertyKey_AllowFrameReordering, kCFBooleanFalse),
            (kVTCompressionPropertyKey_ProfileLevel, kVTProfileLevel_H264_ConstrainedBaseline_AutoLevel),
            (kVTCompressionPropertyKey_AverageBitRate, NSNumber(value: quality.h264Bitrate)),
            (kVTCompressionPropertyKey_ExpectedFrameRate, NSNumber(value: quality.framesPerSecond)),
            (kVTCompressionPropertyKey_MaxKeyFrameInterval, NSNumber(value: quality.framesPerSecond * 2)),
            (kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration, NSNumber(value: 2))
        ]
        for (key, value) in properties {
            guard VTSessionSetProperty(created, key: key, value: value) == noErr else { invalidate(); failed = true; return false }
        }
        guard VTCompressionSessionPrepareToEncodeFrames(created) == noErr else { invalidate(); failed = true; return false }
        dimensions = CGSize(width: width, height: height); self.quality = quality; failed = false
        return true
    }
    func encode(_ pixel: CVPixelBuffer, time: CMTime, quality: LANVideoQuality) -> H264Packet? {
        let width = CVPixelBufferGetWidth(pixel), height = CVPixelBufferGetHeight(pixel)
        guard prepare(width: width, height: height, quality: quality), let session else { return nil }
        let lock = NSLock()
        var sample: CMSampleBuffer?, outputError = noErr
        let properties = forceKeyframe ? [kVTEncodeFrameOptionKey_ForceKeyFrame: true] as CFDictionary : nil
        forceKeyframe = false
        let result = VTCompressionSessionEncodeFrame(session, imageBuffer: pixel, presentationTimeStamp: time,
            duration: CMTime(value: 1, timescale: quality.framesPerSecond), frameProperties: properties, infoFlagsOut: nil) { status, _, buffer in
                lock.lock(); sample = buffer; outputError = status; lock.unlock()
            }
        let flush = VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
        lock.lock(); let buffer = sample, error = outputError; lock.unlock()
        guard result == noErr, flush == noErr, error == noErr else { failed = true; return nil }
        guard let buffer else { forceKeyframe = true; return nil }
        guard let block = buffer.dataBuffer, let format = buffer.formatDescription else { failed = true; return nil }
        let length = CMBlockBufferGetDataLength(block)
        guard length > 0, length <= H264Packet.maximumBytes else { failed = true; return nil }
        var bytes = Data(count: length)
        let copied = bytes.withUnsafeMutableBytes { CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: $0.baseAddress!) }
        guard copied == noErr else { failed = true; return nil }
        let keyframe = (CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: false) as? [[String: Any]])?.first?[kCMSampleAttachmentKey_NotSync as String] as? Bool != true
        var sets: [Data] = []
        if keyframe {
            for index in 0..<2 {
                var pointer: UnsafePointer<UInt8>?, size = 0
                guard CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, parameterSetIndex: index,
                    parameterSetPointerOut: &pointer, parameterSetSizeOut: &size, parameterSetCountOut: nil, nalUnitHeaderLengthOut: nil) == noErr,
                      let pointer, size > 0, size < 65536 else { failed = true; return nil }
                sets.append(Data(bytes: pointer, count: size))
            }
        }
        sequence &+= 1
        let packet = H264Packet(header: .init(stream: stream, sequence: sequence, keyframe: keyframe, width: width, height: height, parameterSets: sets), bytes: bytes)
        guard packet.valid else { failed = true; return nil }
        return packet
    }
}

#endif

/// Decode synchronously on the transport's background queue. No accumulated
/// display queue: only the latest decoded image is handed to the UI.
final class H264Decoder {
    private var session: VTDecompressionSession?
    private var format: CMVideoFormatDescription?
    private var stream: UUID?
    private var sequence: UInt64?
    private var dimensions = CGSize.zero
    private let context = CIContext(options: [.cacheIntermediates: false])
    private(set) var needsKeyframe = true
    private(set) var failed = false
    func invalidate() {
        if let session { VTDecompressionSessionInvalidate(session) }
        session = nil; format = nil; stream = nil; sequence = nil; needsKeyframe = true; failed = false
    }
    deinit { invalidate() }
    func decode(_ packet: H264Packet) -> CGImage? {
        guard packet.valid else { failed = true; return nil }
        let h = packet.header
        if h.stream != stream || (sequence.map { $0 &+ 1 != h.sequence } ?? true) { needsKeyframe = true }
        if needsKeyframe && !h.keyframe { return nil }
        if h.keyframe {
            invalidate()
            let a = h.parameterSets[0], b = h.parameterSets[1]
            let status = a.withUnsafeBytes { ap in b.withUnsafeBytes { bp in
                let pointers = [ap.baseAddress!.assumingMemoryBound(to: UInt8.self), bp.baseAddress!.assumingMemoryBound(to: UInt8.self)]
                return CMVideoFormatDescriptionCreateFromH264ParameterSets(allocator: kCFAllocatorDefault, parameterSetCount: 2,
                    parameterSetPointers: pointers, parameterSetSizes: [a.count, b.count], nalUnitHeaderLength: 4, formatDescriptionOut: &format)
            } }
            guard status == noErr, let format else { failed = true; return nil }
            let size = CMVideoFormatDescriptionGetDimensions(format)
            guard size.width == h.width, size.height == h.height else { failed = true; return nil }
            let spec = [kVTVideoDecoderSpecification_RequireHardwareAcceleratedVideoDecoder: true] as CFDictionary
            let attrs = [kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA] as CFDictionary
            guard VTDecompressionSessionCreate(allocator: kCFAllocatorDefault, formatDescription: format, decoderSpecification: spec,
                imageBufferAttributes: attrs, outputCallback: nil, decompressionSessionOut: &session) == noErr else { failed = true; return nil }
            stream = h.stream; dimensions = CGSize(width: h.width, height: h.height); needsKeyframe = false
        }
        guard let session, let format, dimensions == CGSize(width: h.width, height: h.height) else { failed = true; return nil }
        var block: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: packet.bytes.count,
            blockAllocator: kCFAllocatorDefault, customBlockSource: nil, offsetToData: 0, dataLength: packet.bytes.count,
            flags: 0, blockBufferOut: &block) == noErr, let block else { failed = true; return nil }
        let copied = packet.bytes.withUnsafeBytes { CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: packet.bytes.count) }
        var sample: CMSampleBuffer?
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: CMTime(value: Int64(h.sequence % UInt64(Int64.max)), timescale: 1000), decodeTimeStamp: .invalid)
        var size = packet.bytes.count
        guard copied == noErr, CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: format,
            sampleCount: 1, sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleSizeEntryCount: 1, sampleSizeArray: &size, sampleBufferOut: &sample) == noErr,
              let sample else { failed = true; return nil }
        let lock = NSLock()
        var pixels: CVPixelBuffer?, outputError = noErr
        let result = VTDecompressionSessionDecodeFrame(session, sampleBuffer: sample, flags: [], infoFlagsOut: nil) { status, _, image, _, _ in
            lock.lock(); pixels = image; outputError = status; lock.unlock()
        }
        let wait = VTDecompressionSessionWaitForAsynchronousFrames(session)
        lock.lock(); let decoded = pixels, error = outputError; lock.unlock()
        guard result == noErr, wait == noErr, error == noErr, let decoded else { failed = true; return nil }
        sequence = h.sequence
        let image = CIImage(cvPixelBuffer: decoded)
        guard let output = context.createCGImage(image, from: image.extent) else { failed = true; return nil }
        return output
    }
}

extension LANVideoQuality {
    var h264Bitrate: Int {
        switch self {
        case .efficient: 1_500_000
        case .sharp: 6_000_000
        case .ultra: 12_000_000
        case .responsive60: 4_000_000
        case .experimental120, .experimental144: 5_000_000
        }
    }
}

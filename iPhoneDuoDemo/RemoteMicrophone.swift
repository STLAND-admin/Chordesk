import Foundation
import AVFoundation

struct LANMicrophoneRequest: Codable {
    var streamID: UUID
    var enabled: Bool
}

struct LANMicrophoneState: Codable {
    var streamID: UUID?
    var available: Bool
    var active: Bool
    var message: String
}

/// Fixed-format voice packets: UUID, big-endian sequence, then 20 ms of
/// little-endian signed PCM. No arbitrary codec, device or file from the peer.
struct MicrophonePacket {
    static let sampleRate = 24_000.0
    static let frames = 480
    static let byteCount = 16 + 4 + frames * 2
    var streamID: UUID
    var sequence: UInt32
    var pcm: Data

    var encoded: Data {
        var uuid = streamID.uuid
        var data = withUnsafeBytes(of: &uuid) { Data($0) }
        var seq = sequence.bigEndian
        withUnsafeBytes(of: &seq) { data.append(contentsOf: $0) }
        data.append(pcm)
        return data
    }

    init(streamID: UUID, sequence: UInt32, pcm: Data) {
        self.streamID = streamID; self.sequence = sequence; self.pcm = pcm
    }
    init?(_ data: Data) {
        guard data.count == Self.byteCount else { return nil }
        var uuid: uuid_t = (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
        withUnsafeMutableBytes(of: &uuid) { _ = data.copyBytes(to: $0, from: 0..<16) }
        streamID = UUID(uuid: uuid)
        sequence = data[16..<20].reduce(0) { ($0 << 8) | UInt32($1) }
        pcm = Data(data[20...])
    }
}

/// A fresh stream ID is required after stop, timeout, route change or reconnect.
struct MicrophoneReceiveGate {
    private(set) var streamID: UUID?
    private var lastSequence: UInt32?
    mutating func start(_ id: UUID) { streamID = id; lastSequence = nil }
    mutating func stop() { streamID = nil; lastSequence = nil }
    mutating func accept(_ packet: MicrophonePacket) -> Bool {
        guard packet.pcm.count == MicrophonePacket.frames * 2,
              packet.streamID == streamID,
              lastSequence.map({ packet.sequence > $0 }) ?? true else { return false }
        lastSequence = packet.sequence
        return true
    }
}

#if os(iOS)
import UIKit

/// Owned by LANClient. The audio tap converts off the main actor. No recording
/// file, background capture, or microphone permission request during app launch.
@MainActor
final class PhoneMicrophone {
    private var engine: AVAudioEngine?
    private var observers: [NSObjectProtocol] = []
    private var stopped: (() -> Void)?

    static func permission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
        }
    }

    func start(streamID: UUID, send: @escaping (Data) -> Void, interrupted: @escaping () -> Void) throws {
        stop()
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [.allowBluetoothHFP])
        try session.setPreferredSampleRate(48_000)
        try session.setPreferredIOBufferDuration(0.02)
        try session.setActive(true)
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let source = input.outputFormat(forBus: 0)
        guard source.sampleRate > 0, source.channelCount > 0,
              let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                  sampleRate: MicrophonePacket.sampleRate, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: source, to: format) else {
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            throw NSError(domain: "ChordeskAudio", code: 1, userInfo: [NSLocalizedDescriptionKey: "麦克风音频格式不可用"])
        }
        // All mutable conversion state belongs to the serial input tap.
        let encoder = MicrophonePCMEncoder(converter: converter, format: format, streamID: streamID, send: send)
        input.installTap(onBus: 0, bufferSize: 960, format: source) { buffer, _ in encoder.consume(buffer) }
        self.engine = engine
        do { try engine.start() } catch { stop(); throw error }
        stopped = interrupted
        for name in [AVAudioSession.interruptionNotification, AVAudioSession.routeChangeNotification,
                     AVAudioSession.mediaServicesWereResetNotification, UIApplication.didEnterBackgroundNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                // Category changes caused by our own start aren't route loss.
                if note.name == AVAudioSession.routeChangeNotification,
                   let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                   raw == AVAudioSession.RouteChangeReason.categoryChange.rawValue { return }
                Task { @MainActor in
                    guard let self else { return }
                    let callback = self.stopped; self.stop(); callback?()
                }
            })
        }
    }

    func stop() {
        observers.forEach(NotificationCenter.default.removeObserver); observers.removeAll()
        stopped = nil
        if let engine {
            engine.inputNode.removeTap(onBus: 0); engine.stop()
            self.engine = nil
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
}

private final class MicrophonePCMEncoder {
    let converter: AVAudioConverter
    let format: AVAudioFormat
    let streamID: UUID
    let send: (Data) -> Void
    private var pending = Data()
    private var sequence: UInt32 = 0
    init(converter: AVAudioConverter, format: AVAudioFormat, streamID: UUID, send: @escaping (Data) -> Void) {
        self.converter = converter; self.format = format; self.streamID = streamID; self.send = send
    }
    func consume(_ input: AVAudioPCMBuffer) {
        let capacity = AVAudioFrameCount(ceil(Double(input.frameLength) * format.sampleRate / input.format.sampleRate) + 32)
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return }
        var supplied = false
        var error: NSError?
        let result = converter.convert(to: output, error: &error) { _, status in
            if supplied { status.pointee = .noDataNow; return nil }
            supplied = true; status.pointee = .haveData; return input
        }
        guard result != .error, error == nil, let samples = output.floatChannelData?[0] else { return }
        for index in 0..<Int(output.frameLength) {
            let value = samples[index].isFinite ? min(1, max(-1, samples[index])) : 0
            var pcm = Int16(value * 32767).littleEndian
            withUnsafeBytes(of: &pcm) { pending.append(contentsOf: $0) }
        }
        let size = MicrophonePacket.frames * 2
        while pending.count >= size {
            send(MicrophonePacket(streamID: streamID, sequence: sequence, pcm: Data(pending.prefix(size))).encoded)
            pending.removeFirst(size)
            sequence &+= 1
        }
    }
}
#endif

#if os(macOS)
import CoreAudio
import AudioToolbox

struct MicrophoneDestination: Identifiable {
    var id: String
    var name: String
    var device: AudioDeviceID
}

enum MicrophoneDevices {
    /// Only duplex virtual devices. Never silently fall back to a speaker or
    /// change the Mac's system default input/output device.
    static func available() -> [MicrophoneDestination] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return [] }
        var devices = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &devices) == noErr else { return [] }
        return devices.compactMap { device in
            var transport: UInt32 = 0; var bytes = UInt32(MemoryLayout<UInt32>.size)
            var property = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyTransportType, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            guard AudioObjectGetPropertyData(device, &property, 0, nil, &bytes, &transport) == noErr,
                  transport == kAudioDeviceTransportTypeVirtual,
                  channels(device, scope: kAudioDevicePropertyScopeOutput) > 0,
                  channels(device, scope: kAudioDevicePropertyScopeInput) > 0,
                  let uid = string(device, selector: kAudioDevicePropertyDeviceUID),
                  let name = string(device, selector: kAudioObjectPropertyName) else { return nil }
            return MicrophoneDestination(id: uid, name: name, device: device)
        }
    }
    private static func string(_ device: AudioDeviceID, selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?; var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }
    private static func channels(_ device: AudioDeviceID, scope: AudioObjectPropertyScope) -> Int {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let memory = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { memory.deallocate() }
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, memory) == noErr else { return 0 }
        return UnsafeMutableAudioBufferListPointer(memory.assumingMemoryBound(to: AudioBufferList.self)).reduce(0) { $0 + Int($1.mNumberChannels) }
    }
}

@MainActor
final class MacMicrophonePlayer {
    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var queued = 0
    private var generation = UUID()
    private let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: MicrophonePacket.sampleRate, channels: 1, interleaved: false)!
    private var route: AudioDeviceID?
    private var configurationObserver: NSObjectProtocol?
    var routeIsValid: Bool {
        guard let engine, let route, let unit = engine.outputNode.audioUnit else { return false }
        var current = AudioDeviceID(0); var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        return engine.isRunning && AudioUnitGetProperty(unit, kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global, 0, &current, &size) == noErr && current == route
            && MicrophoneDevices.available().contains { $0.device == route }
    }
    func start(device: AudioDeviceID) throws {
        stop()
        let engine = AVAudioEngine()
        guard let unit = engine.outputNode.audioUnit else { throw LANWireError.malformed }
        var id = device
        let result = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global,
                                         0, &id, UInt32(MemoryLayout<AudioDeviceID>.size))
        guard result == noErr else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(result)) }
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        self.engine = engine; self.player = player; route = device
        do { try engine.start(); player.play() } catch { stop(); throw error }
        configurationObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil) { _ in
            // Stop immediately if Core Audio attempts to reroute. Never continue
            // a remote microphone on an implicit default speaker destination.
            engine.stop()
        }
    }
    func play(_ packet: MicrophonePacket) {
        guard let player, queued < 6,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(MicrophonePacket.frames)),
              let samples = buffer.floatChannelData?[0] else { return }
        buffer.frameLength = AVAudioFrameCount(MicrophonePacket.frames)
        for i in 0..<MicrophonePacket.frames {
            samples[i] = Float(Int16(bitPattern: UInt16(packet.pcm[i * 2]) | UInt16(packet.pcm[i * 2 + 1]) << 8)) / 32768
        }
        queued += 1
        let token = generation
        player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                self.queued = max(0, self.queued - 1)
            }
        }
    }
    func stop() {
        generation = UUID(); queued = 0
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
        configurationObserver = nil
        player?.stop(); engine?.stop(); player = nil; engine = nil; route = nil
    }
}
#endif

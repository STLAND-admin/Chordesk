import Foundation
import CoreGraphics

enum ScrollTuning {
    static let key = "ChordeskScrollInertiaV1"
    static let defaultCoefficient = 1.0
    static func coefficient(_ value: Double) -> Double { value.isFinite ? min(max(value, 0), 2) : defaultCoefficient }
}

/// Positions/deltas are normalized on the phone; timestamps come from UIKit,
/// never from packet arrival time. Only the host generates momentum events.
struct ScrollGestureEvent: Codable, Equatable {
    enum Phase: String, Codable { case began, changed, ended, cancelled }
    enum Mode: String, Codable { case direct, trackpad }
    var id: UUID
    var phase: Phase
    var mode: Mode
    var timestamp: Double
    var delta: CGPoint = .zero
    var velocity: CGPoint = .zero
    var anchor: CGPoint = CGPoint(x: 0.5, y: 0.5)
    var coefficient = ScrollTuning.defaultCoefficient
    var isValid: Bool {
        timestamp.isFinite && timestamp >= 0 && timestamp < 1e12
            && delta.x.isFinite && delta.y.isFinite && abs(delta.x) <= 1 && abs(delta.y) <= 1
            && velocity.x.isFinite && velocity.y.isFinite && abs(velocity.x) <= 8 && abs(velocity.y) <= 8
            && anchor.x.isFinite && anchor.y.isFinite && (0...1).contains(anchor.x) && (0...1).contains(anchor.y)
            && coefficient.isFinite && (0...2).contains(coefficient)
    }
}

/// Shared by direct touch and trackpad. A pause before lifting suppresses a flick.
struct ScrollGestureTracker {
    private var sample: ScrollGestureEvent?
    private var terminal: ScrollGestureEvent?
    private var lastTime = 0.0
    private var pending = CGPoint.zero
    private var speed = CGPoint.zero
    mutating func begin(mode: ScrollGestureEvent.Mode, at time: Double, anchor: CGPoint = CGPoint(x: 0.5, y: 0.5)) -> ScrollGestureEvent {
        lastTime = time; pending = .zero; speed = .zero; terminal = nil
        let value = ScrollGestureEvent(id: UUID(), phase: .began, mode: mode, timestamp: time, anchor: anchor)
        sample = value
        return value
    }
    mutating func move(delta: CGPoint, at time: Double) -> ScrollGestureEvent? {
        guard var value = sample, time.isFinite, time >= lastTime,
              delta.x.isFinite, delta.y.isFinite else { return nil }
        pending.x += delta.x; pending.y += delta.y
        let dt = time - lastTime
        if dt >= 0.001 {
            let alpha = 1 - exp(-dt / 0.04)
            let vx = min(max(pending.x / dt, -8), 8), vy = min(max(pending.y / dt, -8), 8)
            if dt > 0.15 { speed = .zero }
            speed.x += (vx - speed.x) * alpha; speed.y += (vy - speed.y) * alpha
            pending = .zero; lastTime = time
        }
        value.phase = .changed; value.timestamp = time; value.delta = delta; value.velocity = speed
        sample = value
        return value
    }
    mutating func end(at time: Double) -> ScrollGestureEvent? {
        guard var value = sample else { return nil }
        let pause = max(0, time - lastTime)
        value.phase = .ended; value.timestamp = max(time, value.timestamp); value.delta = .zero
        value.velocity = pause > 0.12 ? .zero : CGPoint(x: speed.x * exp(-pause / 0.06), y: speed.y * exp(-pause / 0.06))
        sample = nil; terminal = value; pending = .zero; speed = .zero
        return value
    }
    mutating func cancel() -> ScrollGestureEvent? {
        guard var value = sample ?? terminal else { return nil }
        value.phase = .cancelled; value.delta = .zero; value.velocity = .zero
        sample = nil; terminal = nil; pending = .zero; speed = .zero
        return value
    }
}

struct ScrollPixelAccumulator {
    private var remainder = CGPoint.zero
    mutating func take(_ delta: CGPoint) -> (x: Int32, y: Int32) {
        remainder.x += delta.x; remainder.y += delta.y
        let x = Int32(min(max(remainder.x.rounded(.towardZero), -1500), 1500))
        let y = Int32(min(max(remainder.y.rounded(.towardZero), -1500), 1500))
        // Bound oversized input rather than retaining a backlog to replay later.
        remainder.x = abs(remainder.x) > 1500 ? 0 : remainder.x - Double(x)
        remainder.y = abs(remainder.y) > 1500 ? 0 : remainder.y - Double(y)
        return (x, y)
    }
}

/// Exponential decay integrated over elapsed time, independent of timer frequency.
struct ScrollMomentum {
    private(set) var velocity = CGPoint.zero
    private var tau = 0.3
    private var elapsed = 0.0
    var active: Bool { hypot(velocity.x, velocity.y) >= 8 && elapsed < 2 }
    init(velocity: CGPoint, coefficient: Double) {
        let value = ScrollTuning.coefficient(coefficient)
        tau = 0.10 + 0.20 * value
        self.velocity = value == 0 ? .zero : CGPoint(x: min(max(velocity.x, -6000), 6000), y: min(max(velocity.y, -6000), 6000))
    }
    mutating func advance(by dt: Double) -> CGPoint {
        guard active, dt.isFinite, dt > 0, dt <= 0.25 else { velocity = .zero; return .zero }
        let step = min(dt, 2 - elapsed), decay = exp(-step / tau)
        let result = CGPoint(x: velocity.x * tau * (1 - decay), y: velocity.y * tau * (1 - decay))
        velocity.x *= decay; velocity.y *= decay; elapsed += step
        return result
    }
}

#if os(macOS)
enum ScrollWheelPhase: Int64 { case none = 0, began = 1, changed = 2, ended = 4, cancelled = 8 }
enum ScrollMomentumPhase: Int64 { case none = 0, began = 1, changed = 2, ended = 3 }
struct ScrollWheelOutput {
    var x: Int32 = 0
    var y: Int32 = 0
    var location: CGPoint
    var phase: ScrollWheelPhase = .none
    var momentum: ScrollMomentumPhase = .none
}

/// The sole owner of the scroll sequence. Injection is supplied by LANMacInput;
/// tests use an in-memory sink and never post events to the user's desktop.
@MainActor
final class HostScrollDriver {
    private let allowed: () -> Bool
    private let emit: (ScrollWheelOutput) -> Bool
    private let clock: () -> Double
    private let automaticTimer: Bool
    private var timer: Timer?
    private var gesture: ScrollGestureEvent?
    private var location = CGPoint.zero
    private var scale = CGSize.zero
    private var pixels = ScrollPixelAccumulator()
    private var scrolling = false
    private var momentum: ScrollMomentum?
    private var momentumID: UUID?
    private var momentumStarted = false
    private var lastTick = 0.0
    private var timerEpoch: UInt64 = 0
    var isActive: Bool { gesture != nil || momentum != nil }

    init(automaticTimer: Bool = true, clock: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime },
         allowed: @escaping () -> Bool, emit: @escaping (ScrollWheelOutput) -> Bool) {
        self.automaticTimer = automaticTimer; self.clock = clock; self.allowed = allowed; self.emit = emit
    }
    @discardableResult
    func receive(_ value: ScrollGestureEvent, bounds: CGRect, pointer: CGPoint) -> Bool {
        guard value.isValid, allowed(), bounds.width > 0, bounds.height > 0 else { cancel(); return false }
        if value.phase == .began {
            cancel()
            gesture = value
            scale = value.mode == .direct ? bounds.size : CGSize(width: 1200, height: 1200)
            location = value.mode == .direct
                ? CGPoint(x: bounds.minX + value.anchor.x * (bounds.width - 1), y: bounds.minY + value.anchor.y * (bounds.height - 1))
                : pointer
            return true
        }
        if value.phase == .cancelled, value.id == momentumID { cancel(); return true }
        guard let previous = gesture, previous.id == value.id, previous.mode == value.mode,
              value.timestamp >= previous.timestamp else { return false }
        gesture = value
        switch value.phase {
        case .began: return false
        case .cancelled: cancel()
        case .changed:
            let delta = pixels.take(CGPoint(x: value.delta.x * scale.width, y: value.delta.y * scale.height))
            if delta.x != 0 || delta.y != 0 {
                guard emit(.init(x: delta.x, y: delta.y, location: location, phase: scrolling ? .changed : .began)) else { cancel(emitTerminal: false); return false }
                scrolling = true
            }
        case .ended:
            gesture = nil
            guard scrolling else { pixels = .init(); return true }
            scrolling = false
            guard emit(.init(location: location, phase: .ended)) else { cancel(emitTerminal: false); return false }
            let coast = ScrollMomentum(velocity: CGPoint(x: value.velocity.x * scale.width, y: value.velocity.y * scale.height), coefficient: value.coefficient)
            if coast.active {
                momentum = coast; momentumID = value.id; lastTick = clock()
                if automaticTimer {
                    let epoch = timerEpoch
                    let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
                        Task { @MainActor [weak self] in
                            guard let self, self.timerEpoch == epoch else { return }
                            self.tick(at: self.clock())
                        }
                    }
                    self.timer = timer; RunLoop.main.add(timer, forMode: .common)
                }
            } else { pixels = .init() }
        }
        return true
    }
    func tick(at time: Double) {
        guard allowed() else { cancel(emitTerminal: false); return }
        guard var coast = momentum else { return }
        let dt = time - lastTick; lastTick = time
        let delta = pixels.take(coast.advance(by: dt))
        momentum = coast
        if delta.x != 0 || delta.y != 0 {
            guard emit(.init(x: delta.x, y: delta.y, location: location, momentum: momentumStarted ? .changed : .began)) else { cancel(emitTerminal: false); return }
            momentumStarted = true
        }
        if !coast.active { cancel() }
    }
    func cancel(emitTerminal: Bool = true) {
        timerEpoch &+= 1
        timer?.invalidate(); timer = nil
        if emitTerminal && allowed() {
            if scrolling { _ = emit(.init(location: location, phase: .cancelled)) }
            if momentumStarted { _ = emit(.init(location: location, momentum: .ended)) }
        }
        gesture = nil; momentum = nil; momentumID = nil; momentumStarted = false; scrolling = false; pixels = .init()
    }
}
#endif

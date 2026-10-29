import SwiftUI

/// Normalized to the accessory's safe, available bounds, independent of device size.
struct RearActiveRegion: Codable, Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    static let minimum = 0.15
    static func centered(inset: Double) -> Self {
        let v = TouchpadTuning.edgeInset(inset)
        return .init(x: v, y: v, width: 1 - 2 * v, height: 1 - 2 * v)
    }
    var normalized: Self {
        func finite(_ v: Double, _ fallback: Double) -> Double { v.isFinite ? v : fallback }
        let w = min(1, max(Self.minimum, finite(width, 0.75)))
        let h = min(1, max(Self.minimum, finite(height, 0.75)))
        return .init(x: min(1 - w, max(0, finite(x, 0.125))), y: min(1 - h, max(0, finite(y, 0.125))), width: w, height: h)
    }
    static func decode(_ text: String, inset: Double) -> Self {
        guard let data = text.data(using: .utf8), let value = try? JSONDecoder().decode(Self.self, from: data) else { return .centered(inset: inset) }
        return value.normalized
    }
    var encoded: String { String(data: (try? JSONEncoder().encode(normalized)) ?? Data(), encoding: .utf8) ?? "" }
    func rect(in bounds: CGRect) -> CGRect {
        let v = normalized
        return CGRect(x: bounds.minX + bounds.width * v.x, y: bounds.minY + bounds.height * v.y,
                      width: bounds.width * v.width, height: bounds.height * v.height)
    }
    func translated(dx: Double, dy: Double) -> Self {
        let v = normalized
        return Self(x: v.x + dx, y: v.y + dy, width: v.width, height: v.height).normalized
    }
    enum Corner: String, CaseIterable { case topLeft, topRight, bottomLeft, bottomRight }
    func resized(_ corner: Corner, dx: Double, dy: Double) -> Self {
        let v = normalized
        let left = corner == .topLeft || corner == .bottomLeft
        let top = corner == .topLeft || corner == .topRight
        let x0 = left ? min(v.x + v.width - Self.minimum, max(0, v.x + dx)) : v.x
        let x1 = left ? v.x + v.width : max(v.x + Self.minimum, min(1, v.x + v.width + dx))
        let y0 = top ? min(v.y + v.height - Self.minimum, max(0, v.y + dy)) : v.y
        let y1 = top ? v.y + v.height : max(v.y + Self.minimum, min(1, v.y + v.height + dy))
        return Self(x: x0, y: y0, width: x1 - x0, height: y1 - y0).normalized
    }
}

enum TouchpadTuning {
    static let defaultSensitivity = 0.5
    static let defaultEdgeInset = 0.125
    static func sensitivity(_ value: Double) -> Double { value.isFinite ? min(max(value, 0.1), 1.5) : defaultSensitivity }
    static func edgeInset(_ value: Double) -> Double { value.isFinite ? min(max(value, 0), 0.25) : defaultEdgeInset }

    static func scale(_ event: TouchpadEvent, by value: Double) -> TouchpadEvent {
        let gain = sensitivity(value)
        switch event {
        case let .pointerMoved(dx, dy): return .pointerMoved(dx: dx * gain, dy: dy * gain)
        case let .dragMoved(dx, dy): return .dragMoved(dx: dx * gain, dy: dy * gain)
        default: return event
        }
    }

    static func activeRect(in bounds: CGRect, inset: Double) -> CGRect {
        let fraction = edgeInset(inset)
        return bounds.insetBy(dx: bounds.width * fraction, dy: bounds.height * fraction)
    }
}

/// A contact that starts in the excluded ring or later enters it stays rejected until lift.
/// This prevents a resting grip finger from becoming an input merely by sliding inward.
struct TouchContactGate<ID: Hashable> {
    private var contacts: [ID: Bool] = [:]
    private var cancelled: Set<ID> = []
    var waitingForLift: Bool { !cancelled.isEmpty }
    /// UIKit may cancel a stream while a keyboard/menu is changing without later
    /// delivering its ended event. Only the identities still live can block input.
    /// A fresh began also handles UIKit reusing a released UITouch identity.
    mutating func synchronize(live: Set<ID>, began: Set<ID> = []) {
        let previous = live.subtracting(began)
        contacts = contacts.filter { previous.contains($0.key) }
        cancelled.formIntersection(previous)
    }
    mutating func begin(_ id: ID, at point: CGPoint, in rect: CGRect) {
        guard contacts[id] == nil else { return }
        contacts[id] = rect.contains(point)
    }
    mutating func move(_ id: ID, to point: CGPoint, in rect: CGRect) {
        if contacts[id] == true, !rect.contains(point) { contacts[id] = false }
    }
    func accepts(_ id: ID) -> Bool { contacts[id] == true }
    mutating func end(_ id: ID) { contacts.removeValue(forKey: id); cancelled.remove(id) }
    mutating func cancel() {
        cancelled.formUnion(contacts.keys)
        for id in Array(contacts.keys) { contacts[id] = false }
    }
}

enum InnerInputMode: String, CaseIterable, Identifiable {
    case keyboard, touchpad
    var id: String { rawValue }
    var title: String { self == .keyboard ? "键盘覆盖" : "触控 · 全屏桌面" }
    var opposite: Self { self == .keyboard ? .touchpad : .keyboard }
}
enum RearActivation: String, CaseIterable, Identifiable {
    case momentary, toggle
    var id: String { rawValue }
    var title: String { self == .momentary ? "按住临时切换" : "触发一次切换" }
}
enum RearTrigger: String, CaseIterable, Identifiable {
    case touch, longPress
    var id: String { rawValue }
}
enum RearContactGesture { case tap, longPress }

/// Two rear fingers switch the front pointer mode; one rear finger is reserved for the window chord.
struct GripInputState {
    private(set) var defaultMode: InnerInputMode = .touchpad
    private(set) var defaultFrontMode: FrontTouchMode = .direct
    private(set) var activation: RearActivation = .momentary
    private(set) var trigger: RearTrigger = .longPress
    private(set) var activated = false
    private(set) var outerCount = 0
    private(set) var innerCount = 0
    private var suppressFront = false
    private var frontDragging = false
    var buttonHeld: Bool { false }
    var requestedMode: InnerInputMode { defaultMode }
    var requestedFrontMode: FrontTouchMode {
        activated ? (defaultFrontMode == .direct ? .trackpad : .direct) : defaultFrontMode
    }
    var overlayVisible: Bool { requestedMode == .touchpad || innerCount > 0 }

    mutating func configure(defaultMode: InnerInputMode, activation: RearActivation, trigger: RearTrigger,
                            frontMode: FrontTouchMode = .direct) -> [TouchpadEvent] {
        guard self.defaultMode != defaultMode || self.activation != activation || self.trigger != trigger || self.defaultFrontMode != frontMode else { return [] }
        if self.activation == activation && self.trigger == trigger && self.defaultFrontMode == frontMode {
            self.defaultMode = defaultMode
            return releaseFront()
        }
        let result = cancel()
        self.defaultMode = defaultMode; self.activation = activation; self.trigger = trigger; self.defaultFrontMode = frontMode
        return result
    }
    mutating func gesture(_ gesture: RearContactGesture, fingers: Int = 2) {
        guard fingers == 2 else { return }
        guard trigger == .longPress ? gesture == .longPress : gesture == .tap else { return }
        if gesture == .longPress && outerCount < 2 { return }
        if activation == .toggle { activated.toggle() }
        else if outerCount >= 2 { activated = true }
        if innerCount > 0 { suppressFront = true }
    }
    mutating func outerContacts(_ count: Int) -> [TouchpadEvent] {
        let old = requestedFrontMode
        outerCount = max(0, count)
        if activation == .momentary {
            if trigger == .touch { activated = outerCount >= 2 }
            else if outerCount < 2 { activated = false }
        }
        if old != requestedFrontMode, innerCount > 0 { suppressFront = true }
        return []
    }
    mutating func innerContacts(_ count: Int) {
        innerCount = max(0, count)
        if innerCount == 0 { suppressFront = false }
    }
    mutating func route(_ event: TouchpadEvent) -> [TouchpadEvent] {
        if event == .dragEnded, frontDragging { frontDragging = false; return [event] }
        guard !suppressFront else { return [] }
        if event == .dragBegan { frontDragging = true }
        return [event]
    }
    mutating func cancel() -> [TouchpadEvent] {
        let release = releaseFront()
        outerCount = 0; activated = false
        suppressFront = innerCount > 0
        return release
    }
    mutating func releaseFront() -> [TouchpadEvent] {
        let result: [TouchpadEvent] = frontDragging ? [.dragEnded] : []
        frontDragging = false; suppressFront = innerCount > 0
        return result
    }
}

@MainActor
final class GripInteraction: ObservableObject {
    @Published private(set) var state = GripInputState()
    @Published private(set) var controlsPresented = false
    var onEvent: ((TouchpadEvent) -> Void)?

    func setControlsPresented(_ value: Bool) {
        controlsPresented = value
        if value { cancel(); state.innerContacts(0) }
    }
    func outerContacts(_ count: Int) { guard !controlsPresented else { return }; emit(state.outerContacts(count)) }
    func gesture(_ gesture: RearContactGesture) { guard !controlsPresented else { return }; state.gesture(gesture) }
    func configure(defaultMode: InnerInputMode, activation: RearActivation, trigger: RearTrigger, frontMode: FrontTouchMode = .direct) {
        emit(state.configure(defaultMode: defaultMode, activation: activation, trigger: trigger, frontMode: frontMode))
    }
    func innerContacts(_ count: Int) { state.innerContacts(count) }
    func handle(_ event: TouchpadEvent) { emit(state.route(event)) }
    func cancel() { emit(state.cancel()) }
    func releaseFront() { emit(state.releaseFront()) }
    private func emit(_ events: [TouchpadEvent]) { events.forEach { onEvent?($0) } }
}

import SwiftUI

enum TouchpadEvent: Equatable {
    case pointerMoved(dx: CGFloat, dy: CGFloat)
    case leftClick
    case dragBegan
    case dragMoved(dx: CGFloat, dy: CGFloat)
    case dragEnded
    case rightClick
    case scrolled(amount: CGFloat)
}

#if os(macOS)
import AppKit

struct TouchpadSurface: NSViewRepresentable {
    let onEvent: (TouchpadEvent) -> Void
    func makeNSView(context: Context) -> MacTouchSurface {
        let view = MacTouchSurface()
        view.onEvent = onEvent
        return view
    }
    func updateNSView(_ view: MacTouchSurface, context: Context) { view.onEvent = onEvent }
}

/// Mouse drag/scroll/right click are local stand-ins for touchpad fingers.
/// No global event monitor or input injection is used.
final class MacTouchSurface: NSView {
    var onEvent: ((TouchpadEvent) -> Void)?
    private var origin = CGPoint.zero
    private var last = CGPoint.zero
    private var moved: CGFloat = 0
    private var armed = false
    private var dragging = false
    private var holdTimer: Timer?
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityLabel("外屏触控板")
        setAccessibilityRole(.group)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func mouseDown(with event: NSEvent) {
        holdTimer?.invalidate()
        origin = convert(event.locationInWindow, from: nil)
        last = origin; moved = 0; armed = false; dragging = false
        holdTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { [weak self] _ in
            if let self, self.moved < 6 { self.armed = true }
        }
    }
    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        moved = max(moved, hypot(point.x - origin.x, point.y - origin.y))
        let dx = (point.x - last.x) / max(bounds.width, 1)
        let dy = (point.y - last.y) / max(bounds.height, 1)
        last = point
        if !armed && moved > 6 { holdTimer?.invalidate() }
        if armed {
            if !dragging { dragging = true; onEvent?(.dragBegan) }
            onEvent?(.dragMoved(dx: dx, dy: dy))
        } else { onEvent?(.pointerMoved(dx: dx, dy: dy)) }
    }
    override func mouseUp(with event: NSEvent) {
        holdTimer?.invalidate()
        if dragging { onEvent?(.dragEnded) }
        else if moved < 6 { onEvent?(.leftClick) }
        dragging = false; armed = false
    }
    override func rightMouseDown(with event: NSEvent) { onEvent?(.rightClick) }
    override func scrollWheel(with event: NSEvent) {
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 12
        onEvent?(.scrolled(amount: delta / max(bounds.height, 1)))
    }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            holdTimer?.invalidate()
            if dragging { onEvent?(.dragEnded) }
            dragging = false
        }
        super.viewWillMove(toWindow: newWindow)
    }
}
#else
import UIKit

enum TouchSurfaceBehavior { case standard, contactsOnly, thumb }

struct TouchpadSurface: UIViewRepresentable {
    var behavior: TouchSurfaceBehavior = .standard
    var inputEnabled = true
    var edgeInsetFraction: Double = 0
    var activeRegion: RearActiveRegion? = nil
    var contactGestureFingers = 1
    var inputEpoch = 0
    var inputIsCurrent: () -> Bool = { true }
    var onContactCount: ((Int) -> Void)? = nil
    var onContactGesture: ((RearContactGesture) -> Void)? = nil
    let onEvent: (TouchpadEvent) -> Void
    func makeUIView(context: Context) -> TouchSurfaceView {
        let view = TouchSurfaceView()
        view.contactGestureFingers = contactGestureFingers
        view.behavior = behavior; view.edgeInsetFraction = TouchpadTuning.edgeInset(edgeInsetFraction)
        view.activeRegion = activeRegion
        view.onEvent = onEvent; view.onContactCount = onContactCount; view.onContactGesture = onContactGesture
        view.inputEpoch = inputEpoch; view.inputIsCurrent = inputIsCurrent
        view.inputEnabled = inputEnabled
        return view
    }
    func updateUIView(_ view: TouchSurfaceView, context: Context) {
        view.onEvent = onEvent; view.onContactCount = onContactCount; view.onContactGesture = onContactGesture
        view.inputIsCurrent = inputIsCurrent; view.inputEpoch = inputEpoch
        view.inputEnabled = inputEnabled
        view.behavior = behavior; view.contactGestureFingers = contactGestureFingers
        view.edgeInsetFraction = TouchpadTuning.edgeInset(edgeInsetFraction)
        view.activeRegion = activeRegion
    }
    static func dismantleUIView(_ view: TouchSurfaceView, coordinator: ()) { view.cancelTouches() }
}

final class TouchSurfaceView: UIView {
    var activeRegion: RearActiveRegion? {
        didSet { if oldValue != activeRegion { cancelTouches() } }
    }
    var inputEnabled = true {
        didSet {
            guard oldValue != inputEnabled else { return }
            isUserInteractionEnabled = inputEnabled
            if !inputEnabled { cancelTouches() }
        }
    }
    var inputIsCurrent: () -> Bool = { true }
    var inputEpoch = 0 { didSet { if oldValue != inputEpoch { cancelTouches() } } }
    var onEvent: ((TouchpadEvent) -> Void)?
    var onContactCount: ((Int) -> Void)?
    var onContactGesture: ((RearContactGesture) -> Void)?
    var behavior: TouchSurfaceBehavior = .standard {
        didSet { if oldValue != behavior { cancelTouches() } }
    }
    var edgeInsetFraction: Double = 0 {
        didSet { if oldValue != edgeInsetFraction { cancelTouches() } }
    }
    var contactGestureFingers = 1 {
        didSet { if oldValue != contactGestureFingers { cancelTouches() } }
    }
    private var rearGestureStartedAt: TimeInterval?
    private var rearGestureValid = false
    private var rearOrigins: [ObjectIdentifier: CGPoint] = [:]
    private var contactGate = TouchContactGate<ObjectIdentifier>()
    private var previousSize: CGSize?
    private var reportedContacts = 0
    private var startedAt: TimeInterval?
    private var firstPoint = CGPoint.zero
    private var lastPoint = CGPoint.zero
    private var lastCentroid = CGPoint.zero
    private var maxTravel: CGFloat = 0
    private var observedFingerCount = 0
    private var lastFingerCount = 0
    private var dragIsActive = false
    private var dragArmed = false
    private var holdTimer: Timer?
    private var rearLongPressSent = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        backgroundColor = .clear
        isOpaque = false
        accessibilityLabel = "外屏触控板"
        accessibilityTraits = .allowsDirectInteraction
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func ownedTouches(_ event: UIEvent?) -> [UITouch] {
        event?.allTouches?.filter { $0.view === self && [.began, .moved, .stationary].contains($0.phase) } ?? []
    }

    private var activeRect: CGRect { activeRegion?.rect(in: bounds) ?? TouchpadTuning.activeRect(in: bounds, inset: edgeInsetFraction) }
    private func acceptedTouches(_ event: UIEvent?) -> [UITouch] {
        let touches = ownedTouches(event)
        for touch in touches { contactGate.move(ObjectIdentifier(touch), to: touch.location(in: self), in: activeRect) }
        return touches.filter { contactGate.accepts(ObjectIdentifier($0)) }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        contactGate.synchronize(live: Set(ownedTouches(event).map(ObjectIdentifier.init)),
                                began: Set(touches.filter { $0.view === self }.map(ObjectIdentifier.init)))
        guard inputIsCurrent() else { cancelTouches(); return }
        for touch in touches where touch.view === self {
            contactGate.begin(ObjectIdentifier(touch), at: touch.location(in: self), in: activeRect)
        }
        let active = acceptedTouches(event)
        if contactGate.waitingForLift { contactGate.cancel(); return }
        guard !active.isEmpty else { return }
        guard touches.contains(where: { contactGate.accepts(ObjectIdentifier($0)) }) else { return }
        reportContacts(active.count)
        if startedAt == nil {
            startedAt = active[0].timestamp
            firstPoint = centroid(active)
            lastPoint = firstPoint
            maxTravel = 0
            rearLongPressSent = false
            if behavior == .standard {
                let timer = Timer(timeInterval: 0.35, repeats: false) { [weak self] _ in
                    if let self, self.inputIsCurrent(), self.observedFingerCount == 1, self.maxTravel < 6 { self.dragArmed = true }
                }
                holdTimer = timer
                RunLoop.main.add(timer, forMode: .common)
            }
        }
        if active.count > 1 && behavior != .contactsOnly {
            holdTimer?.invalidate(); dragArmed = false
            if dragIsActive { onEvent?(.dragEnded); dragIsActive = false }
        }
        observedFingerCount = max(observedFingerCount, active.count)
        lastFingerCount = active.count
        lastCentroid = centroid(active)
        if behavior == .contactsOnly {
            if active.count > contactGestureFingers { rearGestureValid = false; holdTimer?.invalidate() }
            else if active.count == contactGestureFingers && rearGestureStartedAt == nil && observedFingerCount == contactGestureFingers {
                rearGestureStartedAt = event?.timestamp ?? active[0].timestamp
                rearGestureValid = true; maxTravel = 0
                rearOrigins = Dictionary(uniqueKeysWithValues: active.map { (ObjectIdentifier($0), $0.location(in: self)) })
                let timer = Timer(timeInterval: 0.45, repeats: false) { [weak self] _ in
                    guard let self, self.rearGestureValid, self.reportedContacts == self.contactGestureFingers,
                          self.maxTravel < 10, !self.contactGate.waitingForLift,
                          self.inputEnabled, self.inputIsCurrent() else { return }
                    self.rearLongPressSent = true; self.onContactGesture?(.longPress)
                }
                holdTimer = timer; RunLoop.main.add(timer, forMode: .common)
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        contactGate.synchronize(live: Set(ownedTouches(event).map(ObjectIdentifier.init)))
        guard inputIsCurrent() else { cancelTouches(); return }
        let active = acceptedTouches(event)
        guard !contactGate.waitingForLift else { return }
        if behavior == .contactsOnly {
            for touch in active {
                if let start = rearOrigins[ObjectIdentifier(touch)] {
                    let point = touch.location(in: self)
                    maxTravel = max(maxTravel, hypot(point.x - start.x, point.y - start.y))
                }
            }
            if maxTravel >= 10 || active.count != contactGestureFingers { holdTimer?.invalidate() }
            if ownedTouches(event).count > active.count { rearGestureValid = false }
            if active.isEmpty { reset() }
            reportContacts(active.count); return
        }
        if active.count < reportedContacts { cancelTouches(); return }
        guard startedAt != nil, !active.isEmpty else { return }
        if observedFingerCount > 1 {
            let current = centroid(active)
            if active.count > 1 && active.count == lastFingerCount {
                let dy = current.y - lastCentroid.y
                maxTravel += hypot(current.x - lastCentroid.x, dy)
                if abs(dy) > 0.2 { onEvent?(.scrolled(amount: dy / max(bounds.height, 1))) }
            }
            lastFingerCount = active.count
            lastCentroid = current
            return
        }
        let point = active[0].location(in: self)
        maxTravel = max(maxTravel, hypot(point.x - firstPoint.x, point.y - firstPoint.y))
        let dx = (point.x - lastPoint.x) / max(bounds.width, 1)
        let dy = (point.y - lastPoint.y) / max(bounds.height, 1)
        lastPoint = point
        if !dragArmed && maxTravel > 6 { holdTimer?.invalidate() }
        if dragArmed && maxTravel > 2 {
            if !dragIsActive { dragIsActive = true; onEvent?(.dragBegan) }
            onEvent?(.dragMoved(dx: dx, dy: dy))
        } else { onEvent?(.pointerMoved(dx: dx, dy: dy)) }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if !inputIsCurrent() { cancelTouches() }
        var endedOutside = false
        for touch in touches {
            let id = ObjectIdentifier(touch)
            if behavior == .contactsOnly, let start = rearOrigins[id] {
                let point = touch.location(in: self)
                maxTravel = max(maxTravel, hypot(point.x - start.x, point.y - start.y))
            }
            let wasAccepted = contactGate.accepts(id)
            contactGate.move(id, to: touch.location(in: self), in: activeRect)
            endedOutside = endedOutside || (wasAccepted && !contactGate.accepts(id))
            contactGate.end(id)
        }
        if endedOutside { rearGestureValid = false; if behavior != .contactsOnly { cancelTouches() } }
        let active = acceptedTouches(event)
        let wasWaiting = contactGate.waitingForLift
        contactGate.synchronize(live: Set(ownedTouches(event).map(ObjectIdentifier.init)))
        if wasWaiting || contactGate.waitingForLift {
            return
        }
        if behavior == .contactsOnly {
            if active.isEmpty {
                if let startedAt = rearGestureStartedAt, observedFingerCount == contactGestureFingers, rearGestureValid, maxTravel < 10, !rearLongPressSent,
                   !endedOutside, (event?.timestamp ?? startedAt) - startedAt < 0.45 {
                    onContactGesture?(.tap)
                }
                reset()
            }
            if active.count != contactGestureFingers { holdTimer?.invalidate() }
            reportContacts(active.count); return
        }
        if !active.isEmpty {
            lastCentroid = centroid(active); lastFingerCount = active.count
            reportContacts(active.count); return
        }
        if dragIsActive { onEvent?(.dragEnded) }
        else if let startedAt, maxTravel < 10, (event?.timestamp ?? startedAt) - startedAt < 0.6 {
            onEvent?(observedFingerCount > 1 ? .rightClick : .leftClick)
        }
        reset()
        // Emit the terminal click before the contact count resets its suppression state.
        reportContacts(0)
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        cancelTouches()
        for touch in touches { contactGate.end(ObjectIdentifier(touch)) }
        contactGate.synchronize(live: Set(ownedTouches(event).map(ObjectIdentifier.init)))
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        if let previousSize, previousSize != bounds.size { cancelTouches() }
        previousSize = bounds.size
    }
    override func willMove(toWindow newWindow: UIWindow?) {
        if newWindow == nil { cancelTouches() }
        super.willMove(toWindow: newWindow)
    }
    func cancelTouches() {
        if dragIsActive { onEvent?(.dragEnded) }
        contactGate.cancel()
        reset(); reportContacts(0)
    }
    private func reportContacts(_ count: Int) {
        guard count != reportedContacts else { return }
        reportedContacts = count; onContactCount?(count)
    }
    private func reset() {
        holdTimer?.invalidate(); holdTimer = nil
        startedAt = nil; observedFingerCount = 0; lastFingerCount = 0
        rearGestureStartedAt = nil; rearGestureValid = false; rearOrigins.removeAll()
        dragIsActive = false; dragArmed = false; maxTravel = 0
    }
    private func centroid(_ touches: [UITouch]) -> CGPoint {
        guard !touches.isEmpty else { return lastCentroid }
        let sum = touches.reduce(CGPoint.zero) { result, touch in
            let p = touch.location(in: self)
            return CGPoint(x: result.x + p.x, y: result.y + p.y)
        }
        return CGPoint(x: sum.x / CGFloat(touches.count), y: sum.y / CGFloat(touches.count))
    }
}

/// A local tactile acknowledgement, not confirmation that the Mac executed an event.
@MainActor
final class TouchFeedback {
    static let shared = TouchFeedback()
    private let press = UIImpactFeedbackGenerator(style: .rigid)
    private let release = UIImpactFeedbackGenerator(style: .soft)
    private var enabled: Bool { UserDefaults.standard.object(forKey: "clickFeedbackEnabled") as? Bool ?? true }

    func prepare() { if enabled { press.prepare(); release.prepare() } }
    func play(_ event: TouchpadEvent) {
        guard enabled else { return }
        switch event {
        case .leftClick, .dragBegan: press.impactOccurred(intensity: 0.8)
        case .rightClick: press.impactOccurred(intensity: 1)
        case .dragEnded: release.impactOccurred(intensity: 0.45)
        default: return
        }
        prepare()
    }
}
#endif

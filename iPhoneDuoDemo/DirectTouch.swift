import Foundation
import CoreGraphics

enum FrontTouchMode: String, CaseIterable, Identifiable {
    case trackpad, direct
    var id: String { rawValue }
    var title: String { self == .direct ? "直接触屏" : "触控板" }
}

enum WindowOverviewAction: Equatable {
    case show, hide, previousDesktop, nextDesktop
    var isDesktopSwitch: Bool { self == .previousDesktop || self == .nextDesktop }
    var title: String {
        switch self {
        case .show: "打开窗口总览"
        case .hide: "退出窗口总览"
        case .previousDesktop: "上一个桌面"
        case .nextDesktop: "下一个桌面"
        }
    }
}

/// The two-finger group chooses overview OR local zoom when it starts, never both.
struct WindowOverviewSwipe {
    private var origins: [CGPoint] = []
    private var finished = false
    mutating func begin(at points: [CGPoint]) {
        origins = points; finished = points.count != 2
    }
    mutating func move(to points: [CGPoint], rearContacts: Int) -> WindowOverviewAction? {
        guard origins.count == 2, !finished else { return nil }
        guard rearContacts == 1, points.count == 2,
              points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { finished = true; return nil }
        let deltas = zip(points, origins).map { CGPoint(x: $0.x - $1.x, y: $0.y - $1.y) }
        let dx = (deltas[0].x + deltas[1].x) / 2, dy = (deltas[0].y + deltas[1].y) / 2
        // Once both fingers have chosen opposing directions, this group is a pinch,
        // not a later window command. Separate UIKit move callbacks remain valid.
        if (abs(deltas[0].x) >= 24 && abs(deltas[1].x) >= 24 && deltas[0].x * deltas[1].x < 0)
            || (abs(deltas[0].y) >= 24 && abs(deltas[1].y) >= 24 && deltas[0].y * deltas[1].y < 0) {
            finished = true; return nil
        }
        if abs(dx) >= 44, abs(dx) > abs(dy) * 1.5,
           deltas.allSatisfy({ $0.x * dx > 0 && abs($0.x) >= 24 }) {
            finished = true
            return dx < 0 ? .nextDesktop : .previousDesktop
        }
        // UIKit may deliver each finger's move separately. A span-ratio test on every
        // callback rejected ordinary swipes before the second finger caught up.
        // Require both fingers to travel in the same vertical direction instead.
        guard deltas.allSatisfy({ $0.y * dy > 0 && abs($0.y) >= 24 }) else { return nil }
        guard abs(dy) >= 44, abs(dy) > abs(dx) * 1.5 else { return nil }
        finished = true
        return dy < 0 ? .show : .hide
    }
    mutating func cancel() { origins = []; finished = true }
}

/// Delayed hold callbacks belong to one contact group, never the next one.
struct TouchSequence {
    private(set) var token: UInt64 = 0
    mutating func invalidate() { token &+= 1 }
    func accepts(_ candidate: UInt64) -> Bool { token == candidate }
}

/// Semantic gestures are independent of the current mouse-event transport adapter.
struct DirectTouchEvent: Equatable {
    enum Action: String { case tap, context, scroll, down, move, up }
    var action: Action
    var point: CGPoint
    var delta: CGPoint = .zero
    var clicks: Int = 1

    var isValid: Bool {
        point.x.isFinite && point.y.isFinite && (0...1).contains(point.x) && (0...1).contains(point.y)
            && delta.x.isFinite && delta.y.isFinite && abs(delta.x) <= 1 && abs(delta.y) <= 1
            && (1...2).contains(clicks)
    }
    func displayPoint(in bounds: CGRect) -> CGPoint {
        CGPoint(x: bounds.minX + point.x * max(0, bounds.width - 1),
                y: bounds.minY + point.y * max(0, bounds.height - 1))
    }
}

/// The same rectangle renders the image and maps touches, including letterboxing and zoom.
struct RemoteViewport {
    var container: CGSize
    var content: CGSize
    var zoom: CGFloat = 1
    var offset: CGPoint = .zero

    var fittedSize: CGSize {
        guard content.width > 0, content.height > 0, container.width > 0, container.height > 0 else { return .zero }
        let scale = min(container.width / content.width, container.height / content.height)
        return CGSize(width: content.width * scale, height: content.height * scale)
    }
    var imageRect: CGRect {
        let size = CGSize(width: fittedSize.width * zoom, height: fittedSize.height * zoom)
        return CGRect(x: (container.width - size.width) / 2 + offset.x,
                      y: (container.height - size.height) / 2 + offset.y, width: size.width, height: size.height)
    }
    func normalized(_ point: CGPoint, clamped: Bool = false) -> CGPoint? {
        let rect = imageRect
        guard point.x.isFinite, point.y.isFinite, rect.width > 0, rect.height > 0,
              clamped || (point.x >= rect.minX && point.x <= rect.maxX && point.y >= rect.minY && point.y <= rect.maxY) else { return nil }
        return CGPoint(x: min(max((point.x - rect.minX) / rect.width, 0), 1),
                       y: min(max((point.y - rect.minY) / rect.height, 0), 1))
    }
    mutating func magnify(to scale: CGFloat, anchor: CGPoint, centroid: CGPoint) {
        zoom = min(max(scale.isFinite ? scale : 1, 1), 4)
        let size = CGSize(width: fittedSize.width * zoom, height: fittedSize.height * zoom)
        let limitX = max(0, (size.width - container.width) / 2)
        let limitY = max(0, (size.height - container.height) / 2)
        offset = CGPoint(x: min(max(centroid.x - anchor.x * size.width - (container.width - size.width) / 2, -limitX), limitX),
                         y: min(max(centroid.y - anchor.y * size.height - (container.height - size.height) / 2, -limitY), limitY))
    }
}

/// A quick swipe scrolls. Holding first arms a drag; lifting without moving opens the menu.
struct DirectTouchState {
    private enum Phase { case idle, pending, held, scrolling, dragging, ignored }
    private var phase: Phase = .idle
    private var origin = CGPoint.zero
    private var anchor = CGPoint.zero
    private var point = CGPoint.zero
    private var contact = false
    private(set) var rearHeld = false
    private(set) var dragging = false
    var selectionArmed: Bool { phase == .held || phase == .dragging }

    mutating func begin(at position: CGPoint, viewPoint: CGPoint) -> [DirectTouchEvent] {
        point = position; anchor = position; origin = viewPoint; contact = true
        phase = rearHeld ? .dragging : .pending
        if rearHeld {
            let action: DirectTouchEvent.Action = dragging ? .move : .down
            dragging = true
            return [.init(action: action, point: point)]
        }
        return []
    }
    mutating func move(to position: CGPoint, viewPoint: CGPoint, delta: CGPoint) -> [DirectTouchEvent] {
        guard contact else { return [] }
        point = position
        if phase == .dragging { return [.init(action: .move, point: point)] }
        if phase == .held {
            guard hypot(viewPoint.x - origin.x, viewPoint.y - origin.y) >= 7 else { return [] }
            phase = .dragging; dragging = true
            return [.init(action: .down, point: anchor), .init(action: .move, point: point)]
        }
        if phase == .pending && hypot(viewPoint.x - origin.x, viewPoint.y - origin.y) >= 7 { phase = .scrolling }
        guard phase == .scrolling else { return [] }
        return [.init(action: .scroll, point: anchor, delta: delta)]
    }
    mutating func longPress() -> [DirectTouchEvent] {
        guard contact, phase == .pending, !rearHeld else { return [] }
        phase = .held
        return []
    }
    mutating func end(clicks: Int) -> [DirectTouchEvent] {
        var result: [DirectTouchEvent] = []
        if !rearHeld {
            if phase == .pending { result = [.init(action: .tap, point: point, clicks: min(max(clicks, 1), 2))] }
            else if phase == .held { result = [.init(action: .context, point: anchor)] }
            else if dragging { result = [.init(action: .up, point: point)]; dragging = false }
        }
        contact = false; phase = .idle
        return result
    }
    mutating func setRearHeld(_ held: Bool) -> [DirectTouchEvent] {
        guard rearHeld != held else { return [] }
        rearHeld = held
        if !held {
            let events: [DirectTouchEvent] = dragging ? [.init(action: .up, point: point)] : []
            dragging = false
            if contact { phase = .ignored }
            return events
        }
        guard contact, phase != .ignored else { return [] }
        phase = .dragging; dragging = true
        return [.init(action: .down, point: point)]
    }
    mutating func cancel() -> [DirectTouchEvent] {
        let result: [DirectTouchEvent] = dragging ? [.init(action: .up, point: point)] : []
        self = Self()
        return result
    }
}

struct MagnifierGeometry {
    static func frame(around point: CGPoint, within safe: CGRect) -> CGRect {
        guard safe.width > 0, safe.height > 0 else { return .zero }
        let width = min(safe.width * 0.44, safe.height * 0.8)
        let height = width * 0.65
        let gap = height * 0.35
        let above = point.y - height - gap
        let y = above >= safe.minY ? above : point.y + gap
        return CGRect(x: min(max(point.x - width / 2, safe.minX), safe.maxX - width),
                      y: min(max(y, safe.minY), safe.maxY - height), width: width, height: height)
    }
}

#if os(iOS)
import SwiftUI
import UIKit

struct DirectTouchSurface: UIViewRepresentable {
    var image: CGImage
    var enabled: Bool
    var rearHeld: Bool
    var magnifierEnabled: Bool
    var windowGesturesEnabled: Bool
    var readRearContacts: () -> Int
    var onWindowOverview: (WindowOverviewAction) -> Void
    var revision: String?
    var resetToken: Int
    var inputEpoch: Int
    var readRearHeld: () -> Bool
    var inputIsCurrent: () -> Bool
    var onContacts: (Int) -> Void
    var onEvent: (DirectTouchEvent) -> Void

    func makeUIView(context: Context) -> DirectTouchView { DirectTouchView() }
    func updateUIView(_ view: DirectTouchView, context: Context) {
        view.onEvent = onEvent; view.onContacts = onContacts
        view.readRearHeld = readRearHeld
        view.inputIsCurrent = inputIsCurrent
        view.readRearContacts = readRearContacts; view.onWindowOverview = onWindowOverview
        view.windowGesturesEnabled = windowGesturesEnabled
        view.configure(image: image, enabled: enabled, rearHeld: rearHeld, magnifierEnabled: magnifierEnabled, revision: revision, resetToken: resetToken, inputEpoch: inputEpoch)
    }
    static func dismantleUIView(_ view: DirectTouchView, coordinator: ()) { view.cancelInput() }
}

final class DirectTouchView: UIView {
    var onEvent: ((DirectTouchEvent) -> Void)?
    var onContacts: ((Int) -> Void)?
    var readRearHeld: (() -> Bool)?
    var readRearContacts: (() -> Int)?
    var inputIsCurrent: (() -> Bool)?
    var onWindowOverview: ((WindowOverviewAction) -> Void)?
    var windowGesturesEnabled = true
    private var overviewSwipe = WindowOverviewSwipe()
    private var windowChord = false
    private var windowFingerIDs: [ObjectIdentifier] = []
    private let picture = UIImageView()
    private let lens = RemoteMagnifierView()
    private var magnifierEnabled = true
    private var viewport = RemoteViewport(container: .zero, content: .zero)
    private var state = DirectTouchState()
    private var enabled = false
    private var rearHeld = false
    private var revision: String?
    private var resetToken = 0
    private var inputEpoch = 0
    private var active: [ObjectIdentifier: UITouch] = [:]
    private var ignored = false
    private var multi = false
    private var last = CGPoint.zero
    private var pinchDistance: CGFloat = 1
    private var pinchZoom: CGFloat = 1
    private var pinchAnchor = CGPoint.zero
    private var timer: Timer?
    private var sequence = TouchSequence()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black; clipsToBounds = true; isMultipleTouchEnabled = true
        picture.isUserInteractionEnabled = false; addSubview(picture)
        lens.isHidden = true; lens.isUserInteractionEnabled = false; addSubview(lens)
        accessibilityLabel = "直接触屏远程桌面"
        accessibilityIdentifier = "direct-remote-touch"
        accessibilityTraits = .allowsDirectInteraction
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(image: CGImage, enabled: Bool, rearHeld: Bool, magnifierEnabled: Bool, revision: String?, resetToken: Int, inputEpoch: Int) {
        let size = CGSize(width: image.width, height: image.height)
        if self.revision != revision || viewport.content != size || self.resetToken != resetToken {
            cancelInput(); viewport.zoom = 1; viewport.offset = .zero
        }
        if self.enabled && !enabled { cancelInput() }
        if self.inputEpoch != inputEpoch { cancelInput() }
        self.inputEpoch = inputEpoch
        self.magnifierEnabled = magnifierEnabled
        if !magnifierEnabled { lens.isHidden = true }
        if windowChord && (!windowGesturesEnabled || readRearContacts?() != 1) { overviewSwipe.cancel() }
        self.enabled = enabled; self.revision = revision; self.resetToken = resetToken
        self.rearHeld = rearHeld
        // Press at a front contact, on the same event turn as its move. SwiftUI rendering
        // may lag the accessory's contact count; never enqueue a delayed mouse-down here.
        if !rearHeld { emit(state.setRearHeld(false)) }
        viewport.content = size
        picture.image = UIImage(cgImage: image)
        lens.image = picture.image; lens.setNeedsDisplay()
        picture.frame = viewport.imageRect
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        if viewport.container != bounds.size {
            cancelInput(); viewport.container = bounds.size; viewport.zoom = 1; viewport.offset = .zero
        }
        picture.frame = viewport.imageRect
    }
    private func emit(_ events: [DirectTouchEvent]) {
        for event in events where event.isValid { onEvent?(event) }
    }
    func cancelInput() {
        invalidateHold()
        lens.isHidden = true; overviewSwipe.cancel()
        emit(state.cancel())
        ignored = !active.isEmpty
        // Defer SwiftUI state publication until after updateUIView/layoutSubviews.
        if active.isEmpty {
            let token = sequence.token
            DispatchQueue.main.async { [weak self] in
                guard let self, self.sequence.accepts(token), self.active.isEmpty,
                      self.inputIsCurrent?() != false else { return }
                self.onContacts?(0)
            }
        }
    }
    private func invalidateHold() {
        timer?.invalidate(); timer = nil; sequence.invalidate()
    }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        invalidateHold()
        for touch in touches { active[ObjectIdentifier(touch)] = touch }
        guard inputIsCurrent?() != false else { cancelInput(); return }
        onContacts?(active.count)
        guard enabled, !ignored else { ignored = true; return }
        let fingers = Array(active.values)
        if fingers.count > 1 {
            timer?.invalidate(); lens.isHidden = true; emit(state.cancel()); multi = true
            if fingers.count == 2 {
                let a = fingers[0].location(in: self), b = fingers[1].location(in: self)
                let center = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
                windowChord = windowGesturesEnabled && readRearContacts?() == 1
                    && viewport.normalized(a) != nil && viewport.normalized(b) != nil
                if windowChord {
                    windowFingerIDs = fingers.map(ObjectIdentifier.init)
                    overviewSwipe.begin(at: [a, b])
                }
                pinchAnchor = viewport.normalized(center, clamped: true) ?? CGPoint(x: 0.5, y: 0.5)
                pinchDistance = max(1, hypot(a.x - b.x, a.y - b.y)); pinchZoom = viewport.zoom
            } else { overviewSwipe.cancel() }
            return
        }
        guard let touch = fingers.first else { return }
        last = touch.location(in: self)
        guard let point = viewport.normalized(last) else { ignored = true; return }
        emit(state.setRearHeld(readRearHeld?() ?? rearHeld))
        emit(state.begin(at: point, viewPoint: last))
        let token = sequence.token
        let timer = Timer(timeInterval: 0.45, repeats: false) { [weak self] _ in
            guard let self, self.sequence.accepts(token), self.active.count == 1,
                  self.inputIsCurrent?() != false, self.enabled, !self.ignored, !self.multi else { return }
            self.emit(self.state.setRearHeld(self.readRearHeld?() ?? self.rearHeld))
            self.emit(self.state.longPress())
            if self.state.selectionArmed {
                Task { @MainActor in TouchFeedback.shared.play(.leftClick) }
                self.updateMagnifier(at: self.last)
            }
        }
        self.timer = timer; RunLoop.main.add(timer, forMode: .common)
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard inputIsCurrent?() != false else { cancelInput(); return }
        guard enabled, !ignored else { return }
        let fingers = Array(active.values)
        if multi {
            guard fingers.count == 2 else { return }
            let a = fingers[0].location(in: self), b = fingers[1].location(in: self)
            let center = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
            if windowChord {
                let points = windowFingerIDs.compactMap { active[$0]?.location(in: self) }
                if let action = overviewSwipe.move(to: points,
                    rearContacts: windowGesturesEnabled ? (readRearContacts?() ?? 0) : 0) {
                    onWindowOverview?(action)
                    Task { @MainActor in TouchFeedback.shared.play(.leftClick) }
                }
                return
            }
            viewport.magnify(to: pinchZoom * hypot(a.x - b.x, a.y - b.y) / pinchDistance, anchor: pinchAnchor, centroid: center)
            picture.frame = viewport.imageRect
            return
        }
        guard let touch = fingers.first else { return }
        let position = touch.location(in: self)
        guard let point = viewport.normalized(position, clamped: true) else { return }
        let rect = viewport.imageRect
        let delta = CGPoint(x: min(max((position.x - last.x) / rect.width, -1), 1),
                            y: min(max((position.y - last.y) / rect.height, -1), 1))
        last = position
        emit(state.setRearHeld(readRearHeld?() ?? rearHeld))
        emit(state.move(to: point, viewPoint: position, delta: delta))
        if state.selectionArmed { updateMagnifier(at: position) }
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        lens.isHidden = true; overviewSwipe.cancel()
        invalidateHold()
        for touch in touches { active.removeValue(forKey: ObjectIdentifier(touch)) }
        if active.isEmpty {
            if !ignored && !multi && enabled && inputIsCurrent?() != false { emit(state.end(clicks: touches.first?.tapCount ?? 1)) }
            else { emit(state.cancel()) }
            ignored = false; multi = false; windowChord = false; windowFingerIDs = []
        }
        onContacts?(active.count)
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches { active.removeValue(forKey: ObjectIdentifier(touch)) }
        cancelInput()
        if active.isEmpty { ignored = false; multi = false }
        onContacts?(active.count)
    }
    private func updateMagnifier(at position: CGPoint) {
        guard magnifierEnabled, let point = viewport.normalized(position, clamped: true) else { lens.isHidden = true; return }
        let safe = bounds.inset(by: safeAreaInsets).inset(by: layoutMargins)
        lens.frame = MagnifierGeometry.frame(around: position, within: safe)
        lens.sourcePoint = point; lens.renderedSize = viewport.imageRect.size
        lens.layer.cornerRadius = lens.bounds.height * 0.22
        lens.isHidden = false; lens.setNeedsDisplay()
    }
    override func willMove(toWindow newWindow: UIWindow?) {
        if newWindow == nil { active.removeAll(); cancelInput() }
        super.willMove(toWindow: newWindow)
    }
}
private final class RemoteMagnifierView: UIView {
    var image: UIImage?
    var sourcePoint = CGPoint.zero
    var renderedSize = CGSize.zero
    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true; backgroundColor = .black
        layer.borderColor = UIColor.white.withAlphaComponent(0.8).cgColor; layer.borderWidth = 2
        accessibilityLabel = "选字放大镜"
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func draw(_ rect: CGRect) {
        let size = CGSize(width: renderedSize.width * 2.2, height: renderedSize.height * 2.2)
        image?.draw(in: CGRect(x: bounds.midX - sourcePoint.x * size.width,
                              y: bounds.midY - sourcePoint.y * size.height, width: size.width, height: size.height))
        UIColor.systemMint.setStroke()
        let ring = UIBezierPath(ovalIn: CGRect(x: bounds.midX - 3, y: bounds.midY - 3, width: 6, height: 6))
        ring.lineWidth = 1; ring.stroke()
    }
}
#endif

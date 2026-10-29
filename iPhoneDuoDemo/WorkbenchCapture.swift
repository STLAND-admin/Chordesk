#if os(macOS)
import AppKit
import CoreGraphics
import SwiftUI

/// Foreground-only relative input. An optional selected-window session routes input
/// to that target; no global keyboard listener or HID event tap is installed.
@MainActor
final class WorkbenchCapture: ObservableObject {
    @Published private(set) var isActive = false
    weak var window: NSWindow?
    var monitorSize = CGSize(width: 1, height: 1)
    private weak var session: DemoSession?
    private weak var remote: WindowRemoteSession?
    private var eventMonitor: Any?
    private var notifications: [NSObjectProtocol] = []
    private var workspaceNotifications: [NSObjectProtocol] = []
    private var previousMouseMoved = false
    private var pressed = false
    private var dragging = false
    private var travel: CGFloat = 0
    private var returnCursor: CGPoint?

    func start(session: DemoSession, remote: WindowRemoteSession? = nil) {
        guard !isActive, let window, NSApp.isActive, window.isKeyWindow, window.attachedSheet == nil else { return }
        if let remote, !remote.prepareInput() { return }
        self.session = session
        self.remote = remote
        guard CGAssociateMouseAndMouseCursorPosition(0) == .success else {
            session.record("无法接管触控板，请重新聚焦此窗口后再试")
            return
        }
        previousMouseMoved = window.acceptsMouseMovedEvents
        window.acceptsMouseMovedEvents = true
        NSCursor.hide()
        // Anchor inside our window even if P was pressed while the pointer was elsewhere.
        // This is cursor capture, not a posted input event or a layout decision.
        if let current = CGEvent(source: nil)?.location, let content = window.contentView {
            returnCursor = current
            let mouse = NSEvent.mouseLocation
            let center = window.convertPoint(toScreen: content.convert(NSPoint(x: content.bounds.midX, y: content.bounds.midY), to: nil))
            CGWarpMouseCursorPosition(CGPoint(x: current.x + center.x - mouse.x, y: current.y - center.y + mouse.y))
        }
        isActive = true
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDown, .leftMouseUp, .leftMouseDragged,
                                          .rightMouseDown, .rightMouseUp, .rightMouseDragged,
                                          .otherMouseDown, .otherMouseUp, .otherMouseDragged,
                                          .scrollWheel, .keyDown, .keyUp, .flagsChanged, .magnify, .swipe, .rotate]
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            guard let self, self.isActive else { return event }
            guard NSApp.isActive, self.window?.isKeyWindow == true else { self.stop(); return event }
            return self.handle(event)
        }
        let center = NotificationCenter.default
        for name in [NSApplication.didResignActiveNotification, NSApplication.willTerminateNotification] {
            notifications.append(center.addObserver(forName: name, object: NSApp, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.stop() }
            })
        }
        for name in [NSWindow.didResignKeyNotification, NSWindow.willCloseNotification] {
            notifications.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.stop() }
            })
        }
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.sessionDidResignActiveNotification] {
            workspaceNotifications.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.stop() }
            })
        }
        session.record("已接管 · 直接滑动触控板，Esc 返回 Mac")
    }

    func stop() {
        guard isActive else { return }
        isActive = false
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        eventMonitor = nil
        notifications.forEach { NotificationCenter.default.removeObserver($0) }
        notifications.removeAll()
        workspaceNotifications.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        workspaceNotifications.removeAll()
        remote?.releaseInput()
        remote = nil
        CGAssociateMouseAndMouseCursorPosition(1)
        if let returnCursor { CGWarpMouseCursorPosition(returnCursor) }
        returnCursor = nil
        NSCursor.unhide()
        window?.acceptsMouseMovedEvents = previousMouseMoved
        if dragging { session?.touchpad(.dragEnded) }
        pressed = false; dragging = false; travel = 0
        session?.shift = false; session?.command = false; session?.control = false; session?.option = false
        session?.record("已退出接管 · 触控板恢复控制 Mac")
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard let session else { stop(); return event }
        // Host navigation belongs to macOS, including when controlling a real window.
        if event.type == .keyDown {
            if event.keyCode == 53 { stop(); return nil }
            if (event.keyCode == 48 && event.modifierFlags.contains(.command)) ||
                ([123, 124, 125, 126].contains(event.keyCode) && event.modifierFlags.contains(.control)) {
                stop(); return event
            }
        }
        if event.type == .swipe, remote != nil || event.deltaX != 0 { stop(); return event }
        if let remote {
            remote.handleCaptured(event, session: session)
            return nil
        }
        switch event.type {
        case .keyDown:
            if event.keyCode == 53 { stop(); return nil }
            // Keep host app switching available; window deactivation also releases capture.
            if event.keyCode == 48 && event.modifierFlags.contains(.command) { stop(); return event }
            keyboard(event, session: session)
        case .flagsChanged:
            session.shift = event.modifierFlags.contains(.shift)
            session.command = event.modifierFlags.contains(.command)
            session.control = event.modifierFlags.contains(.control)
            session.option = event.modifierFlags.contains(.option)
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            let dx = event.deltaX / max(1, monitorSize.width) / 1.5
            let dy = event.deltaY / max(1, monitorSize.height) / 1.5
            if pressed {
                travel += hypot(event.deltaX, event.deltaY)
                if !dragging && travel > 3 { dragging = true; session.touchpad(.dragBegan) }
            }
            session.touchpad(dragging ? .dragMoved(dx: dx, dy: dy) : .pointerMoved(dx: dx, dy: dy))
        case .leftMouseDown: pressed = true; dragging = false; travel = 0
        case .leftMouseUp:
            if pressed { session.touchpad(dragging ? .dragEnded : .leftClick) }
            pressed = false; dragging = false
        case .rightMouseDown: session.touchpad(.rightClick)
        case .scrollWheel:
            let dy = event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 1 : 12)
            session.touchpad(.scrolled(amount: dy / max(1, monitorSize.height)))
        case .swipe:
            // AppKit reports a three-finger trackpad swipe as an NSEvent swipe.
            // Positive deltaY is up; keep this local to the active workbench window.
            if event.deltaY > 0 { session.setWindowExpanded(true) }
            else if event.deltaY < 0 { session.setWindowExpanded(false) }
        default: break
        }
        // Prevent clicks and keys from also activating ordinary Mac controls in this window.
        return nil
    }

    private func keyboard(_ event: NSEvent, session: DemoSession) {
        let special: [UInt16: String] = [51: "delete", 36: "return", 76: "return", 48: "tab", 49: "space",
                                       123: "left", 124: "right", 125: "down", 126: "up"]
        session.command = event.modifierFlags.contains(.command)
        session.control = event.modifierFlags.contains(.control)
        session.option = event.modifierFlags.contains(.option)
        session.shift = event.modifierFlags.contains(.shift)
        if let key = special[event.keyCode] { session.key(key) }
        else if session.command || session.control {
            if let key = event.charactersIgnoringModifiers, key.count == 1 { session.key(key.lowercased()) }
        } else if let text = event.characters, !text.isEmpty,
                  text.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) && !(0xF700...0xF8FF).contains($0.value) }) {
            session.insert(text)
            session.record("输入 \(text)")
        }
    }
}

/// Attaches to this window only; removal releases any active capture.
struct CaptureWindowReader: NSViewRepresentable {
    let controller: WorkbenchCapture
    func makeNSView(context: Context) -> WindowProbe {
        let view = WindowProbe()
        view.controller = controller
        return view
    }
    func updateNSView(_ view: WindowProbe, context: Context) { view.controller = controller }
    static func dismantleNSView(_ view: WindowProbe, coordinator: ()) { view.controller?.stop() }

    final class WindowProbe: NSView {
        weak var controller: WorkbenchCapture?
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil { controller?.stop() }
            controller?.window = window
        }
    }
}
#endif

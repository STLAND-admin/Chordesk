import Foundation

enum KeyboardInvocation: String, CaseIterable, Identifiable {
    case manual, automatic
    var id: String { rawValue }
    var title: String { self == .manual ? "手动唤起" : "自动唤起" }
}

enum PhoneKeyboardStyle: String, CaseIterable, Identifiable {
    case system
    case mobile = "desktop" // Preserve the previous custom-keyboard preference.
    var id: String { rawValue }
    var title: String { self == .system ? "iPhone 输入法" : "手机布局 · 可调" }
}

/// Do not insert the keyboard beneath a resting front finger. Existing keyboard
/// stays visible when the user taps another point on the monitor.
struct NativeKeyboardPresentation {
    private(set) var visible = false
    mutating func update(wanted: Bool, frontContacts: Int) {
        if !wanted || frontContacts == 0 { visible = wanted }
    }
}

/// A keyboard suggestion belongs to one explicit remote click. Rear switching or
/// a manual mode choice consumes older suggestions, including delayed AX replies.
struct AutomaticKeyboardPolicy {
    private var handledThrough: UInt64 = 0
    mutating func suppress(through sequence: UInt64) { handledThrough = max(handledThrough, sequence) }
    mutating func mode(for focus: LANTextFocus, frontContacts: Int, rearContacts: Int) -> InnerInputMode? {
        guard focus.requestID > handledThrough, frontContacts == 0, rearContacts == 0 else { return nil }
        handledThrough = focus.requestID
        return focus.editable ? .keyboard : .touchpad
    }
}

struct LANTextFocus: Codable, Equatable {
    var id: String
    var editable: Bool
    var secure: Bool
    var requestID: UInt64
}

struct LANTextEdit: Codable, Equatable {
    var deleteCount: Int
    var text: String
    var focusID: String?
    var displayID: UInt32?
    var captureRevision: String?
    var sequence: UInt64 = 0
    var isValid: Bool {
        (0...256).contains(deleteCount) && text.utf8.count <= 8192
            && !text.unicodeScalars.contains(where: { $0.value == 0 })
    }
}

/// Only confirmed phone text is mirrored. Never send marked pinyin/IME candidates.
struct NativeTextBuffer {
    private(set) var committed = ""
    mutating func reset() { committed = "" }
    mutating func update(_ text: String, hasMarkedText: Bool) -> LANTextEdit? {
        guard !hasMarkedText else { return nil }
        let old = Array(committed), new = Array(text)
        let prefix = zip(old, new).prefix { $0 == $1 }.count
        let edit = LANTextEdit(deleteCount: old.count - prefix, text: String(new.dropFirst(prefix)))
        guard edit.isValid else { return nil }
        committed = String(new.suffix(256))
        return edit.deleteCount == 0 && edit.text.isEmpty ? nil : edit
    }
}

/// Convert UIKit's floating-cursor movement into bounded semantic caret steps.
/// This works without fetching any remote document text or inventing local text.
struct NativeCursorGesture {
    private var last: CGPoint?
    private var remainder = CGPoint.zero
    mutating func begin(at point: CGPoint) {
        last = point.x.isFinite && point.y.isFinite ? point : nil
        remainder = .zero
    }
    mutating func end() { last = nil; remainder = .zero }
    mutating func move(to point: CGPoint, horizontalStep: CGFloat = 12, verticalStep: CGFloat = 28) -> [String] {
        guard point.x.isFinite, point.y.isFinite, horizontalStep.isFinite, verticalStep.isFinite,
              horizontalStep > 0, verticalStep > 0, let old = last else { return [] }
        last = point
        remainder.x = min(max(remainder.x + point.x - old.x, -horizontalStep * 16), horizontalStep * 16)
        remainder.y = min(max(remainder.y + point.y - old.y, -verticalStep * 8), verticalStep * 8)
        let columns = min(max(Int(remainder.x / horizontalStep), -16), 16)
        let rows = min(max(Int(remainder.y / verticalStep), -8), 8)
        remainder.x -= CGFloat(columns) * horizontalStep
        remainder.y -= CGFloat(rows) * verticalStep
        return Array(repeating: columns < 0 ? "left" : "right", count: abs(columns))
            + Array(repeating: rows < 0 ? "up" : "down", count: abs(rows))
    }
}

struct ShortcutModifiers {
    private(set) var flags: UInt = 0
    mutating func toggle(_ flag: UInt) { flags ^= flag & 14 }
    mutating func clear() { flags = 0 }
    mutating func consume() -> UInt { let value = flags; flags = 0; return value }
    mutating func shortcut(for text: String) -> (key: String, flags: UInt)? {
        let selected = consume()
        guard selected != 0, text.count == 1, let char = text.first,
              char.isASCII, char.asciiValue.map({ (32...126).contains($0) || $0 == 10 || $0 == 9 }) == true else { return nil }
        let shifted: [Character: String] = ["!":"1", "@":"2", "#":"3", "$":"4", "%":"5", "^":"6", "&":"7", "*":"8", "(":"9", ")":"0", "_":"-", "+":"=", "{":"[", "}":"]", "|":"\\", ":":";", "\"":"'", "<":",", ">":".", "?":"/", "~":"`"]
        let key: String
        switch char { case " ": key = "space"; case "\n": key = "return"; case "\t": key = "tab"; default: key = shifted[char] ?? text.lowercased() }
        // Phone sentence auto-capitalization must not turn Cmd+A into Cmd+Shift+A.
        return (key, selected | (shifted[char] == nil ? 0 : 1))
    }
}

#if os(iOS)
import SwiftUI
import UIKit

@MainActor
final class NativeKeyboardController: ObservableObject {
    @Published private(set) var flags: UInt = 0
    private weak var input: RemoteInputTextView?
    func attach(_ view: RemoteInputTextView) {
        input = view; view.controller = self
        view.onModifiersChanged = { [weak self, weak view] value in
            // configure/reset can run during updateUIView. Publish after that render pass.
            DispatchQueue.main.async {
                guard let self, let view, self.input === view else { return }
                self.flags = value
            }
        }
    }
    func detach(_ view: RemoteInputTextView) {
        guard input === view else { return }
        input = nil
        DispatchQueue.main.async { [weak self] in if self?.input == nil { self?.flags = 0 } }
    }
    func toggle(_ flag: UInt) { input?.toggleModifier(flag) }
    func sendKey(_ key: String, flags: UInt = 0) { input?.sendShortcutKey(key, flags: flags) }
    func reset() { input?.resetBuffer(); flags = 0 }
}

struct NativeKeyboardInput: UIViewRepresentable {
    var active = true
    var contextID: String
    var secure: Bool
    var onEdit: (LANTextEdit) -> Void
    var onKey: (String, UInt) -> Void
    var onCursorKey: (String) -> Void
    var controller: NativeKeyboardController

    func makeUIView(context: Context) -> RemoteInputTextView { RemoteInputTextView() }
    func updateUIView(_ view: RemoteInputTextView, context: Context) {
        controller.attach(view)
        view.onEdit = onEdit; view.onKey = onKey; view.onCursorKey = onCursorKey
        view.configure(contextID: contextID, secure: secure, active: active)
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: RemoteInputTextView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 0, height: 0)
    }
    static func dismantleUIView(_ view: RemoteInputTextView, coordinator: ()) {
        view.closing = true; view.resetBuffer(); view.resignFirstResponder(); view.controller?.detach(view)
    }
}

final class RemoteInputTextView: UITextView, UITextViewDelegate {
    var onEdit: ((LANTextEdit) -> Void)?
    var onKey: ((String, UInt) -> Void)?
    var onCursorKey: ((String) -> Void)?
    weak var controller: NativeKeyboardController?
    var onModifiersChanged: ((UInt) -> Void)?
    var closing = false
    private var keyboardActive = true
    private var buffer = NativeTextBuffer()
    private var contextID = ""
    private var changing = false
    private var cursorGesture = NativeCursorGesture()
    private var remoteFloatingCursor = false
    private var cancelledFloatingCursor = false
    private var modifiers = ShortcutModifiers()
    private var shortcutInputActive = false

    init() {
        super.init(frame: .zero, textContainer: nil)
        delegate = self
        font = .preferredFont(forTextStyle: .body)
        adjustsFontForContentSizeCategory = true
        // A zero-height IME bridge. The remote desktop is the only text display.
        backgroundColor = .clear; textColor = .clear; tintColor = .clear
        isOpaque = false; isScrollEnabled = false
        textContainerInset = .zero; textContainer.lineFragmentPadding = 0
        isAccessibilityElement = false; accessibilityElementsHidden = true
        keyboardType = .default; textContentType = nil
        smartQuotesType = .no; smartDashesType = .no
        inputAccessoryView = nil
        inputAssistantItem.leadingBarButtonGroups = []; inputAssistantItem.trailingBarButtonGroups = []
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func caretRect(for position: UITextPosition) -> CGRect { .zero }
    override func selectionRects(for range: UITextRange) -> [UITextSelectionRect] { [] }
    func toggleModifier(_ flag: UInt) {
        resetBuffer(keepModifiers: true); modifiers.toggle(flag); updateModifierButtons()
    }
    func sendShortcutKey(_ key: String, flags: UInt) {
        let selected = modifiers.consume()
        resetBuffer(); onKey?(key, flags | selected)
    }
    private func updateModifierButtons() {
        autocapitalizationType = modifiers.flags == 0 ? .sentences : .none
        let active = modifiers.flags != 0
        if active != shortcutInputActive {
            shortcutInputActive = active
            keyboardType = active ? .asciiCapable : .default
            autocorrectionType = active || isSecureTextEntry ? .no : .default
            if isFirstResponder {
                DispatchQueue.main.async { [weak self] in
                    guard let self, !self.closing else { return }
                    self.reloadInputViews()
                }
            }
        }
        onModifiersChanged?(modifiers.flags)
    }

    func configure(contextID: String, secure: Bool, active: Bool) {
        keyboardActive = active
        if !active {
            if isFirstResponder { resetBuffer(keepModifiers: true); resignFirstResponder() }
            return
        }
        if self.contextID != contextID || isSecureTextEntry != secure {
            resetBuffer(); self.contextID = contextID
            isSecureTextEntry = secure
            autocorrectionType = secure ? .no : .default
            if isFirstResponder { reloadInputViews() }
        }
        if !isFirstResponder && !closing {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.window != nil, !self.closing, self.keyboardActive else { return }
                self.becomeFirstResponder()
            }
        }
    }
    func resetBuffer(keepModifiers: Bool = false) {
        if !keepModifiers { modifiers.clear(); updateModifierButtons() }
        if remoteFloatingCursor { cancelledFloatingCursor = true }
        remoteFloatingCursor = false; cursorGesture.end()
        changing = true
        // Clear composition before resigning; unconfirmed candidates must not leak to a new field.
        text = ""; buffer.reset()
        changing = false
    }
    override func beginFloatingCursor(at point: CGPoint) {
        guard !closing, markedTextRange == nil else { super.beginFloatingCursor(at: point); return }
        resetBuffer()
        cancelledFloatingCursor = false; remoteFloatingCursor = true
        cursorGesture.begin(at: point)
    }
    override func updateFloatingCursor(at point: CGPoint) {
        guard !cancelledFloatingCursor else { return }
        guard remoteFloatingCursor else { super.updateFloatingCursor(at: point); return }
        guard !closing else { return }
        let horizontal = max(8, (font?.pointSize ?? 17) * 0.65)
        let vertical = max(20, (font?.lineHeight ?? 22) * 1.25)
        for key in cursorGesture.move(to: point, horizontalStep: horizontal, verticalStep: vertical) { onCursorKey?(key) }
    }
    override func endFloatingCursor() {
        if remoteFloatingCursor {
            remoteFloatingCursor = false; cursorGesture.end(); resetBuffer()
        } else if !cancelledFloatingCursor { super.endFloatingCursor() }
        cancelledFloatingCursor = false
    }
    override func deleteBackward() {
        if text.isEmpty && markedTextRange == nil { let selected = modifiers.consume(); updateModifierButtons(); onKey?("delete", selected) }
        else { super.deleteBackward() }
    }
    func textViewDidChange(_ textView: UITextView) {
        guard !changing, !closing, markedTextRange == nil else { return }
        if let edit = buffer.update(text ?? "", hasMarkedText: false) {
            if modifiers.flags != 0 {
                if let shortcut = modifiers.shortcut(for: edit.text) { onKey?(shortcut.key, shortcut.flags) }
                else { UIAccessibility.post(notification: .announcement, argument: "快捷键需要单个英文字母、数字或按键") }
                resetBuffer(); return
            }
            onEdit?(edit)
        }
        changing = true
        if text != buffer.committed { text = buffer.committed }
        // The relay holds only the phone's recently committed suffix, not the remote document.
        selectedRange = NSRange(location: (text as NSString).length, length: 0)
        changing = false
    }
    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        guard !closing else { return false }
        if markedTextRange == nil && text == "\n" {
            let selected = modifiers.consume(); resetBuffer(); onKey?("return", selected); return false
        }
        return text.utf8.count <= 8192
    }
}
#endif

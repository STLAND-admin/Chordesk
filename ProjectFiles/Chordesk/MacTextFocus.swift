#if os(macOS)
import ApplicationServices
import Foundation

/// Reads only focused element metadata, never text values, passwords, or clipboard data.
actor MacTextFocusMonitor {
    private var previous: AXUIElement?
    private var identity = UUID().uuidString

    func refresh(in displayBounds: CGRect, requestID: UInt64) -> LANTextFocus {
        guard AXIsProcessTrusted() else { return clear(requestID: requestID) }
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.12)
        guard let raw = attribute(system, kAXFocusedUIElementAttribute), CFGetTypeID(raw) == AXUIElementGetTypeID() else {
            return clear(requestID: requestID)
        }
        let element = unsafeBitCast(raw, to: AXUIElement.self)
        AXUIElementSetMessagingTimeout(element, 0.12)
        if previous == nil || !CFEqual(previous!, element) { previous = element; identity = UUID().uuidString }
        let role = attribute(element, kAXRoleAttribute) as? String ?? ""
        let subrole = attribute(element, kAXSubroleAttribute) as? String ?? ""
        let enabled = (attribute(element, kAXEnabledAttribute) as? Bool) != false
        var writable = DarwinBoolean(false)
        AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &writable)
        var selectionWritable = DarwinBoolean(false)
        AXUIElementIsAttributeSettable(element, kAXSelectedTextRangeAttribute as CFString, &selectionWritable)
        let textRole = ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"].contains(role)
        var position = CGPoint.zero, size = CGSize.zero
        let positionOK = point(element, into: &position)
        let sizeOK = dimensions(element, into: &size)
        let onDisplay = positionOK && sizeOK && CGRect(origin: position, size: size).intersects(displayBounds)
        return LANTextFocus(id: identity, editable: enabled && textRole && onDisplay && (writable.boolValue || selectionWritable.boolValue),
                            secure: subrole == "AXSecureTextField", requestID: requestID)
    }
    private func clear(requestID: UInt64) -> LANTextFocus {
        if previous != nil { previous = nil; identity = UUID().uuidString }
        return LANTextFocus(id: identity, editable: false, secure: false, requestID: requestID)
    }
    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success else { return nil }
        return result
    }
    private func point(_ element: AXUIElement, into result: inout CGPoint) -> Bool {
        guard let raw = attribute(element, kAXPositionAttribute), CFGetTypeID(raw) == AXValueGetTypeID() else { return false }
        return AXValueGetValue(unsafeBitCast(raw, to: AXValue.self), .cgPoint, &result)
    }
    private func dimensions(_ element: AXUIElement, into result: inout CGSize) -> Bool {
        guard let raw = attribute(element, kAXSizeAttribute), CFGetTypeID(raw) == AXValueGetTypeID() else { return false }
        return AXValueGetValue(unsafeBitCast(raw, to: AXValue.self), .cgSize, &result)
    }
}
#endif

import SwiftUI

/// Local page/shift keys never produce remote input. Printable symbols are text,
/// so the host's physical keyboard layout cannot reinterpret them.
enum MobileKeyboardAction: Equatable {
    case text(String)
    case key(String)
}

struct MobileKeyboardState {
    enum Page { case alphabet, numbers, symbols }
    enum Shift { case off, once, locked }
    private(set) var page: Page = .alphabet
    private(set) var shift: Shift = .off
    private var lastShiftTap: TimeInterval?

    mutating func press(_ key: String, now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> MobileKeyboardAction? {
        switch key {
        case "page-numbers": page = .numbers; lastShiftTap = nil; return nil
        case "page-symbols": page = .symbols; lastShiftTap = nil; return nil
        case "page-alphabet": page = .alphabet; lastShiftTap = nil; return nil
        case "shift":
            if shift == .locked { shift = .off; lastShiftTap = nil }
            else if let previous = lastShiftTap, now >= previous, now - previous <= 0.35 {
                shift = .locked; lastShiftTap = nil
            } else { shift = shift == .off ? .once : .off; lastShiftTap = now }
            return nil
        case "delete": lastShiftTap = nil; return .key("delete")
        case "return": page = .alphabet; lastShiftTap = nil; return .key("return")
        case "space": page = .alphabet; lastShiftTap = nil; return .text(" ")
        default:
            lastShiftTap = nil
            guard key.count == 1 else { return nil }
            let text = page == .alphabet && shift != .off ? key.uppercased() : key
            if page == .alphabet && shift == .once { shift = .off }
            return .text(text)
        }
    }
}

struct MobileKey: Identifiable {
    var id: String
    var title: String
    var weight: CGFloat = 1
    var symbol: String? = nil
    var spacer = false
    static func characters(_ text: String) -> [Self] { text.map { Self(id: String($0), title: String($0)) } }
    static func space(_ id: String, _ weight: CGFloat) -> Self { Self(id: id, title: "", weight: weight, spacer: true) }
}

extension MobileKeyboardState {
    var rows: [[MobileKey]] {
        let backspace = MobileKey(id: "delete", title: "退格", weight: 1.4, symbol: "delete.left")
        let change = MobileKey(id: "page-alphabet", title: "ABC", weight: 1.5)
        let bottom = [page == .alphabet ? MobileKey(id: "page-numbers", title: "123", weight: 1.5) : change,
                      MobileKey(id: "space", title: "空格", weight: 5.8),
                      MobileKey(id: "return", title: "换行", weight: 2, symbol: "return")]
        switch page {
        case .alphabet:
            return [MobileKey.characters("qwertyuiop"),
                    [.space("leading", 0.5)] + MobileKey.characters("asdfghjkl") + [.space("trailing", 0.5)],
                    [MobileKey(id: "shift", title: shift == .locked ? "大写锁定" : "大写", weight: 1.4,
                               symbol: shift == .locked ? "capslock.fill" : shift == .once ? "shift.fill" : "shift")]
                    + MobileKey.characters("zxcvbnm") + [backspace], bottom]
        case .numbers, .symbols:
            let toggle = MobileKey(id: page == .numbers ? "page-symbols" : "page-numbers", title: page == .numbers ? "#+=" : "123", weight: 1.4)
            return [MobileKey.characters(page == .numbers ? "1234567890" : "[]{}#%^*+="),
                    MobileKey.characters(page == .numbers ? "-/:;()$&@\"" : "_\\|~<>€£¥•"),
                    [toggle] + MobileKey.characters(".,?!'").map { var key = $0; key.weight = 1.4; return key } + [backspace], bottom]
        }
    }
}

private struct MobileKeyWeight: LayoutValueKey { static let defaultValue: CGFloat = 1 }
private struct MobileKeyRow: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize { proposal.replacingUnspecifiedDimensions() }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let gap = min(6, bounds.width / 100)
        let unit = max(0, bounds.width - gap * CGFloat(max(0, subviews.count - 1))) / max(1, subviews.reduce(0) { $0 + $1[MobileKeyWeight.self] })
        var x = bounds.minX
        for view in subviews {
            let width = unit * view[MobileKeyWeight.self]
            view.place(at: CGPoint(x: x, y: bounds.minY), anchor: .topLeading,
                       proposal: ProposedViewSize(width: width, height: bounds.height))
            x += width + gap
        }
    }
}

private struct MobileKeyStyle: ButtonStyle {
    var selected: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(selected ? Color.accentColor : .primary)
            .background(Color.accentColor.opacity(configuration.isPressed ? 0.35 : selected ? 0.18 : 0), in: .rect(cornerRadius: 9))
            .background(.regularMaterial, in: .rect(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(.primary.opacity(0.12)))
    }
}

/// A phone-style remote keyboard, not an IME. Native input remains available for
/// Chinese composition and third-party keyboards.
struct MobileTouchKeyboard: View {
    @State private var state = MobileKeyboardState()
    var onAction: (MobileKeyboardAction) -> Void
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 6) {
                ForEach(state.rows.indices, id: \.self) { row in
                    MobileKeyRow {
                        ForEach(state.rows[row]) { key in
                            Group {
                                if key.spacer { Color.clear.accessibilityHidden(true) }
                                else {
                                    Button {
                                        if let action = state.press(key.id) { onAction(action) }
                                    } label: {
                                        Group {
                                            if let symbol = key.symbol { Image(systemName: symbol) }
                                            else { Text(state.page == .alphabet && state.shift != .off && key.id.count == 1 ? key.title.uppercased() : key.title) }
                                        }
                                        .font(.system(size: min(24, max(12, geometry.size.height / 10)), weight: .medium))
                                        .lineLimit(1).minimumScaleFactor(0.65)
                                    }
                                    .buttonStyle(MobileKeyStyle(selected: key.id == "shift" && state.shift != .off))
                                    .accessibilityLabel(key.title)
                                    .accessibilityIdentifier("mobile-key-\(key.id)")
                                }
                            }.layoutValue(key: MobileKeyWeight.self, value: key.weight)
                        }
                    }
                }
            }.padding(8)
        }

    }
}

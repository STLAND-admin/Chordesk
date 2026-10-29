import SwiftUI

private struct KeySpec: Identifiable {
    let id: String
    var label: String
    var weight: CGFloat = 1
    var symbol: String? = nil
}
private struct KeyWeight: LayoutValueKey { static let defaultValue: CGFloat = 1 }
private struct KeyRow: Layout {
    var gap: CGFloat = 4
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let unit = max(0, bounds.width - gap * CGFloat(max(0, subviews.count - 1))) / max(1, subviews.reduce(0) { $0 + $1[KeyWeight.self] })
        var x = bounds.minX
        for view in subviews {
            let width = unit * view[KeyWeight.self]
            view.place(at: CGPoint(x: x, y: bounds.minY), anchor: .topLeading, proposal: ProposedViewSize(width: width, height: bounds.height))
            x += width + gap
        }
    }
}
private struct TouchKeyStyle: ButtonStyle {
    let active: Bool
    let accent: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(accent || active ? Color.white : Color.white.opacity(0.9))
            .background(configuration.isPressed ? Color.teal : active || accent ? Color(red: 0.18, green: 0.43, blue: 0.52) : Color.white.opacity(0.13),
                        in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.white.opacity(0.08)))
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
    }
}

/// An always visible touch keyboard. No TextField, IME popup, or system keyboard.
struct TouchKeyboard: View {
    @ObservedObject var session: DemoSession
    var transparentBackground = false
    var onKey: ((String) -> Void)? = nil
    private let rows: [[KeySpec]] = [
        [KeySpec(id: "esc", label: "esc", weight: 1.2)] + Array("1234567890").map { KeySpec(id: String($0), label: String($0)) } + [KeySpec(id: "delete", label: "退格", weight: 1.5, symbol: "delete.left")],
        [KeySpec(id: "tab", label: "tab", weight: 1.4)] + Array("qwertyuiop").map { KeySpec(id: String($0), label: String($0)) } + [KeySpec(id: "-", label: "−")],
        Array("asdfghjkl").map { KeySpec(id: String($0), label: String($0)) } + [KeySpec(id: "'", label: "'"), KeySpec(id: "return", label: "换行", weight: 2, symbol: "return")],
        [KeySpec(id: "shift", label: "Shift", weight: 1.6, symbol: "shift")] + Array("zxcvbnm").map { KeySpec(id: String($0), label: String($0)) } + [KeySpec(id: ",", label: ","), KeySpec(id: ".", label: "."), KeySpec(id: "up", label: "开头", symbol: "arrow.up")],
        [KeySpec(id: "ctrl", label: "ctrl"), KeySpec(id: "opt", label: "⌥"), KeySpec(id: "cmd", label: "⌘"), KeySpec(id: "space", label: "space", weight: 5.2), KeySpec(id: "left", label: "向左", symbol: "arrow.left"), KeySpec(id: "down", label: "末尾", symbol: "arrow.down"), KeySpec(id: "right", label: "向右", symbol: "arrow.right")]
    ]

    var body: some View {
        GeometryReader { geometry in
            let keyHeight = max(1, (geometry.size.height - 16 - 4 * 4) / 5)
            VStack(spacing: 4) {
                ForEach(rows.indices, id: \.self) { index in
                    KeyRow {
                        ForEach(rows[index]) { key in
                            Button {
                                if let onKey { onKey(key.id) } else { session.key(key.id) }
                            } label: {
                                Group {
                                    if let symbol = key.symbol { Image(systemName: symbol) }
                                    else { Text(session.shift && key.id.count == 1 ? key.label.uppercased() : key.label) }
                                }
                                .font(.system(size: min(18, max(9, keyHeight * 0.46)), weight: .medium, design: .rounded))
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                            }
                            .buttonStyle(TouchKeyStyle(active: isActive(key.id), accent: key.id == "return"))
                            .accessibilityLabel(key.id.count == 1 ? key.id.uppercased() : key.label)
                            .accessibilityIdentifier("key-\(key.id)")
                            .layoutValue(key: KeyWeight.self, value: key.weight)
                        }
                    }
                }
            }
            .padding(8)
        }
        .background(transparentBackground ? Color.clear : Color(red: 0.10, green: 0.13, blue: 0.18))
    }

    private func isActive(_ key: String) -> Bool {
        switch key {
        case "shift": session.shift
        case "cmd": session.command
        case "opt": session.option
        case "ctrl": session.control
        default: false
        }
    }
}

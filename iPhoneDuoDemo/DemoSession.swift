import SwiftUI

struct InteractionEntry: Identifiable {
    let id = UUID()
    let time = Date()
    let message: String
}

/// Local simulation shared by the iOS inner screen and the Mac dual-screen workbench.
@MainActor
final class DemoSession: ObservableObject {
    static let welcome = "把屏幕留给内容。\n\n点下面的屏幕键盘开始输入。\n用旁边的触控板移动光标，按住后拖动窗口标题栏。\n\n双指滚动 · 双指轻点右键\n拇指负责键盘，食指与中指负责触控板。"
    @Published var document = DemoSession.welcome
    @Published var caret = DemoSession.welcome.count
    @Published var selectedAll = false
    @Published var cursor = CGPoint(x: 0.5, y: 0.3)
    @Published var windowOrigin = CGPoint(x: 0.16, y: 0.12)
    @Published var windowExpanded = false
    @Published var scrollFraction: CGFloat = 0
    @Published var contextVisible = false
    @Published var shift = false
    @Published var command = false
    @Published var option = false
    @Published var control = false
    @Published var status = "就绪"
    @Published var logs: [InteractionEntry] = []
    private var clipboard = ""
    private var undoStack: [String] = []
    private var draggingWindow = false
    // Actual laid-out hit regions for the simulated pointer, normalized to the monitor.
    var monitorTargets: [String: CGRect] = [:]

    var noteRect: CGRect {
        windowExpanded ? CGRect(x: 0.04, y: 0.05, width: 0.92, height: 0.90)
                       : CGRect(x: windowOrigin.x, y: windowOrigin.y, width: 0.76, height: 0.79)
    }
    var beforeCaret: String { String(document.prefix(caret)) }
    var afterCaret: String { String(document.dropFirst(caret)) }

    func record(_ message: String) {
        status = message
        logs.append(InteractionEntry(message: message))
        if logs.count > 60 { logs.removeFirst(logs.count - 60) }
    }

    func reset() {
        document = Self.welcome
        caret = document.count
        selectedAll = false
        cursor = CGPoint(x: 0.5, y: 0.3)
        windowOrigin = CGPoint(x: 0.16, y: 0.12)
        windowExpanded = false
        scrollFraction = 0
        contextVisible = false
        shift = false; command = false; option = false; control = false
        draggingWindow = false
        undoStack = []
        record("已重置")
    }

    func key(_ value: String) {
        switch value {
        case "shift": shift.toggle(); return
        case "cmd": command.toggle(); return
        case "opt": option.toggle(); return
        case "ctrl": control.toggle(); return
        case "esc": contextVisible = false; selectedAll = false; record("Esc"); return
        case "left": caret = max(0, caret - 1); selectedAll = false; record("向左"); return
        case "right": caret = min(document.count, caret + 1); selectedAll = false; record("向右"); return
        case "up": caret = 0; selectedAll = false; scrollFraction = 0; record("文稿开头"); return
        case "down": caret = document.count; selectedAll = false; scrollFraction = 1; record("文稿末尾"); return
        default: break
        }
        if command {
            switch value.lowercased() {
            case "a": selectedAll = true; record("全选")
            case "c": if selectedAll { clipboard = document }; record("复制到演示剪贴板")
            case "v": insert(clipboard); record("粘贴")
            case "z":
                if let old = undoStack.popLast() { document = old; caret = old.count; selectedAll = false }
                record("撤销")
            default: record("快捷键 ⌘\(value.uppercased())")
            }
            command = false
            return
        }
        if control || option {
            record("快捷键 \(control ? "Ctrl " : "")\(option ? "Option " : "")\(value.uppercased())")
            control = false; option = false
            return
        }
        if value == "delete" {
            undoStack.append(document)
            if selectedAll { document = ""; caret = 0; selectedAll = false }
            else if caret > 0 {
                let index = document.index(document.startIndex, offsetBy: caret - 1)
                document.remove(at: index)
                caret -= 1
            }
            record("退格")
        } else {
            let input = value == "space" ? " " : value == "return" ? "\n" : value == "tab" ? "    " : shift ? value.uppercased() : value.lowercased()
            insert(input)
            record(value == "space" ? "空格" : value == "return" ? "换行" : "输入 \(input)")
            shift = false
        }
    }

    func insert(_ text: String) {
        undoStack.append(document)
        if undoStack.count > 50 { undoStack.removeFirst() }
        if selectedAll { document = ""; caret = 0; selectedAll = false }
        let index = document.index(document.startIndex, offsetBy: min(caret, document.count))
        document.insert(contentsOf: text, at: index)
        caret += text.count
        scrollFraction = 1
    }

    func clearDocument() {
        selectedAll = true
        key("delete")
        contextVisible = false
    }

    func click(at point: CGPoint? = nil) {
        if let point { cursor = point }
        if contextVisible {
            let target = ["select", "copy", "clear"].first { monitorTargets[$0]?.contains(cursor) == true }
            contextVisible = false
            switch target {
            case "select": selectedAll = true; record("全选文稿"); return
            case "copy": command = true; key("c"); return
            case "clear": clearDocument(); return
            default: break
            }
        }
        contextVisible = false
        if noteRect.contains(cursor) { selectedAll = false; record("文稿已聚焦") }
        else if cursor.x < 0.16 { record("打开 Demo 文稿"); windowOrigin = CGPoint(x: 0.16, y: 0.12) }
        else { record("桌面点击") }
    }

    func moveWindow(dx: CGFloat, dy: CGFloat) {
        windowOrigin = CGPoint(x: min(max(windowOrigin.x + dx, 0.01), 0.23),
                               y: min(max(windowOrigin.y + dy, 0.03), 0.20))
    }

    func setWindowExpanded(_ expanded: Bool) {
        guard windowExpanded != expanded else { return }
        withAnimation(.spring(response: 0.38, dampingFraction: 0.84)) {
            windowExpanded = expanded
        }
        record(expanded ? "三指上滑 · 展开文稿" : "三指下滑 · 还原文稿")
    }

    func touchpad(_ event: TouchpadEvent) {
        switch event {
        case let .pointerMoved(dx, dy): movePointer(dx: dx, dy: dy); status = "移动光标"
        case .leftClick: click(); record("左键点击")
        case .rightClick: contextVisible = true; record("右键菜单")
        case .dragBegan:
            draggingWindow = !contextVisible && (monitorTargets["title"]?.contains(cursor) ?? false)
            record("拖拽开始")
        case let .dragMoved(dx, dy):
            let previous = cursor
            movePointer(dx: dx, dy: dy)
            if draggingWindow { moveWindow(dx: cursor.x - previous.x, dy: cursor.y - previous.y) }
            status = "拖拽中"
        case .dragEnded: draggingWindow = false; record("拖拽结束")
        case let .scrolled(amount):
            scrollFraction = min(max(scrollFraction - amount * 2, 0), 1)
            record("滚动文稿")
        }
    }

    private func movePointer(dx: CGFloat, dy: CGFloat) {
        cursor = CGPoint(x: min(max(cursor.x + dx * 1.5, 0.01), 0.99),
                         y: min(max(cursor.y + dy * 1.5, 0.01), 0.99))
    }
}

import SwiftUI

private struct TextHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct MonitorTargets: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
private extension View {
    func monitorTarget(_ name: String) -> some View {
        background(GeometryReader { geometry in
            Color.clear.preference(key: MonitorTargets.self, value: [name: geometry.frame(in: .named("demo-monitor"))])
        })
    }
}

struct MonitorView: View {
    @ObservedObject var session: DemoSession
    @State private var textHeight: CGFloat = 0
    @State private var previousDrag: CGSize = .zero

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: [Color(red: 0.17, green: 0.27, blue: 0.38), Color(red: 0.35, green: 0.39, blue: 0.55), Color(red: 0.13, green: 0.35, blue: 0.39)], startPoint: .topLeading, endPoint: .bottomTrailing)
                VStack(alignment: .leading, spacing: 7) {
                    Image(systemName: "folder.fill").font(.title).foregroundStyle(.cyan.opacity(0.8))
                    Text("Demo").font(.caption).foregroundStyle(.white)
                }
                .padding()
                .monitorTarget("folder")
                .onTapGesture { session.click(at: CGPoint(x: 0.06, y: 0.13)) }

                noteWindow(size: size)
                    .frame(width: size.width * session.noteRect.width, height: size.height * session.noteRect.height)
                    .position(x: size.width * session.noteRect.midX, y: size.height * session.noteRect.midY)

                if session.contextVisible {
                    VStack(alignment: .leading, spacing: 10) {
                        Button("全选文稿") { session.selectedAll = true; session.contextVisible = false }
                            .monitorTarget("select")
                        Button("复制") { session.command = true; session.key("c"); session.contextVisible = false }
                            .monitorTarget("copy")
                        Divider()
                        Button("清空文稿") { session.clearDocument() }
                            .monitorTarget("clear")
                    }
                    .buttonStyle(.plain)
                    .font(.callout)
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                    .position(x: size.width * min(max(session.cursor.x, 0.2), 0.8), y: size.height * min(max(session.cursor.y, 0.2), 0.75))
                }

                Image(systemName: "arrow.up.left")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.8), radius: 1)
                    .position(x: size.width * session.cursor.x, y: size.height * session.cursor.y)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)

                VStack {
                    Spacer()
                    HStack {
                        Label("Demo Mac", systemImage: "desktopcomputer")
                        Spacer()
                        Text("本地交互模拟")
                    }
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.horizontal)
                    .padding(.bottom, 7)
                }
                .allowsHitTesting(false)
            }
            .clipped()
            .coordinateSpace(name: "demo-monitor")
            .onPreferenceChange(MonitorTargets.self) { targets in
                session.monitorTargets = targets.mapValues { rect in
                    CGRect(x: rect.minX / max(1, size.width), y: rect.minY / max(1, size.height),
                           width: rect.width / max(1, size.width), height: rect.height / max(1, size.height))
                }
            }
        }
    }

    private func noteWindow(size: CGSize) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "circle.fill").foregroundStyle(.red.opacity(0.7))
                Image(systemName: "circle.fill").foregroundStyle(.yellow.opacity(0.8))
                Image(systemName: "circle.fill").foregroundStyle(.green.opacity(0.7))
                Spacer()
                Text("Duo · 演示文稿").foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "doc.text")
            }
            .font(.caption)
            .foregroundStyle(Color(red: 0.34, green: 0.39, blue: 0.37))
            .padding(10)
            .background(Color.black.opacity(0.04))
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 2).onChanged { value in
                session.moveWindow(dx: (value.translation.width - previousDrag.width) / max(1, size.width),
                                   dy: (value.translation.height - previousDrag.height) / max(1, size.height))
                previousDrag = value.translation
            }.onEnded { _ in previousDrag = .zero; session.record("窗口已移动") })
            .accessibilityIdentifier("demo-window-title")
            .monitorTarget("title")

            GeometryReader { content in
                VStack(alignment: .leading, spacing: 0) {
                    (Text(session.beforeCaret) + Text("▏").foregroundColor(.teal) + Text(session.afterCaret))
                        .font(.system(size: max(12, min(18, size.width * 0.026)), design: .monospaced))
                        .lineSpacing(5)
                        .foregroundStyle(Color(red: 0.18, green: 0.23, blue: 0.29))
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .background(session.selectedAll ? Color.teal.opacity(0.16) : .clear)
                        .fixedSize(horizontal: false, vertical: true)
                        .background(GeometryReader { value in Color.clear.preference(key: TextHeightKey.self, value: value.size.height) })
                        .offset(y: -max(0, textHeight - content.size.height) * session.scrollFraction)
                }
                .onPreferenceChange(TextHeightKey.self) { textHeight = $0 }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped()
                .contentShape(Rectangle())
                .onTapGesture { session.selectedAll = false; session.record("文稿已聚焦") }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("演示文稿")
                .accessibilityValue(session.document)
                .accessibilityIdentifier("document-echo")
            }
        }
        .background(Color(red: 0.98, green: 0.98, blue: 0.96))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.22), radius: 18, y: 8)
    }
}

struct InnerDisplay: View {
    @ObservedObject var session: DemoSession
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                MonitorView(session: session)
                    .frame(height: geometry.size.height * 0.75)
                TouchKeyboard(session: session)
                    .frame(height: geometry.size.height * 0.25)
            }
        }
    }
}

struct InteractionLog: View {
    @ObservedObject var session: DemoSession
    var body: some View {
        List(session.logs.reversed()) { entry in
            HStack {
                Text(entry.time, style: .time).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Text(entry.message)
            }
        }
    }
}

#if os(iOS)
import SwiftUI

struct RearAreaSettings: View {
    @ObservedObject var camera: CameraAccessory
    @AppStorage("rearCustomAreaEnabledV1") private var enabled = false
    @AppStorage("outerTouchEdgeInset") private var inset = TouchpadTuning.defaultEdgeInset
    var body: some View {
        Section("背面有效区域") {
            Toggle("自定义有效区域", isOn: $enabled).accessibilityIdentifier("rear-custom-area")
            NavigationLink {
                RearAreaEditor(camera: camera)
            } label: { Label("可视化调整区域", systemImage: "viewfinder") }
                .accessibilityIdentifier("rear-area-editor-link")
            if !enabled {
                Slider(value: $inset, in: 0...0.25, step: 0.025) { Text("外屏边缘禁触比例") }
                    .accessibilityIdentifier("outer-edge-inset-slider")
                    .accessibilityValue(String(format: "%.1f%%", TouchpadTuning.edgeInset(inset) * 100))
                Text("简易模式：每边排除 \(TouchpadTuning.edgeInset(inset) * 100, specifier: "%.1f")%。")
                HStack { Button("10%") { inset = 0.1 }; Button("12.5%") { inset = 0.125 } }.buttonStyle(.bordered)
            }
            Text("可移动矩形、拖动四角调整大小，也可贴边。区域基于外屏当前可用安全范围；落在区域外或滑出区域的手指需抬起后重按。修改时会取消旧接触。")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
}

struct RearAreaEditor: View {
    @ObservedObject var camera: CameraAccessory
    @AppStorage("rearCustomAreaEnabledV1") private var enabled = false
    @AppStorage("rearActiveBoxV1") private var stored = ""
    @AppStorage("outerTouchEdgeInset") private var inset = TouchpadTuning.defaultEdgeInset
    @State private var dragOrigin: RearActiveRegion?
    private var region: RearActiveRegion { enabled ? .decode(stored, inset: inset) : .centered(inset: inset) }
    private var aspect: CGFloat {
        let size = camera.rearViewportSize
        return size.width > 0 && size.height > 0 ? size.width / size.height : 1
    }
    private func save(_ value: RearActiveRegion) { stored = value.normalized.encoded; enabled = true }
    var body: some View {
        GeometryReader { viewport in
        Form {
            Section {
                GeometryReader { geometry in
                    let rect = region.rect(in: CGRect(origin: .zero, size: geometry.size))
                    ZStack(alignment: .topLeading) {
                        Rectangle().fill(Color.secondary.opacity(0.18))
                        Rectangle().fill(Color.mint.opacity(0.3))
                            .overlay { Rectangle().stroke(.mint, lineWidth: 2) }
                            .overlay { Image(systemName: "arrow.up.and.down.and.arrow.left.and.right").font(.title2).allowsHitTesting(false) }
                            .frame(width: rect.width, height: rect.height)
                            .contentShape(Rectangle())
                            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("rear-editor")).onChanged { value in
                                let start = dragOrigin ?? region; dragOrigin = start
                                save(start.translated(dx: value.translation.width / max(1, geometry.size.width),
                                                      dy: value.translation.height / max(1, geometry.size.height)))
                            }.onEnded { _ in dragOrigin = nil })
                            .position(x: rect.midX, y: rect.midY)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("有效区域，拖动移动")
                            .accessibilityValue(String(format: "X %.1f%%，Y %.1f%%，宽 %.1f%%，高 %.1f%%", region.x * 100, region.y * 100, region.width * 100, region.height * 100))
                            .accessibilityIdentifier("rear-area-move")
                        ForEach(RearActiveRegion.Corner.allCases, id: \.self) { corner in
                            let left = corner == .topLeft || corner == .bottomLeft
                            let top = corner == .topLeft || corner == .topRight
                            Image(systemName: "circle.inset.filled").font(.title2)
                                .foregroundStyle(.mint).padding(8).background(.regularMaterial, in: Circle())
                                .contentShape(Circle())
                                .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("rear-editor")).onChanged { value in
                                    let start = dragOrigin ?? region; dragOrigin = start
                                    save(start.resized(corner, dx: value.translation.width / max(1, geometry.size.width),
                                                       dy: value.translation.height / max(1, geometry.size.height)))
                                }.onEnded { _ in dragOrigin = nil })
                                .position(x: left ? rect.minX : rect.maxX, y: top ? rect.minY : rect.maxY)
                                .accessibilityLabel("\(top ? "上" : "下")\(left ? "左" : "右")角，拖动缩放")
                                .accessibilityIdentifier("rear-area-" + corner.rawValue)
                        }
                    }.coordinateSpace(name: "rear-editor")
                }.aspectRatio(aspect, contentMode: .fit)
                    .frame(maxHeight: viewport.size.height * 0.55).padding()
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("rear-area-canvas")
                Text("绿色为有效区。拖动中间移动、拖动四角缩放，自动保存。\(camera.rearViewportSize == .zero ? "外屏未显示时使用比例示意；外屏出现后同步画幅。" : "画幅来自当前外屏可用区域。")")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("位置与大小") {
                regionSlider("左侧位置", path: \.x, range: 0...(1 - region.width))
                regionSlider("顶部位置", path: \.y, range: 0...(1 - region.height))
                regionSlider("宽度", path: \.width, range: RearActiveRegion.minimum...(1 - region.x))
                regionSlider("高度", path: \.height, range: RearActiveRegion.minimum...(1 - region.y))
                Text("X \(region.x * 100, specifier: "%.0f")% · Y \(region.y * 100, specifier: "%.0f")% · 宽 \(region.width * 100, specifier: "%.0f")% · 高 \(region.height * 100, specifier: "%.0f")%")
                    .font(.caption.monospacedDigit()).accessibilityIdentifier("rear-area-summary")
            }
            Section("快速放置") {
                HStack {
                    Button("贴左半屏") { save(.init(x: 0, y: 0, width: 0.5, height: 1)) }.accessibilityIdentifier("rear-area-left")
                    Button("贴右半屏") { save(.init(x: 0.5, y: 0, width: 0.5, height: 1)) }
                }
                HStack {
                    Button("贴下半屏") { save(.init(x: 0, y: 0.5, width: 1, height: 0.5)) }
                    Button("居中") { save(.centered(inset: inset)) }
                }
                Button("恢复简易边缘模式") { enabled = false; dragOrigin = nil }
            }.buttonStyle(.bordered)
        }.navigationTitle("背面有效区域").navigationBarTitleDisplayMode(.inline)
        }
    }
    @ViewBuilder private func regionSlider(_ title: String, path: WritableKeyPath<RearActiveRegion, Double>, range: ClosedRange<Double>) -> some View {
        LabeledContent(title, value: String(format: "%.0f%%", region[keyPath: path] * 100))
        if range.upperBound - range.lowerBound > 0.001 {
            Slider(value: Binding(get: { region[keyPath: path] }, set: { value in var next = region; next[keyPath: path] = value; save(next) }), in: range, step: 0.01) { Text(title) }
        }
    }
}
#endif

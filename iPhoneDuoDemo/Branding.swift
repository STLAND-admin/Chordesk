import SwiftUI

enum ChordBrand {
    static func image(_ name: String, extension ext: String = "png") -> Image? {
#if SWIFT_PACKAGE
        let bundle = Bundle.module
#else
        let bundle = Bundle.main
#endif
        guard let url = bundle.url(forResource: name, withExtension: ext, subdirectory: "Brand") else { return nil }
#if os(macOS)
        guard let image = NSImage(contentsOf: url) else { return nil }
        return Image(nsImage: image)
#else
        guard let image = UIImage(contentsOfFile: url.path) else { return nil }
        return Image(uiImage: image)
#endif
    }
}

struct ChordAboutView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    ChordBrand.image("Chordesk")?.resizable().scaledToFit()
                        .frame(maxHeight: 160).accessibilityLabel("Chordesk：前后交叠的玻璃曲面")
                    Text("Chordesk").font(.largeTitle.bold())
                    Text("前后协作，像按和弦一样控制。").font(.title3)
                    Text("为 Duo 设计。背面按住或切换，正面拇指完成触控、拖选和输入。两片交叠的玻璃曲面，表达正面与背面的协同操作。").foregroundStyle(.secondary)
                    Text("局域网免登录；公网可选内嵌 Tailscale。背面交互依赖相机辅助接口；相机帧不显示、不保存、不传输。").font(.footnote).foregroundStyle(.secondary)
                    NavigationLink("第三方组件许可") { ThirdPartyNoticesView() }
                    Divider()
                    STLANDWordmark().fill(.primary).aspectRatio(1380.0 / 860, contentMode: .fit)
                        .frame(maxHeight: 110).accessibilityLabel("STLAND 透明底黑白文字标志")
                    Text("STLAND 出品").font(.headline)
                    Text("最终解释权归开发者本人所有。").font(.footnote).foregroundStyle(.secondary)
                    Text("版本 \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版") · \(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "")")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding()
            }
            .navigationTitle("关于 Chordesk")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
#if os(macOS)
        .frame(minWidth: 420, idealWidth: 520, minHeight: 540)
#endif
    }
}

private struct ThirdPartyNoticesView: View {
    @State private var notice = "正在读取许可…"
    var body: some View {
        ScrollView { Text(notice).font(.caption).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding() }
            .navigationTitle("第三方组件许可")
            .task {
#if SWIFT_PACKAGE
                let bundle = Bundle.module
#else
                let bundle = Bundle.main
#endif
                if let url = bundle.url(forResource: "ThirdPartyNotices", withExtension: "txt", subdirectory: "Legal") {
                    notice = (try? String(contentsOf: url, encoding: .utf8)) ?? "无法读取许可文件。"
                } else { notice = "许可文件缺失，请使用完整构建。" }
            }
    }
}

private struct STLANDWordmark: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 350.0, y: 90.0))
        p.addLine(to: CGPoint(x: 10.0, y: 90.0))
        p.addLine(to: CGPoint(x: 10.0, y: 260.0))
        p.addLine(to: CGPoint(x: 180.0, y: 260.0))
        p.addLine(to: CGPoint(x: 180.0, y: 430.0))
        p.addLine(to: CGPoint(x: 10.0, y: 430.0))
        p.move(to: CGPoint(x: 95.0, y: 345.0))
        p.addLine(to: CGPoint(x: 520.0, y: 345.0))
        p.move(to: CGPoint(x: 265.0, y: 345.0))
        p.addLine(to: CGPoint(x: 265.0, y: 845.0))
        p.move(to: CGPoint(x: 435.0, y: 5.0))
        p.addLine(to: CGPoint(x: 435.0, y: 685.0))
        p.addLine(to: CGPoint(x: 1115.0, y: 685.0))
        p.move(to: CGPoint(x: 520.0, y: 685.0))
        p.addLine(to: CGPoint(x: 690.0, y: 175.0))
        p.addLine(to: CGPoint(x: 860.0, y: 685.0))
        p.move(to: CGPoint(x: 520.0, y: 430.0))
        p.addLine(to: CGPoint(x: 775.0, y: 430.0))
        p.move(to: CGPoint(x: 775.0, y: 685.0))
        p.addLine(to: CGPoint(x: 860.0, y: 430.0))
        p.addLine(to: CGPoint(x: 945.0, y: 685.0))
        p.addLine(to: CGPoint(x: 1000.0, y: 540.0))
        p.move(to: CGPoint(x: 1165.0, y: 175.0))
        p.addLine(to: CGPoint(x: 1165.0, y: 770.0))
        p.move(to: CGPoint(x: 1115.0, y: 600.0))
        p.addLine(to: CGPoint(x: 1365.0, y: 600.0))
        p.move(to: CGPoint(x: 1215.0, y: 562.0))
        p.addCurve(to: CGPoint(x: 1103.0, y: 685.0), control1: CGPoint(x: 1215.0, y: 630.0), control2: CGPoint(x: 1165.0, y: 685.0))
        p.addCurve(to: CGPoint(x: 991.0, y: 562.0), control1: CGPoint(x: 1041.0, y: 685.0), control2: CGPoint(x: 991.0, y: 630.0))
        p.addCurve(to: CGPoint(x: 1103.0, y: 439.0), control1: CGPoint(x: 991.0, y: 494.0), control2: CGPoint(x: 1041.0, y: 439.0))
        p.addCurve(to: CGPoint(x: 1215.0, y: 562.0), control1: CGPoint(x: 1165.0, y: 439.0), control2: CGPoint(x: 1215.0, y: 494.0))
        p.closeSubpath()
        // Expand strokes before scaling so the SVG and native drawing match.
        return p.strokedPath(StrokeStyle(lineWidth: 9, lineCap: .square, lineJoin: .miter))
            .applying(CGAffineTransform(scaleX: rect.width / 1380, y: rect.height / 860))
            .applying(CGAffineTransform(translationX: rect.minX, y: rect.minY))
    }
}

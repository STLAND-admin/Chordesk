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
                    ChordBrand.image("STLANDSymbol", extension: "jpg")?.resizable().scaledToFit().frame(maxHeight: 80)
                        .accessibilityLabel("STLAND 个人标志")
                    Text("STLAND present · STLAND 出品").font(.headline)
                    DisclosureGroup("STLAND 品牌标志") {
                        HStack {
                            ChordBrand.image("STLANDColor", extension: "jpg")?.resizable().scaledToFit()
                            ChordBrand.image("STLANDOutline", extension: "jpg")?.resizable().scaledToFit()
                        }.frame(maxHeight: 200)
                    }
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

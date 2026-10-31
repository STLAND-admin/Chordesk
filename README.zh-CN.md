<p align="center"><img src="Branding/Chordesk-transparent.svg" width="150" alt="Chordesk"></p>

# Chordesk

[English](README.md) · 简体中文

**指间和弦，掌控桌面。**

为 iPhone Duo 设计的远程桌面：正面拇指触控和输入，背面手指像按和弦一样切换操作模式。包含 **iOS 控制端** 和 **Mac 主机端**。

[概念与 3D 演示](https://stland-admin.github.io/Chordesk-site/) · [操作指南](OPERATION-GUIDE.md) · [开发计划](ROADMAP.md)

## 安装

### Mac

下载 [Mac 0.18.1 试用 Release](https://github.com/STLAND-admin/Chordesk/releases/tag/mac-v0.18.1-test)，打开 DMG，把 Chordesk 拖入“应用程序”。

- Apple Silicon，macOS 15.2 或更新。测试包未公证，首次打开需由接收者按系统提示允许；[安装说明](docs/MAC-PEER-TEST.txt)。
- 首次点“开始服务”，按引导完成屏幕录制和控制两项权限；检查完整后自动重启 App 一次，默认开启内置屏服务。关闭窗口后保留菜单栏后台运行。
- 本仓库与试用 Release 公开，可把下载链接直接发给测试者。历史私有仓库独立保留，公开提交不包含原作者的私人邮箱。

### iPhone／iPhone Duo

通过 [TestFlight 安装 Beta](https://testflight.apple.com/join/WZDXKgvg)。先在 iPhone 安装 TestFlight，再打开邀请链接；需配合上面的 Mac 主机在同一局域网使用。普通 iPhone 用屏幕按钮切换模式，Duo 可使用背面和弦。测试名额和设备条件以 Apple 页面为准。

也可以自行编译：

1. 安装 Xcode 27.1 或更新及 Go 1.27.1+，先执行 `./scripts/build-tailnet.sh`，再打开 `iPhoneDuoDemo.xcodeproj`（[构建说明](docs/DEVELOPMENT.md)）。
2. 选择 `iPhoneDuoDemo` target，在 Signing & Capabilities 中选择自己的 Team，并使用自己可签名的 Bundle Identifier。
3. USB 连接 Duo、按系统要求开启开发者模式并信任 Mac，选择真机后运行。Xcode 免费个人团队可自测，但需要定期重新签名。

源码安装更新时保持原 Bundle Identifier 和 Team。iOS **1.22.1 / build 28** 已通过外部 TestFlight Beta 审核；这不是正式 App Store 上架。[发行记录](docs/IOS-RELEASE-1.22.md)。

## 怎么用

两端连接同一局域网，首次扫描 Mac 二维码，之后从手机的已配对列表选择电脑。可保存多台 Mac，每次连接一台；IP 变化暂需重新扫码更新地址。

| 操作 | 效果 |
| --- | --- |
| 正面单指操作 | 默认直接触控；长按拖动选字 |
| 背面一指＋正面双指上下滑 | 打开／退出 Mac 窗口总览 |
| 背面一指＋正面双指左／右滑 | 下一个／上一个 Mac 桌面（Spaces） |
| 背面双指长按 | 临时切到正面触控板，松开恢复 |
| 右侧灰色按钮 | 菜单、模式、切屏和键盘，排列在同一列 |

左右切桌面还需在 Mac「设置 → 桌面切换」允许 **System Events 自动化**，并启用系统 Control＋左右方向键；这是独立的可选权限，不影响普通远控。

背面有效区可自由移动和缩放；文字输入支持 iPhone 系统／第三方输入法。普通 iPhone 使用屏幕按钮切换；iPhone 18 Pro／iOS 27.0 模拟器已通过两项针对性 UI 检查，普通 iPhone 真机兼容性仍待首轮验证。

## 后续开发

- [x] **跨网络远控 · 已解决，待发布**：两端内嵌 Tailscale，通过用户自己的私人网络连接，无需额外 App 或自建服务器。当前设备组合的蜂窝画面与触控已获用户确认；新版 Mac Release 与 iOS TestFlight 尚未发布。
- [ ] **P1 后台能耗**：测量无人连接时的采屏、JPEG 编码和保活，按需采集并保持低开销后台可达。
- [ ] **键盘可视性**：探索 Liquid Glass 输入预览，减少远端输入框被键盘遮挡。
- [ ] **RDP／客户端渲染**：验证 Mac 当前会话可行性，对比清晰度、带宽和延迟。
- [ ] **普通 iPhone 真机测试**：验证屏幕按钮、输入法、布局和重连。

已完成内容、剩余测试与发行准备见[公开开发计划](ROADMAP.md)。iOS 下一步优先准备正式 App Store 送审，另一轮 TestFlight 并非必经步骤。

## 当前范围

- iOS **1.22.1 / build 28** 隔离忘记／连接按钮、把背面灯置于桌面上方，并加入有次数限制的相机恢复；闲置后背面失效仍待真机复测。完整手册与默认 iPhone 输入法保留。Mac 保持 **0.18.1 / build 26**。[验证记录](docs/VALIDATION-1.22.1.md)；[真实操作视频录制稿](docs/GUIDE-RECORDING.md)。
- **公开安装包仍为局域网版。**开发中 iOS **1.23.2 / build 31**、Mac **0.19.0 / build 27** 已加入内嵌 Tailscale：局域网免登录，公网使用各自的个人账号，不另装 Tailscale 或系统 VPN。用户已确认当前设备组合的蜂窝跨网画面与触控正常；其他网络与长期测试仍待完成，新版 Mac Release 与 iOS TestFlight 均未发布。[设置与边界](docs/TAILSCALE.md)
- 开发源码默认画质为 **省流 · 15 fps**：最长边 1280 像素、JPEG 65%；保留已有手动选择。这是帧率请求上限，并非固定 Mbps，实际带宽随画面内容变化。
- 开发版 Mac 从一个按钮依次请求首次权限，通过后重启一次并开启内置屏服务；系统授权仍由机主确认。
- 显示模式默认目标 1600×900，使用系统现有安全模式；部分自定义 HiDPI 仍需可选 BetterDisplay 回退。[依赖说明](docs/DEPENDENCIES.md)
- 麦克风默认关闭。当前 Duo → Mac 会议输入需要虚拟音频设备；自研集成驱动尚未实现。[音频说明](docs/REMOTE-MICROPHONE.md)
- 背面实验使用相机辅助 API；相机帧不显示、不保存、不传输，不代表已获得通用外屏接口或上架许可。

[开发与构建](docs/DEVELOPMENT.md) · [开发历史](docs/DEVELOPMENT-HISTORY.md) · [品牌素材](Branding/README.md)

## 许可证

[CC BY-NC-SA 4.0](LICENSE)：署名、非商业性使用、相同方式共享。适用于项目自有代码、文档及素材；第三方依赖保留原许可证。[适用范围](NOTICE.md)。

STLAND 出品

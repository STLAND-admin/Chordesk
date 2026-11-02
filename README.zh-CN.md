<p align="center"><img src="ProjectFiles/Branding/Chordesk-transparent.svg" width="150" alt="Chordesk"></p>

# Chordesk

[English](README.md) · 简体中文

**指间和弦，掌控桌面。**

iPhone 远程桌面客户端与 Mac 主机。拇指负责正面触控和输入，Duo 背屏像和弦一样切换模式；普通 iPhone 使用屏幕按钮。

[官网与演示](https://stland-admin.github.io/Chordesk-site/?lang=zh) · [操作指南](OPERATION-GUIDE.md) · [开发计划](ROADMAP.md)

## 安装

| 平台 | 当前公开版本 |
| --- | --- |
| iPhone / iPhone Duo | [TestFlight 1.30（39）](https://testflight.apple.com/join/WZDXKgvg) |
| Apple Silicon Mac · macOS 15.2+ | [Mac 0.26.0 试用版](https://github.com/STLAND-admin/Chordesk/releases/tag/mac-v0.26.0-test) |

打开 Mac DMG，将 Chordesk 拖进 Applications。当前 Mac 试用包**未公证**，请仅在信任来源时按 macOS「隐私与安全性」提示放行。分别允许屏幕录制、控制 Mac，每项完成后按系统提示重开 App；两项生效后开启服务。[安装说明](docs/MAC-PEER-TEST.txt)。

手机首次扫码绑定，以后点已配对电脑重连。局域网免账号；跨网时在两端 Chordesk 内登录同一 Tailscale 私人网络，无需另装 Tailscale。可记忆多台 Mac。[网络设置与边界](docs/TAILSCALE.md)。

## 操作速查

| 手势 | Mac 操作 |
| --- | --- |
| 正面轻点／长按后拖动 | 点击／选择文字 |
| 背面一指＋正面双指上／下滑 | 打开／退出窗口总览 |
| 背面一指＋正面双指左／右滑 | 下一个／上一个桌面 |
| 背面双指按住 | 临时触控板，抬起恢复 |
| 右侧按钮 | 菜单、模式、显示器、总览与键盘 |

切换桌面需要可选 System Events 权限与 macOS Control＋方向键快捷键。支持原生／第三方 iPhone 输入法。[完整手册](OPERATION-GUIDE.md)。

## 最新进度

**Mac 0.26.0（39）已发布；iOS 1.31（40）正在等待 TestFlight 外部审核。** 默认背面双指接触立即切换；480p–2160p、15–120 fps 和目标码率独立设置；默认 HEVC 并保留回退；限量链路测速与推荐；明显的按钮、逐项权限说明、拖拽安装 DMG；仅认证手机观看时采屏。已明确保存的偏好保留。手机公开邀请在 1.31 获批并启用前仍提供 1.30。独立画质与背面即时触发新默认需要 iOS 1.31；原 1.30 客户端仍可连接新版 Mac。

音频已关闭；不保证合盖／系统睡眠唤醒。支持 IPv4／IPv6 配对，纯 IPv6／NAT64、普通 iPhone 真机与更多网络仍需验证。帧率、码率受硬件与画面影响；HUD RTT 不等于操作到显示的完整延迟。Duo 背屏依赖相机辅助 API，相机帧丢弃。TestFlight 通过不等于正式 App Store 上架。

## 开发与贡献

[工程目录说明](ProjectFiles/README.md)

[开发构建](docs/DEVELOPMENT.md) · [首次安装检查](docs/FIRST-RUN-CHECKLIST.md) · [分发准备](docs/DISTRIBUTION.md) · [文档索引](docs/README.md) · [开发与验证历史](docs/DEVELOPMENT-HISTORY.md)

iOS 从 `ProjectFiles/Chordesk.xcodeproj` 选择自己的 Team 编译；覆盖安装保持原应用身份。概念网站独立维护于 [Chordesk-site](https://github.com/STLAND-admin/Chordesk-site)。

自有代码、文档、品牌适用 **[CC BY-NC-SA 4.0](LICENSE)**，未授予自由商用；第三方依赖保留原许可，见 [NOTICE](NOTICE.md)。[隐私政策](https://stland-admin.github.io/Chordesk-site/privacy.html?lang=zh)。反馈：styj@zju.edu.cn。

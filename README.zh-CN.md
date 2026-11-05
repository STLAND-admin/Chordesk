<p align="center"><img src="ProjectFiles/Branding/Chordesk-transparent.svg" width="150" alt="Chordesk"></p>

# Chordesk

[English](README.md) · 简体中文

**指间和弦，掌控桌面。**

iPhone 远程桌面客户端与 Mac 主机。拇指负责正面触控和输入，Duo 背屏像和弦一样切换模式；普通 iPhone 使用屏幕按钮。

[官网与演示](https://stland-admin.github.io/Chordesk-site/?lang=zh) · [操作指南](docs/user/OPERATION-GUIDE.md) · [开发计划](docs/developer/ROADMAP.md)

## 安装

| 平台 | 当前公开版本 |
| --- | --- |
| iPhone / iPhone Duo | [TestFlight 公开测试](https://testflight.apple.com/join/WZDXKgvg) |
| Apple Silicon Mac · macOS 15.2+ | [Mac 0.28.0 · 已签名公证](https://github.com/STLAND-admin/Chordesk/releases/tag/mac-v0.28.0) |

打开 Mac DMG，将 Chordesk 拖进 Applications。App 和安装包均已 **Developer ID 签名、Apple 公证**。分别允许屏幕录制、控制 Mac，每项完成后按系统提示重开 App；两项生效后开启服务。普通升级请先退出，再替换同一位置的 App。[安装说明](docs/user/MAC-PEER-TEST.txt)。

手机首次扫码绑定，以后点已配对电脑重连。局域网免账号；跨网时在两端 Chordesk 内登录同一 Tailscale 私人网络，无需另装 Tailscale。可记忆多台 Mac。[网络设置与边界](docs/user/TAILSCALE.md)。

## 操作速查

| 手势 | Mac 操作 |
| --- | --- |
| 正面轻点／长按后拖动 | 点击／选择文字 |
| 背面一指＋正面双指上／下滑 | 打开／退出窗口总览 |
| 背面一指＋正面双指左／右滑 | 下一个／上一个桌面 |
| 背面双指按住 | 临时触控板，抬起恢复 |
| 右侧按钮 | 菜单、模式、显示器、总览与键盘 |

切换桌面需要可选 System Events 权限与 macOS Control＋方向键快捷键。支持原生／第三方 iPhone 输入法。[完整手册](docs/user/OPERATION-GUIDE.md)。

## 最新进度

**v1 基线为 Mac 0.28.0（43）、iOS 1.32（46）。** iOS 已通过原 TestFlight 链接开放测试，并于 2026 年 11 月 5 日提交正式 App Store 审核；提交不代表获批或已上架。1.32 加入原生 Liquid Glass 侧栏，改进状态栏避让与明暗背景辨识度。Mac 0.28 自动更新换网后的局域网监听，保留配对与 Tailscale 会话；继续提供签名公证和 Help 内嵌卸载。仅认证手机观看时采屏。[开发与发行历史](docs/developer/DEVELOPMENT-HISTORY.md)。

音频已关闭；不保证合盖／系统睡眠唤醒。支持 IPv4／IPv6 配对，纯 IPv6／NAT64、普通 iPhone 真机与更多网络仍需验证。帧率、码率受硬件与画面影响；HUD RTT 不等于操作到显示的完整延迟。Duo 背屏依赖相机辅助 API，相机帧丢弃。TestFlight 通过不等于正式 App Store 上架。

## 开发与贡献

[`v2` 分支](https://github.com/STLAND-admin/Chordesk/tree/v2)保留 v1 操作方式，评估 RDP／VNC、本地光标、建连与弱网恢复。当前是源码基线及[评估计划](docs/developer/V2-REMOTE-ENGINE-PLAN.md)，尚未发布替代引擎。

[文档索引](docs/README.md)：[用户指南](docs/README.md#users) · [开发者文档](docs/README.md#developers)。

[工程目录](docs/developer/PROJECT-LAYOUT.md) · [开发构建](docs/developer/DEVELOPMENT.md) · [编码规范](docs/developer/AGENTS.md)

iOS 从 `ProjectFiles/Chordesk.xcodeproj` 选择自己的 Team 编译；修改代码前请阅读编码规范，覆盖安装保持原应用身份。概念网站独立维护于 [Chordesk-site](https://github.com/STLAND-admin/Chordesk-site)。

自有代码、文档、品牌适用 **[CC BY-NC-SA 4.0](LICENSE)**，未授予自由商用；第三方依赖保留原许可，见 [NOTICE](NOTICE.md)。[隐私政策](https://stland-admin.github.io/Chordesk-site/privacy.html?lang=zh)。反馈：styj@zju.edu.cn。

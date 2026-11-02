# Chordesk 小范围试用

[操作指南](../OPERATION-GUIDE.md) · [首次安装检查](FIRST-RUN-CHECKLIST.md) · [发行状态](DISTRIBUTION.md)

## 当前入口

| 交付物 | 版本与入口 |
| --- | --- |
| 概念与操作演示 | [中英文官网](https://stland-admin.github.io/Chordesk-site/) |
| iPhone / Duo | [TestFlight 1.30 /39](https://testflight.apple.com/join/WZDXKgvg)，已启用外部测试 |
| Apple Silicon Mac | [0.26.0 /39 试用 Release](https://github.com/STLAND-admin/Chordesk/releases/tag/mac-v0.26.0-test)，macOS 15.2+，ad hoc 签名，未公证 |

**Mac 0.26.0 /39 已发布；iOS 1.31 /40 已提交并正在等待 TestFlight 外部审核**，获批并启用前公开邀请仍提供 1.30。测试报告须记录两端实际版本，不把开发功能当成公开版功能。Mac Developer ID／公证目前暂停；不要求测试者关闭 Gatekeeper，也不分发开发 IPA 代替 TestFlight。

## 安装和十分钟任务

1. Mac：拖入 Applications 后打开；仅在信任来源时按 macOS 隐私与安全性提示允许运行。分别授权屏幕录制、控制 Mac，每项授权后可能需要退出重开。两项生效后开启服务。详见[首次安装检查](FIRST-RUN-CHECKLIST.md)。
2. 手机：安装 TestFlight，打开邀请链接；允许需要的本地网络与相机提示。首次扫描主机二维码，随后从记忆列表重连。
3. 同局域网不需要账号。跨网络在两个 Chordesk 内登录同一私人 Tailscale 网络，不安装额外 Tailscale App；不要把账号或配对二维码发给反馈渠道。
4. 使用可丢弃文稿或测试网页，依次尝试：轻点、滚动、长按拖选、输入文字、收起键盘；Duo 再试背面双指临时触控板，以及一指加正面双指的窗口总览／左右切桌面。普通 iPhone 用屏幕模式按钮，跳过背面手势。
5. 断开、息屏再连、关闭主机窗口后重连。真正睡眠／合盖仍不保证可用。音频功能暂时关闭，勿把它作为会议麦克风测试。

## 1.31 / 0.26 开发版重点

- 新偏好默认背面双指接触即切换、抬起恢复；已有明确保存的长按偏好继续保留。
- 分别修改 480p–2160p、15–120 fps、目标码率，确认互不改写；低分辨率并不保证实际 120 fps。
- 新偏好默认 HEVC，观察 HUD 的实际编码及 H.264/JPEG 回退；已有编码选择继续保留。
- 在当前认证连接执行限量测速，观察推荐，手动应用后确认分辨率不变；弱网／Tailscale 中继需单独记录。
- 服务在线但未连接时应显示“未采集屏幕”；连接后有画面，断开后停止采屏。反复三次，在线查询不能启动采屏。macOS 其他应用可能也在共享屏幕，按应用辨认系统提示。
- 检查两端 Tailscale 按钮、权限旁重启说明，以及 DMG 中 App → Applications 拖拽指引。

## 收集反馈

优先使用 TestFlight 反馈；GitHub issue **公开可见**。截图／录像先检查远程桌面内容。不收集序列号、密码、二维码、密钥或真实私密文档。

```text
体验方式：Duo + Mac / 普通 iPhone + Mac
两端版本与系统：
网络：LAN / Tailscale（Wi-Fi / 蜂窝）：
动作和重现步骤：
预期结果 / 实际结果：
误触、遮挡或主观延迟：
```

网页模拟器、逻辑测试、真机反馈分别记录。正式 App Store 审核、普通 iPhone 真机、全部网络及长期稳定性并未因 Beta 通过而自动验收。

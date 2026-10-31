# Chordesk 1.23 App Store 准备

2026-10-31。用户希望先完成 Mac 首次使用体验，再跳过新一轮 TestFlight，准备正式 App Store 审核。当前仅准备材料；尚未上传新版、保存新版合规声明或提交正式审核。

## 交付与门槛

- iOS 开发版 1.23.2 / build 31，Mac 0.19.0 / 27：用户已确认内嵌 Tailscale 账号绑定及蜂窝画面、触控正常。公开下载仍为旧局域网版本。
- 后续修正版为 iOS 1.23.3 / 32、Mac 0.19.1 / 28，修正手机网络标签及 Mac 权限完整后统一重启；部署状态见 [验证记录](VALIDATION-1.23.md)。
- 本轮先按 [Mac 首次安装检查](MAC-FIRST-RUN-QA.md) 完成真实授权、一次重启、内置屏服务、手机配对。独立本机副本不能替代下载包的 Gatekeeper 验证。
- 审核人员需要下载配套的、含公网功能的 Mac 主机。应准备 Developer ID 签名、公证并装订的安装包和安装说明；本机稳定开发签名保持不变。
- 当前本机未找到 Developer ID Application 身份，只有已有的开发／iOS 发行签名；本轮没有创建该证书、提交公证或发布新版 Mac 包。
- iOS 正式 Archive／IPA、服务端处理、版本资料、设备截图、隐私信息和出口合规须逐项确认。不要把旧 build 28 的 Beta 审核视为新版的正式审核批准。
- 另一轮 TestFlight 是可选步骤；准备完毕可直接选发行构建提交 App Review。[Apple 提交流程](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-app)

## 商店文字草稿（未提交）

名称：**Chordesk**

中文副标题：**指间和弦，掌控 Mac 桌面**

英文副标题：**Play chords. Control your Mac.**

中文简介：

在 iPhone 上触控、输入并操作你的 Mac。Chordesk 支持直接触控与触控板两种方式；iPhone Duo 的背面接触可像按和弦一样切换模式，拇指继续在正面操作。

- 点击、滚动、长按拖选和触控板指针移动。
- 使用 iPhone 系统或已启用的第三方输入法，配合 Ctrl、Option 和 Command 快捷键。
- Duo 背面双指长按临时切换触控板；背面一指配合正面双指滑动控制窗口总览及桌面。
- 同一局域网免登录连接；可选内嵌 Tailscale 公网模式，用自己的私人网络跨网连接，无需另装 Tailscale。
- 普通 iPhone 通过屏幕按钮切换模式。需要运行配套 Chordesk 主机的 Mac，并由机主允许屏幕录制和控制。部分能力受设备和系统限制。

英文简介：

Touch, type and control your Mac from iPhone. Chordesk combines direct touch and trackpad modes. On iPhone Duo, rear contacts switch interaction modes like holding a chord while your thumbs keep working on the front.

- Tap, scroll, hold and drag to select, or move the pointer in trackpad mode.
- Use the iPhone keyboard or an enabled third-party keyboard with Control, Option and Command shortcuts.
- Hold two fingers on Duo's rear surface to temporarily switch to the trackpad. Hold one rear finger and swipe two front fingers for Mission Control or desktop switching.
- Connect on a local network without signing in. Optional embedded Tailscale connects through your private network without installing another Tailscale app.
- Other iPhones use on-screen mode controls. A Mac running the companion Chordesk host is required, with screen-recording and control permissions granted by its owner. Availability depends on the device and operating system.

## 审核备注草稿

The app controls an owner-authorized Mac running the companion Chordesk host. It does not provide an unattended public desktop. Reviewers can use their own test Mac and a disposable TextEdit document. The final submission will include the exact downloadable Mac version and matching setup steps; do not submit with a missing companion download.

LAN mode does not require an account. Start the Mac service, grant macOS screen-recording and control permissions, wait for the host to restart once if needed, then scan its QR code from iPhone. The host pairs using a random secret and TLS. For cross-network testing, sign into the same reviewer-owned Tailscale private network from both apps and approve each app's embedded node. No external Tailscale app or system VPN installation is required; the userspace engine carries only Chordesk's own remote connection. No developer account or private pairing QR code is supplied.

On iPhone Duo, the optional rear interaction experiment uses CameraCaptureAccessory while a camera capture session is active. This is a non-photography interaction use case: camera frames are discarded, not displayed, stored or transmitted. It should be disclosed for review, not described as a general rear-display API. On other iPhones, use the on-screen mode switch. Optional microphone forwarding is off by default and requires a user-selected virtual audio destination on the Mac.

System Events automation is a separate optional Mac permission for switching Spaces. Basic remote control does not require it. Lock screen security is not bypassed; the Mac must remain running and reachable.

## 隐私与加密待核对

公开隐私页当前仍明确适用于局域网 build 28，需补充新版的可选 Tailscale：账号／节点／网络元数据、第三方处理、节点状态的 Keychain 保存、退出账号、桌面端到端加密及 SDK 日志上传关闭。同步 App Store Connect 数据类型；不能继续用“没有第三方账号／中继”的旧版描述。

新版包含 tsnet／WireGuard／Go 的加密实现，不能继续申报“仅使用 Apple 系统加密”。应依据实际依赖与拟分发地区重新回答 Apple 问卷；如需法国材料或其他文件，先准备并由用户确认，不代替作出合规声明。[Apple 加密说明](https://developer.apple.com/help/app-store-connect/reference/app-information/export-compliance-documentation-for-encryption)

正式提交前记录：构建版本与校验值、Mac 首装结果、配套下载地址、普通机型验证范围、截图、审核备注、隐私与加密回答、App Store Connect 最终状态。联系人沿用此前用户授权的后台记录，不复制到公开仓库。

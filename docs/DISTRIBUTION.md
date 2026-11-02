# Chordesk 分发准备

## 当前状态 · 2026-11-02

- **公开 TestFlight：iOS 1.30 /39** 已通过 Beta Review，并经用户批准启用外部测试、通知测试员。[原邀请链接](https://testflight.apple.com/join/WZDXKgvg)保持不变。
- **公开 Mac：0.26.0 /39**，Apple Silicon、macOS 15.2+ 的未公证 ad hoc 测试 DMG；[GitHub Release](https://github.com/STLAND-admin/Chordesk/releases/tag/mac-v0.26.0-test)。接收者按系统提示为这一个 App 放行，不需要 Xcode；不关闭 Gatekeeper/SIP，不绕过受管理设备策略。
- **iOS 1.31 /40：正在等待 TestFlight 外部审核**；已关联原三个组，自动通知关闭，公开邀请暂仍提供 1.30。Mac 0.26 已公开；独立画质控制与即时背面触发新默认需搭配 iOS 1.31。历史验证统一见 [开发与验证历史](DEVELOPMENT-HISTORY.md)。
- 正式 App Store 尚未提交。此前草稿保留，用户手动最终提交；仅美港发行的建议不代表已更改后台供应地区。大陆备案接入方式仍待主管部门／接入商确认。
- Mac Developer ID／公证按用户要求暂停，不能把开发签名或 ad hoc 包称为公证包。

TestFlight 不是正式 App Store 的必经步骤。[Apple 提交流程](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-app)。正式送审仍需完整元数据、截图、隐私标签、真实相机外屏用途与内嵌网络说明。内嵌 WireGuard／Go 使用外部标准加密，不能沿用旧版“仅系统加密”分类。Beta 通过不代表正式审核或各地区资质要求自动通过。

## 安装与试用

Mac：打开 DMG → 将 Chordesk 拖进 Applications → 从应用程序打开 → 允许屏幕录制并按提示重开 → 允许控制 Mac 并按提示重开 → 两项生效后开启服务。

iPhone：安装 TestFlight → 打开邀请 → 安装／更新并核对版本。源码版本从 Xcode 用自己的 Team 签名；覆盖安装保持原 Bundle ID 和 Team。公网在两端 App 内登录用户自己的同一 Tailscale 私人网络。测试清单见 [BETA-TESTING.md](BETA-TESTING.md)，安装细节见 [MAC-PEER-TEST.txt](MAC-PEER-TEST.txt)。

## 当前验证范围与后续机型

本轮按用户要求同时准备 **Duo 手势体验**与 **iPhone 兼容性测试**两个外部组。普通 iPhone 使用右侧按钮／菜单切换直接触控和触控板，不使用背面手势；这属于首轮兼容性测试，不是全机型兼容承诺。

2026-10-30 在 iPhone 18 Pro／iOS 27.0 模拟器通过“短按切换／隐藏模式按钮”和“忘记 Mac 不连接、仅删除确认记录”两项 UI 测试，使用合成画面与配对数据。未完成普通 iPhone 真机连接、输入、旋转和长期测试，不能把模拟器通过扩展为这些路径已验证。

按用户 2026-10-31 要求，官网发布现有公开邀请；加入同一构建后，按实际设备测试 Duo 背面和弦或普通 iPhone 屏幕按钮。未另行发送邮件邀请。[TestFlight](https://developer.apple.com/testflight/)允许公开链接按设备类型和 OS 设置测试者条件，但尚未确认 Duo 单独筛选条件；测试组名称不是安装机型限制。

截至 2026-10-29，本次查阅[公开设备能力限制](https://developer.apple.com/support/required-device-capabilities/)未确认可用于“仅 Duo”的 capability。不能编造 `UIRequiredDeviceCapabilities` 键，也不能拿无关硬件条件排除其他 iPhone。仅设 iPhone family 不能区分 Duo 与其他 iPhone。

正式公开发行前，继续补足可下载机型的适配／验证。不能以“主要为 Duo 设计”替代[Apple 对可下载设备的兼容要求](https://developer.apple.com/help/app-review/before-submitting-for-review/test-compatible-devices)。当前 IPA 声明 iPhone／iPad family；本轮测试范围不等于已验证全部可下载设备。

其他 Duo／iPhone 用户属于外部测试者，首个外部 TestFlight 构建需要 Beta App Review，通过后才能向这些测试者分发；不必先上架 App Store。少量指定设备也可用 [Ad Hoc](https://developer.apple.com/help/account/provisioning-profiles/create-an-ad-hoc-provisioning-profile/) 分发，但需预先登记设备并重新签名，不是可任意安装的 IPA。现有公开试用采用 TestFlight，不授予测试者 App Store Connect 管理权限；新版发行方向见上文。

## iOS → App Store Connect

1. Apple Developer Program 激活并能进入 App Store Connect；个人开发签名安装成功不等于已可分发 TestFlight。
2. 注册 App 记录、确定最终 bundle ID。当前开发 ID 继续用于本机更新，换 ID 会成为另一个 App，需迁移／重新配对。
3. 准备图标、Duo 截图、隐私政策与数据收集说明、相机与本地网络用途说明、测试账号或可复现的 Mac 连接步骤。
4. Archive、导出／验证并上传 App Store Connect；可直接准备 App Store 提交，也可先内部 TestFlight 测试，再提交外部测试审核。TestFlight 不是 App Store 的前置要求。说明相机辅助场景的具体用途，不将其称为通用外屏接口，也不预判审核结论。
5. 测试说明包含局域网依赖、Mac 权限、二维码凭据管理、退后台断连，以及真实支持的手势和画质边界。

## macOS → 安装包

开发期沿用稳定 Apple Development 身份，实际安装包为 `~/Applications/Chordesk.app`，旧 DuoWorkbench 路径只保留兼容链接。正式面向其他用户的包另用 Developer ID Application 签名、Hardened Runtime 与公证，公证完成后装订票据，再打包 DMG；需要真正安装器时使用 Developer ID Installer 签名 PKG。

在干净 Mac 测试首次启动、屏幕录制／辅助功能申请、配对、断线释放和卸载流程。不要把本机开发证书、钥匙串、配对密钥或已有系统授权打进安装包。正式签名／ID 迁移需计划重新授权，不许悄悄退回 ad hoc。

GitHub Releases 可承载 Mac 包和版本说明；不能替代 iOS TestFlight／App Store 签名分发。当前源码仓库和 Mac 0.26.0 试用 Release 已公开，试用包仍为未公证的 ad hoc 签名；正式签名公证包、App Store 发行及自动发行流水线尚未完成。

## 公网与扩容

按 [PUBLIC-NETWORK-PLAN.md](../PUBLIC-NETWORK-PLAN.md) 分阶段实施。当前已内嵌 Tailscale，使用用户各自的私人网络，不暴露任意公网监听；开发者自建账号、信令和中继服务仍为后续路线。不能用设备名称或公网 IP 代替认证。

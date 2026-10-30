# Chordesk 分发准备

## 试用交付

2026-10-30 用户确认 Apple Developer Program 已通过。iOS 1.22 的本地 Release Archive 已生成，发行导出及审核状态见 [1.22 发行准备](IOS-RELEASE-1.22.md)。小范围试用执行清单、十分钟任务与反馈模板见 [BETA-TESTING.md](BETA-TESTING.md)；BetterDisplay 与虚拟音频依赖见 [DEPENDENCIES.md](DEPENDENCIES.md)。尚未上传 TestFlight 或提交 App Store；Mac 正式 Developer ID 公证包也未生成。

2026-10-29 用户另行明确授权生成无付费会员的同学试用包：`scripts/package-macos-test.sh` 独立生成 Apple Silicon Release、本地 ad hoc 签名、未公证 DMG。接收者手动为该 App 放行并授予屏幕录制／辅助功能，不需要 Xcode；受管理的 Mac 可能禁止。具体说明见 [Mac 同学试用说明](MAC-PEER-TEST.txt)。此流程不修改本机稳定开发包，也不等于 Developer ID、公证或 TestFlight 分发。

## 当前验证范围与后续机型

当前仅为 Duo 开发和测试，开发签名安装到已登记 Duo。没有背面场景时保留菜单切换作为降级路径，不宣称非 Duo 兼容。

2026-10-30 已将非 Duo iPhone 的按钮／菜单操作和布局验证纳入[后续开发计划](../ROADMAP.md)。完成实际测试后再扩大兼容声明和招募范围；本轮没有新增设备测试或改变分发方式。

TestFlight 初期采用定向邀请，招募时确认 Duo 设备；不开放无条件公开链接。[TestFlight](https://developer.apple.com/testflight/)允许公开链接按设备类型和 OS 设置测试者条件，但具体是否提供 Duo 单独条件，要在已激活的 App Store Connect 中核对；邀请本身不是只能在某一个型号安装的保证。

截至 2026-10-29，本次查阅[公开设备能力限制](https://developer.apple.com/support/required-device-capabilities/)未确认可用于“仅 Duo”的 capability。不能编造 `UIRequiredDeviceCapabilities` 键，也不能拿无关硬件条件排除其他 iPhone。仅设 iPhone family 不能区分 Duo 与其他 iPhone。

公开发布门槛：先确认官方是否允许声明必需的背面交互能力；若没有硬限制，继续 Duo 封闭测试，或在公开发行前补足可下载机型的适配／验证。不能以“我们只测 Duo”替代[Apple 对可下载设备的兼容要求](https://developer.apple.com/help/app-review/before-submitting-for-review/test-compatible-devices)。

## iOS → App Store Connect

1. Apple Developer Program 激活并能进入 App Store Connect；个人开发签名安装成功不等于已可分发 TestFlight。
2. 注册 App 记录、确定最终 bundle ID。当前开发 ID 继续用于本机更新，换 ID 会成为另一个 App，需迁移／重新配对。
3. 准备图标、Duo 截图、隐私政策与数据收集说明、相机与本地网络用途说明、测试账号或可复现的 Mac 连接步骤。
4. Archive、导出／验证并上传 App Store Connect；可直接准备 App Store 提交，也可先内部 TestFlight 测试，再提交外部测试审核。TestFlight 不是 App Store 的前置要求。说明相机辅助场景的具体用途，不将其称为通用外屏接口，也不预判审核结论。
5. 测试说明包含局域网依赖、Mac 权限、二维码凭据管理、退后台断连，以及真实支持的手势和画质边界。

## macOS → 安装包

开发期沿用稳定 Apple Development 身份和 `~/Applications/DuoWorkbench.app`，显示名称 Chordesk。正式面向其他用户的包另用 Developer ID Application 签名、Hardened Runtime 与公证，公证完成后装订票据，再打包 DMG；需要真正安装器时使用 Developer ID Installer 签名 PKG。

在干净 Mac 测试首次启动、屏幕录制／辅助功能申请、配对、断线释放和卸载流程。不要把本机开发证书、钥匙串、配对密钥或已有系统授权打进安装包。正式签名／ID 迁移需计划重新授权，不许悄悄退回 ad hoc。

GitHub Releases 可承载 Mac 包和版本说明；不能替代 iOS TestFlight／App Store 签名分发。当前源码仓库和 Mac 试用 Release 已公开，试用包仍为未公证的 ad hoc 签名；正式签名公证包、App Store／TestFlight 上传及自动发行流水线尚未完成。

## 公网与扩容

按 [PUBLIC-NETWORK-PLAN.md](../PUBLIC-NETWORK-PLAN.md) 分阶段实施。当前只有规划，不开放公网监听；注册账号／设备认证、信令、直连与中继分别设计，不能用设备名称或公网 IP 代替认证。

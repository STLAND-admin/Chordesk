# Chordesk iOS 1.22 · 发行准备

2026-10-30；iOS 1.22 / build 27，配套 Mac 0.18.1 / build 26。

## 分发路线

Apple Developer Program 已通过。可以直接准备 App Store 提交，**TestFlight 不是前置要求**；也可先用 TestFlight 收集小范围反馈。两者均经过 App Store Connect，但外部 TestFlight 和 App Store 是各自的审核流程。[Apple 分发说明](https://help.apple.com/xcode/mac/current/en.lproj/dev442d7f2ca.html)

本次只准备本地发行产物，不上传构建、不提交审核、不邀请测试者。App Store 导出的 IPA 不能像 Mac DMG 一样直接发给朋友安装。

## 当前产物与阻塞

- Release Archive 构建成功，版本、bundle ID 与内含隐私清单已核对，严格签名校验通过。
- 已在用户明确授权后创建 Apple Distribution 证书；不导出或提交证书私钥。
- 本地路径：`release-artifacts/ios-1.22-build27/Chordesk.xcarchive`。产物、签名日志和配置文件被 Git 忽略。
- IPA 导出尚未完成：命令行报告 `No Accounts`／缺少 App Store profile，Organizer 仍把归档团队识别为历史 Personal Team。需要在 Developer 账户核对团队和 App Store 配置文件后继续，不修改 bundle ID、不假称已上传。

可复用脚本为 `scripts/archive-ios-release.sh` 和 `scripts/export-ios-release.sh`。导出固定使用 `destination=export`；账户侧自动配置仅在明确设置 `CHORDESK_ALLOW_PROVISIONING_UPDATES=1` 时允许。

## 上传／提交前待办

- [ ] App Store Connect 创建或核对 Chordesk App 记录，使用现有 `dev.iphoneduo.remotedemo`；确认 Team、版本及构建号。
- [ ] 完成发行导出与验证，再单独上传；不要选择仅限 TestFlight 内部测试的构建方式，否则不能用于 App Store 提交。
- [ ] 准备真实 App 截图、支持 URL、隐私政策 URL、年龄分级、产品描述和审核联系方式。概念网页的 3D 不能冒充 App 实际截图；尚未提供的演示视频不填假链接。
- [ ] 核对 App Privacy 和加密出口合规问卷。当前使用系统 TLS 的局域网配对，未替账户填写法律声明；`PrivacyInfo.xcprivacy` 不替代问卷或隐私政策。
- [ ] 提供 Mac 主机下载、同网连接／扫码步骤、必要设备要求，以及可复现的测试流程。没有云账号登录；不要公开真实配对密钥或私人桌面。
- [ ] 明确披露 `CameraCaptureAccessory` 实验：为背面交互保持相机采集活动，帧立即丢弃，不显示、保存或传输。该接口面向相机辅助场景，此用途的审核可接受性未确认，不能用“公开 API”推断自动合规。[审核指南](https://developer.apple.com/app-store/review/guidelines/)
- [ ] 完成 1.22 真机回归：自动唤起、中文输入、菜单与后背隔离、0/1/2/3+ 接触灯、旋转和中断。已有偏好保留，测试新默认值时使用新安装或明确恢复偏好。
- [ ] 对可下载机型核实适配范围；目前没有确认“仅 Duo”的公开分发限制键，非 Duo 尚未完成测试。

## 审核备注草稿

Chordesk is a local-network remote desktop client for its companion Mac host. Install the linked Mac test build, grant screen recording and control permissions, start the service, then scan its pairing QR code from Chordesk on the same network. No cloud account is required. Touch and trackpad controls, keyboard entry, display selection and an in-app Duo operation manual are available from the right-side controls.

On Duo, an experimental rear interaction mode uses CameraCaptureAccessory while a foreground camera capture session remains active. Camera frames are immediately discarded; they are not displayed, recorded or transmitted. The rear surface only changes front interaction modes and qualifies front gestures. The app does not claim a general-purpose rear-screen API. Microphone forwarding is optional, off by default, and requires a separately configured virtual audio device on the Mac.

填写最终主机链接、支持／隐私地址和联系信息后再提交本草稿；不包含任何私人二维码。

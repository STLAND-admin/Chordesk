# Chordesk iOS 1.22 · 发行准备

## 2026-10-30 更新：1.22.1 / build 28 TestFlight 候选

- 已用现有正式发行证书和同一 Bundle ID / Team 归档、导出 **1.22.1 / build 28**。本节取代下文旧 build 27 的产物选择；不改变已部署的开发签名版本。
- Archive：`release-artifacts/ios-1.22.1-build28/Chordesk.xcarchive`。
- IPA：`release-artifacts/ios-1.22.1-build28/AppStoreExport/iPhoneDuoDemo.ipa`，2,369,324 字节；SHA-256：`220779ce9fa38ce19cafad4b1222f367879e26bf9b914ecb4457c8be953f8ffb`。
- 干净解包副本的 `codesign --verify --deep --strict` 通过。正式 profile：`Chordesk App Store 2026`；`get-task-allow=false`、`beta-reports-active=true`、无设备名单，版本、iOS 27.1 SDK、隐私清单均已核对。工作目录解包副本受 Finder 扩展属性污染时不能误判为原 IPA 无效；原 ZIP 无 `__MACOSX` 项，独立临时目录重新解包验证通过。
- 用户已指定 TestFlight 反馈邮箱，已在 App Store Connect 与中文 Beta 描述、英文审核备注、官网／隐私政策链接一起保存；不将该邮箱写入公开 Git 历史。审核联系姓名／电话尚待在 Apple 后台补齐。
- [真实演示视频](https://stland-admin.github.io/Chordesk-site/?lang=en#demo)已发布，展示手机和 Mac 的实际操作。视频无声，保留完整启动／配对过程；不能将其视为背面长期闲置恢复的完整回归结果。
- 当前为**本地候选包与审核材料准备**，尚未上传 build 28、提交 TestFlight Beta App Review 或邀请测试者。已创建并核对 [Chordesk App Store Connect 记录](https://appstoreconnect.apple.com/apps/6828753865/distribution/info)（Apple ID `6828753865`，主要语言简体中文，SKU `chordesk-ios`），使用原 Bundle ID。

### 本轮测试重点（可用于 What to Test）

1. 首次扫码与记住多台 Mac；“忘记”取消不连接，确认只删除所选记录。
2. 直接触控：轻点、滚动、长按拖选与抬手释放；长按后不移动为右键。
3. iPhone 输入法：自动唤出、中文确认与退格、长按空格移动光标、Ctrl / Option / Cmd。
4. 背面一指＋正面双指：上下滑窗口总览、左右滑切换桌面；Mac 桌面切换需 System Events 授权和对应系统快捷键。
5. 背面双指长按：临时触控板；松开恢复直接触控，轻点应仍为左键。
6. 闲置、操作 Mac、输入／菜单、前后台及旋转后，重新落指能否恢复背面接触灯；此项仍需重点验证。

### TestFlight 文案草稿

**Beta App Description (English)**

Chordesk brings your Mac desktop to your iPhone over a local network. Touch, scroll, select, and type with the iPhone keyboard. On iPhone Duo, simple holds on the rear surface change the meaning of front gestures, like playing a chord: one rear finger qualifies window and desktop gestures; holding two rear fingers temporarily turns the front into a trackpad. A companion Apple Silicon Mac running macOS 15.2 or later is required. This beta focuses on Duo; other iPhones have not yet been validated. Internet access is not included.

**What to Test (English)**

Test QR pairing and saved-Mac reconnect, forgetting a Mac without connecting, direct-touch selection and release, Chinese text entry and keyboard cursor movement, and rear 0/1/2-finger gestures. Please especially test whether rear contacts recover after idle time, keyboard or menu use, rotation, and returning to the foreground. Report the iOS/Mac versions and the exact gesture combination. Do not attach private desktop content or pairing credentials to public feedback.

**Reviewer setup and disclosure**

Use the [Mac 0.18.1 Apple Silicon host](https://github.com/STLAND-admin/Chordesk/releases/tag/mac-v0.18.1-test). This host is a test build and is not notarized. The [installation instructions](https://github.com/STLAND-admin/Chordesk/blob/main/docs/MAC-PEER-TEST.txt) explain its setup. Put the Mac and iPhone on the same local network. On Mac, click “开始服务” and complete screen recording and control permission setup, then scan its current QR code from the iPhone. No cloud account or reviewer login is required. Use a disposable TextEdit document to test text entry and selection. The right-side menu contains the complete Duo operation manual and diagnostics. A right-side interaction-mode button offers a manual alternative to rear gestures.

The optional experimental Duo rear interface uses the public CameraCaptureAccessory API while a foreground camera capture session remains active. Camera frames are immediately discarded: no preview, recording, or camera-frame transmission. The rear interface is used to qualify gestures and switch the front interaction mode, rather than for photographic controls. This intended-use distinction must be disclosed to App Review; public API availability does not establish that Apple will accept this use. The camera also scans pairing QR codes. Optional microphone forwarding is off by default and requires a separately configured virtual audio input device on the Mac; basic remote control does not require that driver.

### Remaining submission gates

- Confirm the Chordesk App Store Connect record and upload the build; wait for Apple processing and resolve server-side validation findings.
- Beta description, feedback email and reviewer notes have been saved. Complete reviewer contact name / phone, then review the [privacy policy](https://stland-admin.github.io/Chordesk-site/privacy.html?lang=en), [support page](https://stland-admin.github.io/Chordesk-site/support.html?lang=en) and App Privacy questionnaire before submission.
- Complete export compliance based on the actual implementation: Apple Network/Security TLS and authentication, no custom encryption implementation. Using system encryption still requires an export-compliance determination; do not mark “no encryption” simply because TLS comes from Apple.
- For external testing, create the internal test group first, then prepare an external group and submit its first build for Beta App Review. Do not automatically invite testers or publish a public invitation link during preparation.
- Verify the intended Duo device / OS combination and the hardware recovery cases above. Do not claim non-Duo testing or approval has already happened.

Sources: [Test information](https://developer.apple.com/help/app-store-connect/test-a-beta-version/provide-test-information/), [external testing](https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers), [export compliance](https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance/), [App Privacy](https://developer.apple.com/app-store/app-privacy-details/).

---

2026-10-30；iOS 1.22 / build 27，配套 Mac 0.18.1 / build 26。

## 分发路线

Apple Developer Program 已通过。可以直接准备 App Store 提交，**TestFlight 不是前置要求**；也可先用 TestFlight 收集小范围反馈。两者均经过 App Store Connect，但外部 TestFlight 和 App Store 是各自的审核流程。[Apple 分发说明](https://help.apple.com/xcode/mac/current/en.lproj/dev442d7f2ca.html)

本次只准备本地发行产物，不上传构建、不提交审核、不邀请测试者。App Store 导出的 IPA 不能像 Mac DMG 一样直接发给朋友安装。

## 当前产物

- Release Archive 构建成功，版本、bundle ID 与内含隐私清单已核对，严格签名校验通过。
- 已在用户明确授权后创建 Apple Distribution 证书；不导出或提交证书私钥。
- 本地路径：`release-artifacts/ios-1.22-build27/Chordesk.xcarchive`。产物、签名日志和配置文件被 Git 忽略。
- **App Store IPA 已导出**：`release-artifacts/ios-1.22-build27/AppStoreExport/iPhoneDuoDemo.ipa`，2,326,381 字节。SHA-256：`5220645cb22e70dad53310aa673bb4aabe44c77283c8902dcd849320d8eaf836`；同目录提供 `SHA256SUMS.txt`。
- 经 Edge 已登录账户确认原 Team 会员有效，为原 App ID 生成 `Chordesk App Store 2026` profile，使用现有 Apple Distribution 证书手动导出成功。此前 `No Accounts` 和 Personal Team 提示属于本次自动签名／旧配置识别路径的问题，不代表会员未生效；未修改 Bundle ID 或撤销旧证书。
- IPA 解包后严格签名检查通过；版本 1.22 / 27、正式 App Store profile、`get-task-allow=false`、无设备名单和隐私清单均已核对。尚未经过 App Store Connect 服务端验证、上传或审核。
- Duo 已覆盖安装 **开发签名**版本并查询确认为 1.22 / 27。自动启动被系统 `Locked` 拒绝，等待用户解锁后交互复测；发行 IPA 与本次 USB 开发安装分开。

可复用脚本为 `scripts/archive-ios-release.sh` 和 `scripts/export-ios-release.sh`。导出固定使用 `destination=export`；设置 `CHORDESK_DISTRIBUTION_PROFILE` 可选择已安装的 profile 进行手动签名，`CHORDESK_DISTRIBUTION_CERTIFICATE` 可指定证书 SHA-1（不含私钥）。账户侧自动配置仅在明确设置 `CHORDESK_ALLOW_PROVISIONING_UPDATES=1` 时允许。

## 上传／提交前待办

- [ ] App Store Connect 创建或核对 Chordesk App 记录，使用现有 `dev.iphoneduo.remotedemo`；确认 Team、版本及构建号。
- [x] 完成本地 App Store 发行 IPA 导出与签名／profile 校验。
- [ ] App Store Connect 服务端验证与单独上传；不要选择仅限 TestFlight 内部测试的构建方式，否则不能用于 App Store 提交。
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

# Chordesk iOS 1.22 · 发行准备

## 2026-10-31：Beta 已批准，公开邀请已可用

- App Store Connect 核对 **1.22.1 / build 28 已批准**。用户提供并要求发布的邀请为 [加入 Chordesk TestFlight](https://testflight.apple.com/join/WZDXKgvg)，对应 `iPhone 兼容性测试` 外部组；本次查看时公开链接已启用、上限 100、测试员 0，没有另加邮箱或修改人数上限。
- 初次访问公开页仍提示不接受新测试者；在该组已批准构建处执行“通知测试员”启用后，重新读取公开页已出现 **View Chordesk Beta / View in TestFlight** 与 App 测试说明。核验的是公开邀请入口，不是新设备安装或硬件测试。
- 官网中英文首页、双语 README 与试用说明同步此入口。测试者安装 TestFlight 后打开链接；需使用配套 Mac 主机、同一可互访局域网。设备条件、剩余名额及构建有效期以 Apple 页面为准。
- 普通 iPhone 使用屏幕按钮，Duo 可使用背面和弦；公开 Beta 不等于全部机型已验证，也不是正式 App Store 上架或获得通用背屏 API。
- 本轮未上传新构建、未提交正式 App Store 版本、未部署公网或改 App 采集行为。开发计划新增 P0 跨网络远控和 P1 后台耗能优化，见 [ROADMAP](../ROADMAP.md)。

以下保留首次送审过程，历史“等待审核／无公开链接”状态由本节取代。

## 2026-10-30 18:51（北京时间）：1.22.1 / build 28 正在等待审核

- 用户本轮明确授权推进 **外部 TestFlight Beta App Review**，覆盖历史“仅本地导出、不上传／提交”的范围限制；没有提交正式 App Store 发行。
- Xcode 于 18:39 返回 `Upload succeeded`／`EXPORT SUCCEEDED`。Apple 处理后显示 build 28；用户确认系统加密分类后，出口合规问卷已保存，缺少合规证明提示消失。
- 已保存 Beta 描述、反馈邮箱、审核联系人、英文审核备注、中英文测试重点、官网／隐私地址及真实演示视频。审核联系人按用户明确授权沿用其另一 App 的联系人，仅保存在 Apple 后台，不复制到公开仓库。
- 已创建 `Chordesk 内部验证`、`Duo 手势体验`、`iPhone 兼容性测试` 三个组，并关联同一个 build 28。内部组关闭自动分发；送审时取消自动通知测试员。三个组均未邀请测试员，也未创建公开邀请链接。
- 已点击“提交以供审核”，随后构建列表明确显示 **正在等待审核**，详情页出现“从审核中移除”。这表示已送审，**不表示审核通过或已可供外部安装**。
- App Store Connect：[构建与审核状态](https://appstoreconnect.apple.com/apps/6828753865/testflight/ios)（需 App 所有者登录）。首次外部测试审核通过后再按设备分组定向邀请；普通 iPhone 无需背屏，可用屏幕按钮切换。

### 本轮普通 iPhone 验证

- iPhone 18 Pro／iOS 27.0 模拟器，两项针对性 UI 测试通过：`testPointerButtonSwitchesWithShortTapAndCanBeHidden`、`testForgetMacDoesNotConnectAndOnlyDeletesConfirmedHost`。
- 使用 DEBUG 合成画面和配对 fixture，不能视为真实远控链路、普通 iPhone 硬件或全部系统版本已验证。普通 iPhone 真机兼容性、Duo 长时间闲置后的背面恢复继续列为测试重点。
- 结果：`/private/tmp/Chordesk-iPhone-TF-Check.xcresult`；上传日志：`release-artifacts/ios-1.22.1-build28/upload-2026-10-30.log`。日志、IPA 与签名材料均不提交公开 Git。

### 已上传产物

- 已用现有正式发行证书和同一 Bundle ID / Team 归档、导出 **1.22.1 / build 28**。本节取代下文旧 build 27 的产物选择；不改变已部署的开发签名版本。
- Archive：`release-artifacts/ios-1.22.1-build28/Chordesk.xcarchive`。
- IPA：`release-artifacts/ios-1.22.1-build28/AppStoreExport/iPhoneDuoDemo.ipa`，2,369,324 字节；SHA-256：`220779ce9fa38ce19cafad4b1222f367879e26bf9b914ecb4457c8be953f8ffb`。
- 干净解包副本的 `codesign --verify --deep --strict` 通过。正式 profile：`Chordesk App Store 2026`；`get-task-allow=false`、`beta-reports-active=true`、无设备名单，版本、iOS 27.1 SDK、隐私清单均已核对。工作目录解包副本受 Finder 扩展属性污染时不能误判为原 IPA 无效；原 ZIP 无 `__MACOSX` 项，独立临时目录重新解包验证通过。
- 用户指定的 TestFlight 反馈邮箱已在 App Store Connect 保存；审核联系姓名／电话／邮箱本轮也已补齐，不将这些字段写入公开 Git 历史。
- [真实演示视频](https://stland-admin.github.io/Chordesk-site/?lang=en#demo)已发布，展示手机和 Mac 的实际操作。视频无声，保留完整启动／配对过程；不能将其视为背面长期闲置恢复的完整回归结果。
- 已创建并核对 [Chordesk App Store Connect 记录](https://appstoreconnect.apple.com/apps/6828753865/distribution/info)（Apple ID `6828753865`，主要语言简体中文，SKU `chordesk-ios`），使用原 Bundle ID；当前提交状态以上方实时核对记录为准。

### 本轮测试重点（可用于 What to Test）

1. 首次扫码与记住多台 Mac；“忘记”取消不连接，确认只删除所选记录。
2. 直接触控：轻点、滚动、长按拖选与抬手释放；长按后不移动为右键。
3. iPhone 输入法：自动唤出、中文确认与退格、长按空格移动光标、Ctrl / Option / Cmd。
4. 背面一指＋正面双指：上下滑窗口总览、左右滑切换桌面；Mac 桌面切换需 System Events 授权和对应系统快捷键。
5. 背面双指长按：临时触控板；松开恢复直接触控，轻点应仍为左键。
6. 闲置、操作 Mac、输入／菜单、前后台及旋转后，重新落指能否恢复背面接触灯；此项仍需重点验证。

### TestFlight 文案草稿

**Beta App Description (English)**

Chordesk brings your Mac desktop to your iPhone over a local network. Touch, scroll, select, and type with the iPhone keyboard. On iPhone Duo, simple holds on the rear surface change the meaning of front gestures, like playing a chord: one rear finger qualifies window and desktop gestures; holding two rear fingers temporarily turns the front into a trackpad. A companion Apple Silicon Mac running macOS 15.2 or later is required. This beta includes Duo gesture testing and initial regular-iPhone hardware compatibility testing using the on-screen mode switch. Internet access is not included.

**What to Test (English)**

Test QR pairing and saved-Mac reconnect, forgetting a Mac without connecting, direct-touch selection and release, Chinese text entry and keyboard cursor movement, and rear 0/1/2-finger gestures. Please especially test whether rear contacts recover after idle time, keyboard or menu use, rotation, and returning to the foreground. Report the iOS/Mac versions and the exact gesture combination. Do not attach private desktop content or pairing credentials to public feedback.

**Reviewer setup and disclosure**

Use the [Mac 0.18.1 Apple Silicon host](https://github.com/STLAND-admin/Chordesk/releases/tag/mac-v0.18.1-test). This host is a test build and is not notarized. The [installation instructions](https://github.com/STLAND-admin/Chordesk/blob/main/docs/MAC-PEER-TEST.txt) explain its setup. Put the Mac and iPhone on the same local network. On Mac, click “开始服务” and complete screen recording and control permission setup, then scan its current QR code from the iPhone. No cloud account or reviewer login is required. Use a disposable TextEdit document to test text entry and selection. The right-side menu contains the complete Duo operation manual and diagnostics. A right-side interaction-mode button offers a manual alternative to rear gestures.

The optional experimental Duo rear interface uses the public CameraCaptureAccessory API while a foreground camera capture session remains active. Camera frames are immediately discarded: no preview, recording, or camera-frame transmission. The rear interface is used to qualify gestures and switch the front interaction mode, rather than for photographic controls. This intended-use distinction must be disclosed to App Review; public API availability does not establish that Apple will accept this use. The camera also scans pairing QR codes. Optional microphone forwarding is off by default and requires a separately configured virtual audio input device on the Mac; basic remote control does not require that driver.

### 送审时的后续清单（历史；当前状态见页首）

- Wait for Apple's Beta App Review decision and respond to any request for setup details or changes. The optional CameraCaptureAccessory use is explicitly disclosed; do not assume approval merely because the API is public.
- After approval, invite the user's selected testers to the appropriate external group. No public TestFlight link exists yet; do not substitute an App Store distribution IPA as a directly installable download.
- Export classification was saved with the user's confirmation based on Apple Network/Security TLS and no custom encryption implementation. Reassess if encryption changes; this is not a statement that the app uses no encryption.
- Continue the hardware cases above. The two regular-iPhone simulator checks do not establish physical-device compatibility or long-idle rear recovery.
- Formal App Store distribution remains separate and unsubmitted; screenshots, App Privacy, age rating and other store metadata still need completion for that route.

Sources: [Test information](https://developer.apple.com/help/app-store-connect/test-a-beta-version/provide-test-information/), [external testing](https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers), [export compliance](https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance/), [App Privacy](https://developer.apple.com/app-store/app-privacy-details/).

---

以下为历史准备记录，已被上方 build 28 送审状态取代。2026-10-30；iOS 1.22 / build 27，配套 Mac 0.18.1 / build 26。

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

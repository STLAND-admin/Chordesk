# Chordesk 小范围试用

目标：先找 5–10 位 Duo 用户验证背面和弦是否容易学会、是否误触，以及触控／触控板切换是否自然；同时用独立普通 iPhone 测试组开展手动切换与真机兼容性测试。网页、模拟器与真机反馈分开记录，不能用网页结果证明握持舒适或实际延迟。

## 三个交付物

| 交付物 | 试用入口 | 当前状态 |
| --- | --- | --- |
| 概念与操作演示 | https://stland-admin.github.io/Chordesk-site/ | GitHub Pages，具体部署见 VALIDATION-1.18.md |
| iOS App | Duo／普通 iPhone 两个定向 TestFlight 组 | 1.22.1 / 28 已于 2026-10-30 送审，正在等待审核；尚未邀请，无公开链接 |
| Mac 主机 | [Mac 0.18.1 试用 Release](https://github.com/STLAND-admin/Chordesk/releases/tag/mac-v0.18.1-test) | Apple Silicon，macOS 15.2+，ad hoc 签名且未公证，安装说明随包提供 |

本机现有 Apple Development 签名 App 继续用于稳定调试。Mac 同学试用包由独立 Release 构建生成，明确标为未公证；不是把本机开发包改名后当正式发行版，也不适用于 iOS。网站与原生源码仓库目前均已公开，自有内容采用 CC BY-NC-SA 4.0。当前 Mac 构建以 Apple Silicon 为准，不承诺 Intel。

## 会员激活后的执行顺序

1. 确认 App Store Connect 可用并创建 Chordesk 记录；优先保留现有 bundle ID。准备隐私政策、支持联系方式、相机／麦克风用途、局域网说明及审查可复现步骤。
2. build 28 已上传，内部验证、Duo 手势体验、iPhone 兼容性测试组均已建立并关联构建。已提交首次外部审核，取消自动通知测试员；通过后再手动邀请。不要给普通测试者 App Store Connect 管理权限。
3. 申请 Developer ID Application 证书，把公证凭据保存到本机 Keychain 的 notarytool profile。用 `scripts/package-macos-release.sh` 生成 Hardened Runtime、签名、公证并装订的 DMG，验证首次安装权限与配对。
4. 把验证过的 DMG、SHA256、变更与安装说明附到 Chordesk 原生仓库的 GitHub prerelease；更新网页下载链接。iOS 只放真实 TestFlight 链接，不能把开发 IPA 放上去代替。
5. 发送一条包含网页、Mac 下载与 TestFlight 的邀请；需要用户明确指定收件人后才代发。当前不发送邀请、不购买资源。

## 测试者准备与十分钟任务

- iPhone 与 Mac 在同一局域网；暂不支持公网。Mac 选一个可丢弃文稿，不共享带私人信息的窗口。允许屏幕录制和控制后扫码配对。
- 不安装额外组件也能测基本画面、键盘、触控与和弦。内置文字大小后端可切换系统现有模式；无法确认原模式恢复时保持当前分辨率。自定义 HiDPI 可能仍需 BetterDisplay 兼容方案，不承诺全部档位。
- 远程麦克风保持关闭。本轮先测操作逻辑；虚拟音频方案与许可确定后单独测音频。
- 依次完成：点目标／滚动；长按拖选；输入并收起键盘；背面双指长按→正面移动光标→松手恢复；背面一指＋正面双指上推／下滑；断开连接。
- 普通 iPhone 跳过背面操作，用右侧按钮切换直接触控／触控板，测试菜单窗口总览／桌面切换，以及键盘遮挡、横竖屏和重连。当前只通过两项普通 iPhone 模拟器 UI 检查，不能视为真机路径已通过。
- Duo 额外重点：背面一指＋正面双指左右滑切桌面；闲置、操作 Mac、键盘／菜单、前后台及旋转后重新落指，检查背面灯和模式是否恢复。
- 每项记录能否独立完成、是否误触、主观延迟、是否遮挡、哪一步需要提示；最后问“你更愿意用背面和弦还是菜单切换，为什么”。记录版本和系统，不收集设备序列号、配对二维码、密钥、账号密码或真实文档。

## 收集反馈

网页提供 GitHub 反馈入口和模板，**提交内容公开**；没有 GitHub 账号的测试者可把下面的文字发回邀请人。TestFlight 开通后优先使用其反馈渠道，上传截图前检查远程桌面内容。

```text
体验方式：网页 / Duo + Mac / 普通 iPhone + Mac
版本与系统：
尝试的任务：
预期结果：
实际结果与重现步骤：
学习成本（1 容易–5 困难）：
误触（无 / 偶尔 / 频繁）：
主观延迟（不明显 / 可察觉 / 影响操作）：
更喜欢和弦还是菜单，原因：
```

参考：[Apple 外部测试流程](https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers/)、[macOS 公证](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)。这些准备不表示已获审核通过。

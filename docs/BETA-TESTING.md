# Chordesk 小范围试用

目标：先找 5–10 位 Duo 用户验证背面和弦是否容易学会、是否误触，以及触控／触控板切换是否自然。网页反馈与真机反馈分开记录，不能用网页结果证明握持舒适或实际延迟。

## 三个交付物

| 交付物 | 试用入口 | 当前状态 |
| --- | --- | --- |
| 概念与操作演示 | https://stland-admin.github.io/Chordesk-site/ | GitHub Pages，具体部署见 VALIDATION-1.18.md |
| Duo App | 定向邀请 TestFlight | 开发者会员注册中；尚未上传、审核或邀请 |
| Mac 主机 | 本地未公证同学试用 DMG；正式版未来放 Releases | Apple Silicon 0.15.0 / 22 测试包已生成，需接收者手动允许；未公开发布、公证或在另一台 Mac 验证 |

本机现有 Apple Development 签名 App 继续用于稳定调试。用户已单独授权由干净 Release 构建生成本地 ad hoc 签名的 Mac 同学试用包，明确标为未公证；不是把本机开发包改名后当正式发行版，也不适用于 iOS。网站公开不等于原生源码公开。发布前确定包的架构、最低系统版本与配套 Duo 版本；目前构建验证以 Apple Silicon 为准，不承诺 Intel。

## 会员激活后的执行顺序

1. 确认 App Store Connect 可用并创建 Chordesk 记录；优先保留现有 bundle ID。准备隐私政策、支持联系方式、相机／麦克风用途、局域网说明及审查可复现步骤。
2. 用 `scripts/archive-ios-release.sh` Archive，在 Organizer 验证并上传。建立外部 Duo 测试组，先通过首次外部测试审核，再手动邀请；不要给普通测试者 App Store Connect 管理权限。
3. 申请 Developer ID Application 证书，把公证凭据保存到本机 Keychain 的 notarytool profile。用 `scripts/package-macos-release.sh` 生成 Hardened Runtime、签名、公证并装订的 DMG，验证首次安装权限与配对。
4. 把验证过的 DMG、SHA256、变更与安装说明附到网站仓库的 GitHub prerelease；更新网页下载链接。iOS 只放真实 TestFlight 链接，不能把开发 IPA 放上去代替。
5. 发送一条包含网页、Mac 下载与 TestFlight 的邀请；需要用户明确指定收件人后才代发。当前不发送邀请、不购买资源。

## 测试者准备与十分钟任务

- Duo 与 Mac 在同一局域网；暂不支持公网。Mac 选一个可丢弃文稿，不共享带私人信息的窗口。允许屏幕录制和控制后扫码配对。
- 不安装额外组件也能测基本画面、键盘、触控与和弦。内置文字大小后端可切换系统现有模式；无法确认原模式恢复时保持当前分辨率。自定义 HiDPI 可能仍需 BetterDisplay 兼容方案，不承诺全部档位。
- 远程麦克风保持关闭。本轮先测操作逻辑；虚拟音频方案与许可确定后单独测音频。
- 依次完成：点目标／滚动；长按拖选；输入并收起键盘；背面双指长按→正面移动光标→松手恢复；背面一指＋正面双指上推／下滑；断开连接。
- 每项记录能否独立完成、是否误触、主观延迟、是否遮挡、哪一步需要提示；最后问“你更愿意用背面和弦还是菜单切换，为什么”。记录版本和系统，不收集设备序列号、配对二维码、密钥、账号密码或真实文档。

## 收集反馈

网页提供 GitHub 反馈入口和模板，**提交内容公开**；没有 GitHub 账号的测试者可把下面的文字发回邀请人。TestFlight 开通后优先使用其反馈渠道，上传截图前检查远程桌面内容。

```text
体验方式：网页 / Duo + Mac
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

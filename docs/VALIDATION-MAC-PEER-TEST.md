# Mac 同学试用包验证

## 0.17.0 / build 24 更新

2026-10-29，源码 `71e5744`。最低运行版本标记修正为实际捕获入口要求的 macOS 15.2。加入默认内置屏服务、关闭窗口保留后台监听、多机配对身份、简洁设置与息屏恢复逻辑；同学机器复测仍待反馈。

- 已发布私有 [Mac 试用 Release](https://github.com/STLAND-admin/Chordesk/releases/tag/mac-v0.17.0-test)，DMG、SHA256SUMS、BUILD-INFO 和中文说明四附件大小/摘要核验通过。
- 本地 DMG：`release-artifacts/mac-test-0.17.0-build24-arm64/Chordesk-Mac-0.17.0-build24-AppleSilicon-test.dmg`。
- SHA-256：`bc6cfb7bd49776a957fe88427443788c87f26995eb8f44e5922325af34ad1848`。
- 干净 arm64 Release、ad hoc 签名、未公证；DMG 校验、只读挂载九文件白名单、严格签名及版本检查通过。Gatekeeper rejected 为预期；未放行或运行测试副本，测试卷已卸载。
- 本机仍使用 Apple Development 稳定签名版；iOS 1.20 / 24 安装启动及实际版本确认。用户随后确认灰色单列按钮、原有配对重连、接电息屏后重连与画面恢复正常，不代替同学机器或多台真实 Mac 验证。范围见 [1.20 验证记录](VALIDATION-1.20.md)。

## 0.16.0 / build 23 更新

2026-10-29，源码 `ca368b8`。用户已反馈旧包在同学 Mac 跑通基础远控，但首次授权需重启、显示档位不可用。新包加入权限检查与空闲自动重启、原生内置屏缩放系列及诊断提示；尚未获得同学机器的新包反馈。

- 新产物：`release-artifacts/mac-test-0.16.0-build23-arm64/Chordesk-Mac-0.16.0-build23-AppleSilicon-test.dmg`。
- SHA-256：`f80dee597bfec796f7a47e126e5f9058db7cc2add8a7b93cc1e9e4691bf30efc`。
- 干净 Release、arm64、本地 ad hoc 签名、未公证。DMG 校验、只读挂载九文件白名单、严格签名完整性、最终校验和均通过，Gatekeeper 评估 rejected 为预期。
- 更新包内中文安装及授权说明；不含配置、凭据、证书或驱动，未启动试用副本或覆盖本机稳定签名版。测试卷已卸载；未上传安装包或代发他人。
- 两端构建、100 项逻辑／事件／TLS 测试及 3 项 Duo 模拟器场景检查的范围见 [1.19 验证记录](VALIDATION-1.19.md)。iOS 1.19 / 23 在 Duo 重新连接后已覆盖安装并启动，用户已确认模式按钮及背面边缘有效区两项正常；不代替同学 Mac 新包复测，不混用旧版真机反馈。

## 0.15.0 / build 22 历史记录

2026-10-29。用户明确要求在无付费会员情况下准备同学测试包，确认接收者使用 Apple Silicon。

- App 源码提交：0594c85；版本 Mac 0.15.0 / build 22，对应 Duo 1.18 / 22。
- 独立干净 SwiftPM Release 构建，本地 ad hoc 签名；不使用或导出任何开发证书、私钥，不修改本机已安装主机。
- 最低目标 macOS 14.0，架构检查 arm64；不包含 Intel。仅本机 macOS 27 构建／静态验收，不推断较早系统或另一台 Mac 已通过。
- 产物：`release-artifacts/mac-test-0.15.0-build22-arm64/Chordesk-Mac-0.15.0-build22-AppleSilicon-test.dmg`。
- SHA-256：`2f3387640db253a79f5c92e7c97c895cf1343281a7d773d5bd20749fccd3170e`。
- DMG 内含 Chordesk.app、Applications 链接、中文安装与配对说明。只读挂载核对 App 九个文件的精确白名单（可执行文件、两个 Info.plist、图标／四个品牌资源、CodeResources）；无配置、钥匙串、配对凭据、provisioning profile、证书或其他第三方程序。
- `codesign --verify --deep --strict` 通过；显示 Signature=adhoc、TeamIdentifier=not set。`hdiutil verify`、最终 `shasum -c`、挂载内容与说明比较通过；测试卷已卸载。
- `spctl --assess` 返回 rejected：这是未公证、本地签名包的预期默认行为，**不是 Gatekeeper 通过**。接收者需要在系统提供的单 App 入口手动允许；不关闭系统安全，不提供移除隔离或绕过策略的命令。
- 脚本语法、help 以及重复输出目录拒绝覆盖检查通过；应用源码本次未变更，复用 1.18 已通过的 94 项逻辑／TLS 测试，不重新发送真实输入或改变显示模式。
- 包未在本机启动、未覆盖本机 App，未在同学 Mac 实测、未上传 GitHub Releases／网站、未代发消息。第一次安装、屏幕录制与控制授权、二维码和局域网输入需接收者验证。

本地 ad hoc 身份更新可能触发重新授权／重配；不要把它当作稳定 Developer ID 公证发行方案。配对二维码可长期重连，说明中要求结束借用后停止共享并按需重置密钥。

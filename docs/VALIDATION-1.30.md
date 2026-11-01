# 1.30：IPv6、隐私与试用分发准备

2026-11-02。iOS **1.30 / build 39**、Mac **0.25.0 / build 38**。基于 1.29/0.24.0 本地工作树；尚未上传 TestFlight、公开 GitHub Release、安装真机或提交正式 App Store。用户明确暂停 Mac Developer ID 与公证，本轮不继续。

## 2026-11-02 后续发行确认

- 用户登录 Xcode 并明确确认新版标准加密申报、批准采用和发布隐私政策。
- Xcode 在 01:28（北京时间）返回 Upload succeeded / EXPORT SUCCEEDED。App Store Connect 已处理 1.30/build 39；选择“Apple 操作系统以外/同时使用的标准算法”、法国不分发，保存后不再提示缺少出口合规。没有把无自创算法等同于不使用加密，也不声称已免除所有出口法律义务。
- 已提交外部 TestFlight Beta App Review，构建列表明确显示 **正在等待审核**，详情页出现“从审核中移除”。关联原三个组，未新增测试员，自动通知保持关闭，原公开链接与人数上限未改。等待审核不是已批准，也不是已可安装新版；正式 App Store 没有提交。
- 中英文 Beta 介绍、当前隐私 URL、测试重点及英文审核备注已保存。说明真实披露内嵌 Tailscale、非摄影 CameraCaptureAccessory、相机帧丢弃、音频关闭、Mac 未公证和合盖限制。审核联系人沿用原 Apple 后台记录，未写入仓库。
- [Mac 0.25.0 试用 Release](https://github.com/STLAND-admin/Chordesk/releases/tag/mac-v0.25.0-test) 已公开为 pre-release，附 DMG 和 SHA256SUMS.txt。公开接口确认非 draft、两个附件；GitHub 计算的 DMG SHA256 与本地一致。没有恢复 Developer ID 或公证流程。
- 双端源码已推送公开 main：`52f7d96`；没有推送私有历史或本地安全审查报告。官网隐私版本提交 `c87634a`，已在公开页面核验新日期/Tailscale 说明及旧政策链接；旧 iOS 1.22.1 / Mac 0.18.1 政策保留。
- 用户目前无其他需要完成的登录/授权。若将来会话失效、出现本人认证或新协议，应停在该处，而不是把此次确认当作无限授权。

以下“尚未上传/公开”的描述属于此前本地导出阶段，由以上实际发行状态覆盖。既有日常安装版本仍未替换，硬件 IPv6 和新包首次安装回归仍待测试。

## 实现

- 接口枚举含 IPv4 与 IPv6；LAN 支持 ULA、链路本地及当前子网的全局 IPv6。地址使用严格 IP 字面量解析，拒绝 IPv4-mapped、任意域名、组播/未指定地址及不合法 scope。链路本地 QR 不带 Mac 接口名，由手机自己的接口添加 scope。保留 PSK、nonce、hostID、会话与权限校验。
- 全局 IPv6 只能对当前活动本地接口的子网拨号；入站也检查所绑定子网，掩码缺失/不连续/短于 /48 时拒绝。其目的是 IPv6 LAN 兼容，不开放普通公网 IPv6 远控。跨网仍走内嵌 Tailscale。
- Mac 保留原 IPv4 入口，在同接口增加最多三个 IPv6 监听；额外监听用自动独立端口并随配对信息通告。本系统同端口双监听曾返回地址占用，未依赖不可靠的端口复用。
- Tailscale Swift 与 Go 桥接一致接受 `100.64.0.0/10` 与 `fd7a:115c:a1e0::/48`；转发使用 `net.JoinHostPort`，仍拒绝普通公网地址/域名与任意脚本。内部 loopback 桥接继续 IPv4，不妨碍外层 IPv6。
- 记住多条已认证的双栈端点，同一主机只按认证身份/密钥归并；密钥轮换不保留旧密钥的候选。明确连接时最多 12 个候选并行只读协商，网络内第一条成功才参与 Tailscale 优先/350ms LAN 回退；某地址失败不提前判定整个网络失败。普通在线查询仍只读；手动固定模式不会切到另一网络。
- 手动 IP 输入改为可输入 IPv6 字符的键盘，地址/端口显示用 IPv6 方括号格式。
- About 加入本地双语隐私全文、支持入口；公网控制区域增加独立短按隐私弹窗及元数据/境外处理说明。没有让隐私按钮变成整行 NavigationLink，以免重现表单误触。
- 移除已关闭音频对应的 iOS 麦克风用途声明；双端禁用音频的 feature gate 保持有效。
- 替换单方“最终解释权”为版权、源码许可和法定权利说明。完整二进制使用许可补充见 `LEGAL-TERMS-DRAFT.md`，仅为推荐稿，未改变仓库 CC BY-NC-SA 4.0 或替用户签署自定义 EULA。隐私候选见 `PRIVACY-POLICY-1.30.md`，尚未发布到官网/ASC。

IPv6 地址族不构成性能保证：Tailscale 原引擎已能自行选择底层网络；内层从 100.x 换成 fd7a 不必然改变 direct/relay 路径。未声称已测得更低延迟。

## 验证与边界

- `/private/tmp/chordesk-1.30-final-tests.log`：176 项，**175 通过、1 跳过、0 失败**。新增 6 项 IPv6 回归覆盖严格范围、scope/子网拒绝、配对持久化与轮换、真实 IPv6 TLS 回环，以及双栈两个监听同时认证收发。
- 原固定端口测试不再只等 10 秒：补充真实 listener 失败回调，本轮明确收到 `EADDRINUSE`，因此跳过占用端口的这一项；没有关闭用户的日常主机，也不能把跳过称为该项已验收。下次无其他主机监听时仍需单独跑生产端口集成测试。其他临时端口 TLS/错误密钥等回归通过。
- `/private/tmp/chordesk-1.30-go-tests.log`：Go 桥接全部通过。`build-tailnet.sh` 重建 macOS、iOS、arm64/x86_64 模拟器静态库及 xcframework，不启动节点。
- 两项合成 fixture UI 通过：局域网免登录/模式入口；公网登录/断开/退出/隐私短按互不误触。前者证据 `chordesk-1.30-ui.log`，后者最终 `chordesk-1.30-ui-verified.log`。中间发现旧测试仍用已废弃的模式名及选中下层完成按钮，修正定位后通过，未为测试更改产品行为。
- iOS Release 编译、手动发行签名 Archive 与 export 成功。`Info.plist`/privacy manifest 格式通过；干净解包的实际 IPA 严格签名通过，1.30/39、正式 profile、`get-task-allow=false`、`beta-reports-active=true`、无设备名单、无麦克风用途声明、包含隐私资源。归档目录曾带 Finder 元数据，不能以其严格检查失败误判实际 ZIP；原 IPA 无 `__MACOSX` 项，独立临时目录解包已通过。
- Mac Release 编译、本地 ad-hoc 完整性与 DMG 校验通过。**没有 Developer ID 签名、没有公证**。用户暂停证书流程后已终止请求，未在 Apple 创建证书或提交公证；只生成公开证书前的页面停留不等于生成证书。没有将私钥写入仓库。
- 没有真机 IPv6-only/DNS64-NAT64 网络、蜂窝双栈或跨运营商延迟实测，不宣称已通过全部 IPv6 审核环境。需用新版双端实际配对一次以保存新端点；旧凭据与 IPv4 回退保留。
- 现有日常 App、TCC、配对、Tailscale 登录、电源/锁屏设置均未替换或重置。旧公开 TestFlight 1.22.1 /28 与公开 Mac 0.18.1 保持不变。

## 产物

- iOS Archive：`release-artifacts/ios-1.30-build39/Chordesk.xcarchive`
- 发行 IPA：`release-artifacts/ios-1.30-build39/export/iPhoneDuoDemo.ipa`
- SHA256：`321f668757fd4787fb77d7ed7b5d49f190431cfed9f4b1ae88dc71716886955d`，同目录有 SHA256SUMS.txt。
- Mac：`release-artifacts/mac-test-0.25.0-build38-arm64-final/Chordesk-Mac-0.25.0-build38-AppleSilicon-test.dmg`，随附安装说明、构建来源标记与校验和。中间候选保留但不用于最终交付。
- 安装包来自本地工作树，有未提交修改，BUILD-INFO 明确标注，不能把旧 HEAD 哈希当作完全复现该包的干净提交。

## 后续发行

大陆备案/隐私填报路线见 `CHINA-FILING-AND-DISTRIBUTION.md`。工信部材料齐备后的办理时限可达 20 个工作日，无法保证一周内大陆正式上架；优先准备新外部 TestFlight，正式港美/大陆材料并行。TestFlight 仍需 Apple Beta Review 和新版外部标准加密申报，不能沿用 build 28 的系统加密分类，也不是法律豁免。

Xcode 当前 Apple Accounts 界面未登录；Edge 已登录 App Store Connect，但网页“构建版本上传”仅显示上传记录，不能直接把 IPA 当网页附件上传。已请用户自行在 Xcode 登录后再上传；未收取密码/验证码。没有创建 App Store Connect API 私钥或绕过登录。正式 App Store 草稿 1.29 保留，最后提交仍由用户执行。

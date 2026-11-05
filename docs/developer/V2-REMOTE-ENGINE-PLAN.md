# v2 · Remote engine evaluation / 远控引擎评估

2026-11-05 · Status: research and implementation plan; no new engine shipped.

## Baseline and decision

The `v2` branch starts from the accepted v1 experience. Source checkpoint: `4b1009c`; product baseline: iOS 1.32 (46), Mac 0.28.0 (43). The iOS build was submitted for App Store review on November 5; submission is not approval. Existing releases and `main` are not changed by this branch.

The checkpoint includes reviewed build-46 UI changes and subsequent source-only maintenance. It is **not a byte-for-byte reconstruction of the uploaded IPA**: the source development region is now `zh-Hans`, while the uploaded build uses `en`; the November 5 website policy supplement also needs synchronization into a future binary. Preserve submitted archives separately; do not rebuild and upload another binary under build 46.

**建议：保留 Chordesk 交互层，在 v2 试做可替换的远控引擎。RDP 是主要实验候选，macOS 自带 VNC 是对照／兼容候选；在测量前不替换现有 H.264／HEVC 路径。先补齐链路诊断、建连和屏保恢复，再比较协议。** 本地光标独立开发，不以 RDP 迁移为前提。

本轮完成源码审查和方案，不代表已修复用户报告的弱网／屏保问题，也没有安装或运行 macrdp、开启系统 VNC、改变端口或安全设置。

## RDP、VNC、现有路径的区别

| 路线 | 实际传输与潜在收益 | 与 Chordesk 需求相关的限制 | v2 定位 |
| --- | --- | --- | --- |
| 现有 ScreenCaptureKit + VideoToolbox | 已有实时 H.264／HEVC、JPEG 回退；可增加独立光标、过期帧预算、自适应码率和独立控制通道 | 当前视频、状态等复用有序流；无完整 direct／relay 观测，缺少真实呈现时延数据 | 保留为稳定回退与优化基准 |
| macrdp / IronRDP | macOS 捕获后发送位图，或协商 EGFX AVC420 / H.264；RDP 可携带独立光标与缓存更新 | 不是将任意 Mac 窗口转换为 UI 源码；上游目前单会话、缺多显示器支持，认证与完整光标形状获取须额外审查 | 主要实验引擎，先验证当前登录桌面 |
| macOS 原生屏幕共享 + VNC/RFB 客户端 | 系统提供被控服务；RFB 支持矩形更新、CopyRect、客户端绘制光标，适合做静态文档对照 | 实际编码与 cursor 扩展要协商验证；通用 VNC 不自动获得 Apple 专有高性能屏幕共享能力，也不保证比实时视频省带宽 | 系统服务对照和可选兼容后端 |

RDP 是应用协议，H.264／HEVC 是编码，Tailscale 是连接层，三者不处在同一层。RDP/VNC 仍可通过 Tailscale；换 RDP 不会自动换掉当前公网线路。现代 RDP 也可能主要发送视频／位图；文字是否更清晰、滚动是否更省流，要看服务端实现与实际协商。[Microsoft RDP](https://learn.microsoft.com/en-us/windows/win32/termserv/remote-desktop-protocol) · [RFB §7.8.1 本地光标](https://www.rfc-editor.org/rfc/rfc6143#section-7.8.1) · [Apple 屏幕共享](https://support.apple.com/en-gb/guide/mac-help/mh11848/mac)

### macrdp 固定参考版本

本次查看 `clintcan/macrdp` 的提交 [`8848191f866813df13ffa039c8c87b5eca32aa62`](https://github.com/clintcan/macrdp/tree/8848191f866813df13ffa039c8c87b5eca32aa62)，Cargo 版本 0.9.11。以下是该快照的特性，不是 Chordesk 已验证结果：

- [README](https://github.com/clintcan/macrdp/blob/8848191f866813df13ffa039c8c87b5eca32aa62/README.md) 与 [video](https://github.com/clintcan/macrdp/blob/8848191f866813df13ffa039c8c87b5eca32aa62/docs/video.md)：ScreenCaptureKit 捕获，位图与可选 VideoToolbox H.264；不能假定它把 AppKit／SwiftUI／Metal 内容转成客户端绘制命令。
- [光标模块](https://github.com/clintcan/macrdp/blob/8848191f866813df13ffa039c8c87b5eca32aa62/src/cursor/mod.rs) 的完整系统形状读取依赖 [私有 SkyLight 符号](https://github.com/clintcan/macrdp/blob/8848191f866813df13ffa039c8c87b5eca32aa62/src/cursor/private_api.rs)。不能直接纳入当前坚持公开 API 的实现；先做公开 API 可实现的位置同步与通用箭头，并明确跨应用光标形状限制。
- 上游使用 TLS、NLA/CredSSP 与 Mac 账号认证，并有钥匙串凭据流程。Chordesk 现有配对 PSK 不能直接充当 NLA 凭据；必须先设计认证适配，不默认收集／保存用户 Mac 登录密码，也不通过关闭认证完成接入。
- 上游说明了单用户会话、多显示器及安全输入／loginwindow 等限制；不能把它视为解决锁屏、合盖或 FileVault 启动前登录的方案。上游性能与长期运行数据仅为作者报告，需在我们的两端独立复测。
- [Cargo 许可](https://github.com/clintcan/macrdp/blob/8848191f866813df13ffa039c8c87b5eca32aa62/Cargo.toml) 为 MIT OR Apache-2.0；若引入须核对依赖和 vendored IronRDP，保留原版权、许可及必要 NOTICE，不把第三方代码改标为本项目 CC BY-NC-SA。当前仅引用，未引入依赖。

## 用户反馈与代码证据

### 1 · 小于 1 Mbps、约 5000 ms 延迟

**尚未测出本次连接是 direct 还是 DERP，不能判定为 Tailscale 个人版统一限速。** 官方明确：无法直连时可能使用 DERP；DERP 会增加路径时延，并为公平使用限制吞吐。UDP 被阻断、双方较严格的 NAT、运营商线路、拥塞及两端无线网络都可能影响结果。[连接类型](https://tailscale.com/docs/reference/connection-types) · [性能排查](https://tailscale.com/docs/reference/troubleshooting/poor-performance-tailnet)

代码还存在独立于公网服务的排队候选：

- `ProjectFiles/Chordesk/LANWire.swift` 的 `LANLink` 将视频、状态、ping／确认等放在同一条 `NWConnection` 中；接收端先收完一个包体再读下个包头。同一方向的大视频包可挡住后续状态／ping 回应；不能将双向 TCP 误说成视频下行必然阻塞输入上行。
- 已有 `VideoSendGate` 限制应用层待发送视频并处理依赖帧丢弃；`.contentProcessed` 是本地 Network.framework 的写入处理完成，**不是手机呈现确认**。它不能证明 socket、Go 转发及中间网络没有积压。现有最大包 4 MiB／约 8 MiB 待写保护也不是低时延预算。
- 仅作量级说明：在有效吞吐 1 Mbps 时，625,000 字节积压就需约 5 秒传完，尚未包含其他开销。这不是对用户现场的测量。
- 当前 HUD RTT 经过应用协议和调度，可能包含同流排队；它不是纯物理网络 RTT，也不是点击到画面变化的完整时延。

先对比空闲／传输中的 RTT、有效吞吐、帧龄、编码耗时、丢帧和 direct／relay，再决定降低码率、替换通道还是调整公网连接。低于 1 Mbps 时优先维持可读的静态文字和及时输入，不能持续按高于可用吞吐的目标码率发送。提高编码效率不等于必然降低延迟。

### 2 · 公网建连／刷新登录状态慢

审查依据：`ProjectFiles/Chordesk/EmbeddedTailnet.swift`、`LANClient.swift`、`ProjectFiles/Native/Tailnet/main.go`。当前固定 tsnet 为 1.104.1。

- 本机状态调用 `StatusWithoutPeers`，超时上限 3 秒；UI 定时刷新就绪时约每 5 秒、未就绪时约每 2 秒，均还需加上调用耗时。Swift C 桥和 Go API 有串行区段，手动刷新没有完整的同请求合并；这可能让状态显示及后续任务等待，不代表每次必等满 3 秒。
- 该快照只报告本机运行状态，没有对端 direct／DERP 路径。**本机 Ready、账号已登录、对端可达、配对成功、有新画面**是五件不同的事。
- 公网探测在引擎未就绪时有最多约 4 秒等待；Go bridge 的异步 `server.Dial` 最多等待 12 秒。`CRDial` 本身先返回 localhost bridge，不是持有全局锁等待整个网络拨号。现有自动选路已包含 Tailscale 优先及 LAN 竞争，不能简单归因为“先搜局域网再搜 Tailscale”。

计划：合并重复 refresh、使用缓存快照配合异步更新、复用已绑定引擎；逐阶段展示进度和取消／超时原因。为**当前内嵌节点**读取对端路径指标；外置 Tailscale App／CLI 是另一节点，不能用其结果冒充本 App 的链路。

### 3 · 动态屏保时连接失败，UU 可用

`ProjectFiles/Chordesk/LANHost.swift` 中，息屏会暂停捕获；`sessionDidResignActive` 与 `willSleep` 都撤销本次控制。屏幕／系统唤醒会调用 `retryInterruptedCapture`，但 `sessionDidBecomeActive` 只重建输入源和提示重连，没有同样的捕获恢复调用。这是恢复路径的审查线索，**尚未在这次动态屏保场景复现，不能认定屏保一定触发该通知**。

必须分开测试：动态屏保未锁定、仅显示器息屏、锁屏、用户切换、整机睡眠、合盖、FileVault 启动前。先记录公开生命周期通知、捕获错误与服务可达性，区分监听失效、采集无新帧、输入许可撤销。保留已有“认证后新建捕获会话”的恢复逻辑；不能把旧画面当恢复成功。

修复目标：在原会话、原显示器、原配对身份与系统权限仍有效时有界恢复服务与画面；按现有安全边界重新取得控制，不自动跨用户或绕过登录。UU 在同条件可用是有效对照，不足以证明采用相同公开 API，或我们的系统权限已被撤销。更换 RDP 不会自动修复生命周期；原有合盖日志见 [合盖审计](HOST-WAKE-LATENCY.md)。

## v2 实施顺序

### P0 · 先让问题可测、连接可恢复

- [ ] 记录 engine-start → local-ready → peer-path → TLS/配对 → capture-start → first-presented-frame 各段耗时，分开本机状态与对端在线。
- [ ] 加入内嵌 tsnet 的 direct／DERP／peer-relay／未知、路径切换与空闲／负载延迟；诊断默认本地、脱敏、可关闭，不记录密码、输入内容、桌面或有效配对信息。
- [ ] 合并状态查询，处理取消和过期回调，避免要求已绑定用户重复登录；不为追求“快”跳过身份验证。
- [ ] 为动态屏保／息屏／锁屏建立状态转移与连续重连测试，必要时重建原采集源；系统停止共享、权限撤销、用户切换与真正睡眠分别处理。

### P1 · 统一输入接口、本地光标和低时延通道

```text
现有直接触控 / 触控板 / Duo 和弦 / iPhone 输入法
                    ↓
           RemoteSession 接口（待实现）
          ↙             ↓              ↘
  Chordesk 视频       RDP 实验         VNC 对照
          ↘             ↓              ↙
        画面显示层 + 独立本地光标层 + 连接状态
```

- [ ] 保留已有输入语义：绝对／相对移动、左右键、按下／拖动／抬起、滚轮与统一惯性、组合文字、Ctrl／Option／Cmd、Mission Control／Spaces，以及断线释放。背屏继续只参与模式／和弦切换。
- [ ] 将选择显示器、分辨率和窗口总览等能力与传输能力明确协商。RDP/VNC 未提供的功能通过已认证 Chordesk 控制通道补充，不能默默删除现有功能。
- [ ] 本地光标元数据包含会话、显示器、捕获版本、坐标空间、形状／热点（支持时）、可见性和序号；使用公开 API，缺形状时明确回退通用箭头。
- [ ] 触控板移动先本地反馈，再与 Mac 权威位置协调；避免两端加速度重复计算，并同步 Mac 物理鼠标变化。直接触控是否显示指针可选，不改变点击坐标。
- [ ] 当前 `SCStreamConfiguration.showsCursor = true`。只有双方协商本地光标且元数据可用后才关闭视频内光标，防双光标；老版本保持原样。光标流畅不等于点击结果已到达。
- [ ] 拆分控制／状态与视频的传输流并绑定同一认证会话；实验最新帧预算、呈现确认和自适应码率。仅换多条 TCP 不能解决拥塞，评估 datagram／QUIC／WebRTC 等时须同时验证 tsnet 与 DERP 真实路径，不按技术名称承诺低延迟。

### P2 · RDP 最小原型与 VNC 对照

- [ ] 隔离构建 macrdp 参考实现，先连当前登录桌面，审查私有 API、认证、显示器、输入及依赖。未经明确安排，不开放公网 3389／5900、关闭 NLA 或保存登录密码。
- [ ] 对比 FreeRDP iOS 客户端桥接与 IronRDP 客户端 FFI 的实际维护成本、许可和硬件解码；选型后才引入依赖，不把示例 Windows 连接成功当 Mac 集成成功。
- [ ] 对照 Apple 内建 VNC 服务，记录实际协商的编码、光标和安全能力；不假设支持全部扩展。系统服务开启需用户明确选择，远程访问留在受认证的安全通道中。
- [ ] RDP 需在弱网文字、滚动、兼容性与时延上达到下述验收，再决定默认或保留实验开关；原引擎始终可回退。

### P3 · 商业引擎合作备选

UU 已公开 [跨 App 接入文档](https://github.com/netease-uuyc/uuremote-integration-guide)：iOS／Android 客户端 4.42.0 起可绑定 Windows／Mac 设备，再拉起 UU 全屏／PiP，需另装 UU。**当前文档没有开放由 Chordesk 注入鼠标／键盘／滚轮或接管其视频渲染的接口**；这个入口本身不足以保留我们的整套前后屏交互。

合作可以把 Chordesk 聚焦在独特交互、由成熟引擎处理网络，但需取得可嵌入 iOS 客户端／Mac 主机能力，明确原始输入、光标、编码帧、身份、锁屏恢复、流量费用、地区、隐私和商用授权。公开文档／示例的 MIT 许可不等于服务或引擎可任意嵌入。当前没有对外联系或承诺，合作也不是 v2 推进的前提。

## 对比与验收

下列为**拟定测试条件和目标，不是已经测出的性能**：

| 维度 | 方法 |
| --- | --- |
| 网络 | 相同两端、画面和时间段；LAN、Tailscale direct、DERP 分开标记；受控带宽 0.5 / 1 / 3 Mbps，RTT 50 / 150 / 300 / 500 ms，丢包 0 / 1 / 3%；先单变量再组合，单列真实运营商线路 |
| 场景 | TextEdit 输入／选区、Codex 多行文字、网页滚动、窗口拖动、视频；相同分辨率和可读性目标，不只比较 FPS |
| 指标 | 冷／热连接首帧 p50/p95、失败率、空闲和负载 RTT、采集／编解码／呈现耗时、帧龄、队列字节、实际 Mbps、输入确认、操作至可见结果、能耗 |
| 光标 | 区分落指至本地光标响应和远端操作生效；测试主机物理鼠标、双端加速度、形状／热点、切屏与分辨率变化，不以本地预测冒充成功执行 |
| 生命周期 | 屏保未锁定／息屏／锁屏分别连续连接至少 5 次；记录通知与新帧时间，输入仅在许可有效时执行；真正睡眠／FileVault 启动前明确列为限制 |
| 交互回归 | 直接触控／触控板、0/1/2 指和弦、选择释放、惯性中断、输入法组合／退格／修饰键、菜单、显示器切换与断开恢复 |

记录各阶段单调时钟耗时；跨设备帧龄需先估算时钟偏移及误差，不能直接相减两台设备墙上时间。用外部录制或可重复应用反馈测点击到可见变化，避免把协议 ack 当用户已看到。

迁移门槛：同样网络预算和可读性下，至少改善关键场景的 p95 操作延迟或带宽，且没有持续累积数秒旧画面；不退化现有输入与身份边界。报告失败场景和样本数，再确定 RDP／VNC／原引擎的默认组合。全程不修改 v1 分发与审核中的二进制。

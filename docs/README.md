# Documentation / 文档

[English README](../README.md) · [中文 README](../README.zh-CN.md)

<a id="users"></a>

## For users / 用户文档

Install Chordesk, connect your devices and learn the controls. / 安装、连接、操作与故障处理。

| Document / 文档 | Contents / 内容 |
| --- | --- |
| [Mac installation / Mac 安装](user/MAC-PEER-TEST.txt) | Requirements, drag-to-install and first-launch permissions / 系统要求、拖拽安装与首次授权 |
| [Operation guide / 操作指南](user/OPERATION-GUIDE.md) | Touch, trackpad, rear chords, keyboard and quality / 直接触控、触控板、背面和弦、键盘与画质 |
| [Tailscale connection / 公网连接](user/TAILSCALE.md) | LAN and cross-network setup, account binding and limits / 局域网、公网绑定与连接边界 |
| [Mac maintenance / Mac 维护与卸载](user/MAC-MAINTENANCE.md) | Updates, Keychain recovery, permissions and removal / 升级、钥匙串修复、权限与卸载 |
| [Beta testing / 测试与反馈](user/BETA-TESTING.md) | TestFlight, downloads and reporting problems / 测试入口、下载与反馈 |
| [What's new / 更新记录](user/CHANGELOG.md) · [中文](user/CHANGELOG.zh-CN.md) | Changes since the first TestFlight beta / 首个 TestFlight 版本以来的更新 |
| [Privacy policy / 隐私政策](user/PRIVACY-POLICY-1.30.md) | Adopted policy; also available on the website and in the apps / 已采用的政策，官网与 App 内亦可查看 |

<a id="developers"></a>

## For developers / 开发者文档

Build, test and distribute Chordesk, or follow the development plans. / 构建、测试、分发与后续开发。

| Document / 文档 | Contents / 内容 |
| --- | --- |
| [Project layout / 工程目录](developer/PROJECT-LAYOUT.md) | App sources, projects, tests, native bridge and artwork / 源码、工程、测试、原生桥接与素材 |
| [Build instructions / 开发构建](developer/DEVELOPMENT.md) | Xcode, Go, SwiftPM and Mac packaging / 开发环境与两端构建 |
| [Coding guidelines / 编码规范](developer/AGENTS.md) | Rules and boundaries for contributors and coding agents; read before changing code / 修改代码前阅读的项目约定 |
| [First-run checklist / 首次安装检查](developer/FIRST-RUN-CHECKLIST.md) | Isolated Mac/iOS setups and manual acceptance checks / 隔离测试与真实首次使用验收 |
| [Distribution / 分发准备](developer/DISTRIBUTION.md) | TestFlight, App Store and signed/notarized Mac releases / 双端发行与审核 |
| [Dependencies / 依赖](developer/DEPENDENCIES.md) | Native display scaling and third-party boundaries / 显示适配及第三方依赖边界 |
| [Roadmap / 开发计划](developer/ROADMAP.md) | Priorities, completed work and remaining tests / 优先级、已完成工作与待验证项目 |
| [v2 remote engines / v2 远控引擎](developer/V2-REMOTE-ENGINE-PLAN.md) | RDP/VNC comparison, local cursor, weak-network and screen-saver investigation / 协议比较、本地光标、弱网与屏保恢复计划 |
| [Network planning / 公网方案](developer/PUBLIC-NETWORK-PLAN.md) | Embedded Tailscale decision and historical hosting estimates / Tailscale 路线与历史自建成本备选 |
| [Wake and latency / 合盖与延迟](developer/HOST-WAKE-LATENCY.md) | Evidence, known limits and future measurements / 已有证据、已知限制与测量计划 |
| [Development history / 开发与验证历史](developer/DEVELOPMENT-HISTORY.md) | Consolidated validation and historical release/prototype notes / 合并的验证、旧发行和原型记录 |
| [Guide recording assets / 演示录制素材](developer/guide-assets/) | Practice documents and action timestamp template / 练习文稿与动作时间表 |

Build commands run from the repository root. `Package.swift`, `ProjectFiles/` and `scripts/` stay there as build entry points and source directories. Artwork directories may contain a local README explaining their files. / 构建命令均从仓库根目录运行；工程入口、源码与脚本保留原位，素材目录的 README 用于就近解释文件。

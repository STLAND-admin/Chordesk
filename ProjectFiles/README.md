# Project files / 工程目录

All application code, build projects, tests and artwork live here. The iPhone client and Mac host are one product: **Chordesk**.

| Path | Purpose / 用途 |
| --- | --- |
| `Chordesk.xcodeproj` | Open this in Xcode; choose the **Chordesk** scheme for the iPhone app. / iPhone 工程入口。 |
| `Chordesk/` | Swift source and runtime resources shared by iPhone and Mac; platform-specific files use conditional compilation. / 两端源码及随包资源。 |
| `Tests/ChordeskHostTests/` | Protocol, input, video, pairing and lifecycle regression checks. / 逻辑与协议测试，不随 App 安装。 |
| `Tests/ChordeskUITests/` | iOS simulator interaction tests. / 菜单、键盘与手势界面测试，不随 App 安装。 |
| `Native/Tailnet/` | Embedded Tailscale userspace engine bridge, written in Go/C, with pinned dependency versions. / 公网网络引擎桥接，属于基础功能代码。 |
| `Branding/` | SVG masters, rendered app icons and design references. / 品牌和图标源素材；App 运行只使用打包后的必要资源。 |

The root `Package.swift` builds the Mac executable/module **ChordeskHost**. `scripts/` contains build/package/maintenance tools; `docs/` contains current instructions. Generated `build/` and `release-artifacts/` are local-only and excluded from Git.

The original bundle IDs and credential namespaces deliberately remain stable so a project rename does not create a new app or lose existing pairing. Historical names may appear in migration compatibility code and the consolidated development history.

[Build instructions](../docs/DEVELOPMENT.md) · [Operation guide](../OPERATION-GUIDE.md)

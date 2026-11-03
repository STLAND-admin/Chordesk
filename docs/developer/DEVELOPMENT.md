# Chordesk 开发

完整 Xcode 27.1；iOS 控制端使用 iOS 27.1 SDK，真机主测 Duo。Mac 主机最低运行版本 macOS 15.2，目前硬件验收环境为 macOS 27。

## 两端共用的内嵌网络引擎

当前开发版需要 Go 1.27.1+（本机验证使用官方 Go 1.27.3）及完整 Xcode。先从 [Go 官方](https://go.dev/dl/)安装工具链，然后：

```sh
./scripts/build-tailnet.sh
# 或 CHORDESK_GO=/absolute/path/to/go ./scripts/build-tailnet.sh
```

脚本按 `ProjectFiles/Native/Tailnet/go.mod`／`go.sum` 下载并校验官方模块，生成忽略入 Git 的 `build/tailnet/ChordeskTailnet.xcframework`。包括 Mac arm64、iOS arm64 和模拟器 arm64/x86_64。不启动节点或登录，不包含个人凭据。`swift build/test` 与 Xcode 均需先有该产物；修改原生引擎或依赖版本后重跑脚本。Mac 打包脚本缺少产物时会调用它。

依赖下载需要联网，默认用 Go 官方代理；本机首次下载官方代理超时，测试使用 `GOPROXY=https://goproxy.cn`，仍保留模块校验，不关闭 sumdb。这不是 App 运行时代理。

```sh
# 原生字节桥接／取消／地址范围检查；不会登录或操作真实设备
(cd ProjectFiles/Native/Tailnet && go test -race ./...)
# 更新依赖后重新收集并审查两端随包许可
python3 scripts/collect-tailnet-notices.py
```

注意：这不是嵌入外部 Tailscale 可执行文件，不应把机器上已有的登录状态、auth key 或配置目录复制进 App。跨网测试步骤、适用条件及发布要求见 [TAILSCALE.md](../user/TAILSCALE.md)。

## iOS

打开 `ProjectFiles/Chordesk.xcodeproj`，选择自己的 Team 和可用 Bundle Identifier，在 Duo 模拟器或已开启开发者模式的真机运行。个人账号不等于 TestFlight 分发资格，详见 [分发准备](DISTRIBUTION.md)。已有设备保持原签名和标识以延续 App 数据。

## Mac

```sh
CHORDESK_SIGNING_IDENTITY="Apple Development" ./scripts/build-workbench.sh
# 默认 /private/tmp/ChordeskBuild/Chordesk.app
./scripts/build-workbench.sh --install
```

正式使用打开 Applications 中唯一的 Chordesk。开发构建与发行包使用不同构建目录；升级先正常退出，再替换同一位置的 App。旧版本权限和钥匙串问题见 [维护与卸载](../user/MAC-MAINTENANCE.md)。

```sh
# 测试不会投递真实输入或调整实体屏；固定端口若被日常主机占用，应报告跳过而不强停服务。
swift test --scratch-path /private/tmp/ChordeskTests
# 在独立目录生成 Apple Silicon ad hoc 未公证测试 DMG，不安装到本机。
./scripts/package-macos-test.sh
```

## 代码导航

所有源码、工程、测试和素材集中在 [ProjectFiles](PROJECT-LAYOUT.md)。`Package.swift` 留在根目录，作为 Mac 的 SwiftPM 构建入口。

已安装过的 Mac 和 iPhone 可用 [双端首次安装检查](FIRST-RUN-CHECKLIST.md) 复测空白偏好、授权和配对。`python3 scripts/build-first-run-qa.py --platform both --team TEAM_ID` 生成隔离副本；默认 `--platform macos` 保留 Mac 单端流程。无需清除原版的权限、配对或 Tailscale 节点。[Mac 隔离原理与历史记录](DEVELOPMENT-HISTORY.md#archive-mac-first-run-qa)。正式发行准备见 [分发准备](DISTRIBUTION.md)。

- `ContentView.swift`、`StableControls.swift`：iOS 浮动菜单与键盘入口。
- `CameraAccessory.swift`、`GripInputState.swift`、`RearAreaEditor.swift`：背面和弦与有效区。
- `LANWire.swift`、`LANClient.swift`、`LANHost.swift`：配对、TLS、视频和输入传输。
- `ChordeskMacApp.swift`、`LANHostView.swift`、`HostAvailability.swift`：主机与后台可用性。
- `NativeDisplayScaling.swift`、`BetterDisplayBridge.swift`：显示模式及恢复。
- `StreamSettings.swift`、`VideoCodec.swift`：独立传输设置、限量测速推荐与硬件编解码。
- `RemoteMicrophone.swift`：暂时禁用的音频兼容层，不向用户提供入口。
- `ProjectFiles/Tests/`：Mac 逻辑回归与 iOS 界面检查；不会安装给用户。

原网页位于独立公开仓库 [Chordesk-site](https://github.com/STLAND-admin/Chordesk-site)。原生仓库也已公开，不提交签名材料、配对凭据、构建产物或其他产品。

## 拖拽安装 DMG

仅构建机器需要 Python 依赖；不随 App 安装到用户电脑。

```sh
python3 -m venv /private/tmp/chordesk-dmg-tools
/private/tmp/chordesk-dmg-tools/bin/pip install ds-store==1.3.1 mac-alias==2.2.2
CHORDESK_DMG_PYTHON=/private/tmp/chordesk-dmg-tools/bin/python ./scripts/package-macos-test.sh
```

脚本通过公开文件格式生成 Finder 图标位置和隐藏背景，无需操控 Finder。镜像中可见项目只有 Chordesk.app 与 Applications，背景包含中英文拖入指引。布局只写入 DMG 内的 `.DS_Store`，不得为安装外观写入全局 `com.apple.finder` 偏好，也不要在安装窗口点“用作默认”；普通窗口背景异常的修复见[维护说明](../user/MAC-MAINTENANCE.md)。公证脚本使用本机钥匙串的 notarytool profile；若只使用 Xcode 已登录账号，也可通过 Organizer 的 Developer ID → Upload 提交 App 公证。最终 DMG 的命令行公证需单独配置 notarytool 凭据；不要导出或读取 Xcode 登录令牌。App 及归档先在本地临时目录暂存，避免 Documents 同步服务给包重新添加 FinderInfo。当前发行结果见开发历史。

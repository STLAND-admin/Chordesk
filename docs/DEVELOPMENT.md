# Chordesk 开发

完整 Xcode 27.1；iOS 控制端使用 iOS 27.1 SDK，真机主测 Duo。Mac 主机最低运行版本 macOS 15.2，目前硬件验收环境为 macOS 27。

## 两端共用的内嵌网络引擎

当前开发版需要 Go 1.27.1+（本机验证使用官方 Go 1.27.3）及完整 Xcode。先从 [Go 官方](https://go.dev/dl/)安装工具链，然后：

```sh
./scripts/build-tailnet.sh
# 或 CHORDESK_GO=/absolute/path/to/go ./scripts/build-tailnet.sh
```

脚本按 `Native/Tailnet/go.mod`／`go.sum` 下载并校验官方模块，生成忽略入 Git 的 `build/tailnet/ChordeskTailnet.xcframework`。包括 Mac arm64、iOS arm64 和模拟器 arm64/x86_64。不启动节点或登录，不包含个人凭据。`swift build/test` 与 Xcode 均需先有该产物；修改原生引擎或依赖版本后重跑脚本。Mac 打包脚本缺少产物时会调用它。

依赖下载需要联网，默认用 Go 官方代理；本机首次下载官方代理超时，测试使用 `GOPROXY=https://goproxy.cn`，仍保留模块校验，不关闭 sumdb。这不是 App 运行时代理。

```sh
# 原生字节桥接／取消／地址范围检查；不会登录或操作真实设备
(cd Native/Tailnet && go test -race ./...)
# 更新依赖后重新收集并审查两端随包许可
python3 scripts/collect-tailnet-notices.py
```

注意：这不是嵌入外部 Tailscale 可执行文件，不应把机器上已有的登录状态、auth key 或配置目录复制进 App。跨网测试步骤、适用条件及发布要求见 [TAILSCALE.md](TAILSCALE.md)。

## iOS

打开 `iPhoneDuoDemo.xcodeproj`，选择自己的 Team 和可用 Bundle Identifier，在 Duo 模拟器或已开启开发者模式的真机运行。个人账号不等于 TestFlight 分发资格，详见 [分发准备](DISTRIBUTION.md)。已有设备保持原签名和标识以延续 App 数据。

## Mac

```sh
DUO_SIGNING_IDENTITY="Apple Development" ./scripts/build-workbench.sh
# 默认 /private/tmp/DuoWorkbenchBuild/Chordesk.app
./scripts/build-workbench.sh --install
```

从 `~/Applications/Chordesk.app` 打开主机；这里必须是真实应用包。仅给旧 `DuoWorkbench.app` 增加 Chordesk 符号链接不能修正 Dock 的悬停名称。

早期开发安装需先退出主机，再将原来已签名的 `DuoWorkbench.app` 整包重命名为 `Chordesk.app`。若 Chordesk 原先是指向旧包的符号链接，只移开这个链接，不覆盖任何已有实体包；可在旧路径留下指向新包的兼容链接。取消实体包的 Finder 隐藏属性，从新路径启动，并复查系统权限。迁移只改变包路径，不改内部文件、bundle ID、签名或配对数据，不重置权限。安装脚本遇到尚未迁移的旧实体包会停止，避免生成两个不同版本的主机。不要把旧开发目录中的历史 `.app` 当成当前版本。

```sh
# 先退出占用 49173 端口的主机；测试不会投递真实输入或调整实体屏。
swift test --scratch-path /private/tmp/ChordeskTests
# 在独立目录生成 Apple Silicon ad hoc 未公证测试 DMG，不安装到本机。
./scripts/package-macos-test.sh
```

## 代码导航

已安装过的 Mac 可用 [独立首次安装测试副本](MAC-FIRST-RUN-QA.md) 复测授权流程，无需清除原版的权限、配对或 Tailscale 节点。正式发行准备见 [App Store 1.23](APP-STORE-1.23-PREPARATION.md)。

- `ContentView.swift`、`StableControls.swift`：iOS 浮动菜单与键盘入口。
- `CameraAccessory.swift`、`GripInputState.swift`、`RearAreaEditor.swift`：背面和弦与有效区。
- `LANWire.swift`、`LANClient.swift`、`LANHost.swift`：配对、TLS、视频和输入传输。
- `WorkbenchApp.swift`、`LANHostView.swift`、`HostAvailability.swift`：主机与后台可用性。
- `NativeDisplayScaling.swift`、`BetterDisplayBridge.swift`：显示模式及恢复。
- `RemoteMicrophone.swift`：麦克风传输与虚拟设备路由。
- `Tests/`、`iPhoneDuoDemoUITests/`：逻辑与模拟器检查。

原网页位于独立公开仓库 [Chordesk-site](https://github.com/STLAND-admin/Chordesk-site)。原生仓库也已公开，不提交签名材料、配对凭据、构建产物或其他产品。

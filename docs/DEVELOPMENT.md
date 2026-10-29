# Chordesk 开发

完整 Xcode 27.1；iOS 控制端使用 iOS 27.1 SDK，真机主测 Duo。Mac 主机最低运行版本 macOS 15.2，目前硬件验收环境为 macOS 27。

## iOS

打开 `iPhoneDuoDemo.xcodeproj`，选择自己的 Team 和可用 Bundle Identifier，在 Duo 模拟器或已开启开发者模式的真机运行。个人账号不等于 TestFlight 分发资格，详见 [分发准备](DISTRIBUTION.md)。已有设备保持原签名和标识以延续 App 数据。

## Mac

```sh
DUO_SIGNING_IDENTITY="Apple Development" ./scripts/build-workbench.sh
# 默认 /private/tmp/DuoWorkbenchBuild/Chordesk.app
./scripts/build-workbench.sh --install
```

沿用原 bundle ID、签名与稳定路径 `~/Applications/DuoWorkbench.app`，避免钥匙串／系统权限失效。

```sh
# 先退出占用 49173 端口的主机；测试不会投递真实输入或调整实体屏。
swift test --scratch-path /private/tmp/ChordeskTests
# 在独立目录生成 Apple Silicon ad hoc 未公证测试 DMG，不安装到本机。
./scripts/package-macos-test.sh
```

## 代码导航

- `ContentView.swift`、`StableControls.swift`：iOS 浮动菜单与键盘入口。
- `CameraAccessory.swift`、`GripInputState.swift`、`RearAreaEditor.swift`：背面和弦与有效区。
- `LANWire.swift`、`LANClient.swift`、`LANHost.swift`：配对、TLS、视频和输入传输。
- `WorkbenchApp.swift`、`LANHostView.swift`、`HostAvailability.swift`：主机与后台可用性。
- `NativeDisplayScaling.swift`、`BetterDisplayBridge.swift`：显示模式及恢复。
- `RemoteMicrophone.swift`：麦克风传输与虚拟设备路由。
- `Tests/`、`iPhoneDuoDemoUITests/`：逻辑与模拟器检查。

原网页位于独立公开仓库 [Chordesk-site](https://github.com/STLAND-admin/Chordesk-site)。原生仓库私有，不提交签名材料、配对凭据、构建产物或其他产品。

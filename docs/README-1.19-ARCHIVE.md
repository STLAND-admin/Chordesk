# 1.19 项目说明归档

以下为历史版本说明，不代表当前状态；以根目录 README 为准。

<p align="center"><img src="Branding/Chordesk-dark.svg" width="180" alt="Chordesk：前后交叠的玻璃面与和弦触点"></p>

# Chordesk

**前后协作，像按和弦一样控制。** STLAND present · STLAND 出品

已选定 B「前后双面」作为图标。[黑底 SVG](Branding/Chordesk-dark.svg) · [透明 SVG](Branding/Chordesk-transparent.svg) · [品牌素材说明](Branding/README.md)。仓库现为 [STLAND-admin/Chordesk](https://github.com/STLAND-admin/Chordesk)，历史记录和私有权限保留。

为 iPhone Duo 设计的远程控制实验：背面手指按住或切换控制模式，正面拇指完成直接触控、触控板、文字输入。仓库包含 **iOS 控制端** 和 **macOS 主机端**。

目前只支持同一局域网。首次扫码／IP 配对，凭据保存至钥匙串；后续可点选已配对 Mac。连接地址仍为缓存 IP，DHCP 改变后可能需要重新扫码。Bonjour、公网连接和账号服务均为规划，尚未实现。

## 当前开发版

- 首次使用检查 Mac 屏幕录制与控制权限；全部通过、空闲时三秒后自动重启 App，可取消。系统权限尚未生效时保留手动重启检查入口。
- 手机新增独立直接触控／触控板按钮，与显示器和菜单并排，可在“全屏触控方式”隐藏。
- 背面有效区域可视化编辑：拖动移动、四角缩放、贴边预设和位置／尺寸比例滑杆，自动保存；原四周禁触模式保留。
- 内置显示模式切换，默认目标 **1600×900 逻辑分辨率**，优先同尺寸 HiDPI；非 16:9 屏保持比例。仅使用系统现有安全模式，不生成自定义档位。支持安全标准模式及部分内置屏扩展缩放系列；无法确认恢复的自定义模式仍拒绝修改并显示原因；本机当前自定义 HiDPI 配置继续使用保留的 BetterDisplay 兼容方案。[能力边界](docs/DEPENDENCIES.md)。
- 菜单与键盘按钮恢复为独立圆形 Liquid Glass，保留短按、靠右位置和独立背面手指数提示。
- 网站 3D 模型循环示范背面 **0 → 1 → 2 → 0** 指，显示落指／抬指和接触环；支持手动选择左侧／右侧／下方握法，默认外屏位于左侧（以正面视角为准）。

- 新增可选 **Duo 麦克风 → Mac 应用输入**，默认关闭，可选择连接后自动开启。Mac 需选择虚拟音频设备（如 BlackHole 2ch），会议应用选择同名输入；不保存录音、不更改系统默认音频设备。[配置说明](docs/REMOTE-MICROPHONE.md)。
- Mac 启动仅打开 **Chordesk · Mac 主机**，不再显示本地双屏交互台。历史原型代码保留，交互展示转到网站。

- iOS **1.19 / build 23**，Mac **0.16.0 / build 23**。
- 右侧玻璃 Dock 移到内容安全区之外，按公开系统区域对齐至右上状态区下方；上下可调。背面手指数提示独立固定，菜单保留普通短按选择。
- 原生／微信输入法保留。新增可调的手机布局键盘：ABC／123／#+=、Shift 单次／锁定大写，Ctrl／Cmd／Option 位于键盘右侧。
- 两端显示名称与图标更新为 Chordesk；App 使用黑底图标，关于页使用透明图形，保留 STLAND 出品署名。
- 背面触摸取消后按实际活跃接触对象恢复，避免键盘／菜单切换丢失结束事件或复用触摸对象时被旧状态拦截。用户已在 1.16 真机确认：输入文字并收起键盘后，重新双指长按仍能正常切换直接触控／触控板。
- 独立模式按钮为无背面能力设备提供切换入口；仍只针对 Duo 测试，未验证其他机型。**这不是已实现的 App Store 机型分发限制**，见[分发准备](docs/DISTRIBUTION.md)。

本轮构建、自动测试和部署写入 [1.19 验证记录](docs/VALIDATION-1.19.md)。用户已在 1.19 真机确认独立模式按钮切换正常，以及背面有效区移到边缘后区域内触发、区域外不触发。此前背面切换真机反馈见 [1.16 验证记录](docs/VALIDATION-1.16.md)。真机确认仅覆盖明确复测的操作路径；其他输入法、布局旋转及长期稳定性仍待验证。

## 运行

需要完整 Xcode。相机辅助外屏实验使用 iOS 27.1 SDK 与对应 Duo 设备／模拟器。

```sh
open iPhoneDuoDemo.xcodeproj
# 在 Xcode 选择自己的 Signing Team 和 Duo 目标。
# 保留当前设备的 bundle ID 可覆盖更新并保留配对信息。
```

Mac 主机用 SwiftPM 构建并包装为 App：

```sh
# 使用本机已安装的稳定开发证书；不回退临时 ad hoc 签名。
DUO_SIGNING_IDENTITY="Apple Development" ./scripts/build-workbench.sh
# 默认输出 /private/tmp/DuoWorkbenchBuild/Chordesk.app
# 安装到 ~/Applications/DuoWorkbench.app：
./scripts/build-workbench.sh --install
```

显示名称为 Chordesk；保留历史 executable／bundle ID／安装路径，避免破坏已有钥匙串配对与系统授权。Mac 需要屏幕录制、辅助功能／输入权限；显示模式默认使用内置公开 Core Graphics 后端；当前模式无法确认可恢复时保留原画面，可在主机选 BetterDisplay 兼容方案。两条路径均不创建虚拟显示器。

```sh
# 完整测试前关闭正在监听 49173 的开发主机，避免 TLS 回环端口冲突。
swift test --scratch-path /private/tmp/ChordeskTests
```

## 代码导航

| 部分 | 入口 |
| --- | --- |
| iOS 场景、浮动菜单与设置 | `iPhoneDuoDemo/ContentView.swift`、`StableControls.swift` |
| 相机辅助背面与和弦状态 | `CameraAccessory.swift`、`GripInputState.swift` |
| 直接触控／触控板／手机布局／输入法 | `DirectTouch.swift`、`TouchpadSurface.swift`、`MobileKeyboard.swift`、`NativeInput.swift` |
| 传输、配对、能力协商 | `LANWire.swift`、`LANClient.swift`、`LANHost.swift` |
| 远程麦克风、固定格式音频包、虚拟设备路由 | `RemoteMicrophone.swift` |
| Mac 主机、共享与分辨率 | `WorkbenchApp.swift`、`LANHostView.swift`、`NativeDisplayScaling.swift`、`BetterDisplayBridge.swift`、`HostAvailability.swift` |
| 逻辑、传输与 UIKit 回归 | `Tests/`、`iPhoneDuoDemoUITests/` |
| 图标、个人品牌与提示词 | `Branding/`、`iPhoneDuoDemo/Resources/Brand/` |

## 使用与发布

已准备 Apple Silicon 同学试用包（未公证，接收者需手动允许），使用 `./scripts/package-macos-test.sh` 可在独立目录重建；不会安装或上传。首次安装步骤见 [说明](docs/MAC-PEER-TEST.txt)。正式 Developer ID／公证流程继续使用原 release 脚本。

- [操作指南](OPERATION-GUIDE.md)：手势、窗口总览、键盘、画质与重连。
- [公网部署与成本规划](PUBLIC-NETWORK-PLAN.md)：杭州、每日四小时的直连／中继与扩容方案；未购买或部署。
- [Mac 安装包与 iOS TestFlight 准备](docs/DISTRIBUTION.md)、[小范围试用清单](docs/BETA-TESTING.md)。
- [BetterDisplay 与虚拟音频依赖／许可](docs/DEPENDENCIES.md)。
- [开发历史](docs/DEVELOPMENT-HISTORY.md)与 [AI 编码规范](AGENTS.md)。

相机辅助外屏仍要求活动采集会话，帧不显示、不保存、不传输；不代表已获得通用外屏 API 或上架许可。画面是可变码率 JPEG，60／120／144 fps 为请求上限，不能当作实测帧率。输入通过公开鼠标／键盘事件兼容，不是 macOS 原生多点触摸注入。

公开[概念与操作演示](https://stland-admin.github.io/Chordesk-site/)已上线；网站源码在独立仓库 [Chordesk-site](https://github.com/STLAND-admin/Chordesk-site)，演示默认直接触控、背面一指＋正面双指上下滑、背面双指长按临时触控板。本仓库不包含网页构建产物、签名材料、配对凭据或其他产品。

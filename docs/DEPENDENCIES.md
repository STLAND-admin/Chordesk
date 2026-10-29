# Chordesk 的可选依赖与去依赖计划

核对日期：2026-10-29。

## BetterDisplay

1.18 新增独立编写的 `NativeDisplayScaling.swift`，通过公开 `CGDisplayCopyAllDisplayModes` 枚举、`CGDisplaySetDisplayMode` 切换系统已有安全模式，以公开 ColorSync UUID 保存基准，并用 Core Graphics 事务恢复原排列。**内置路径不调用 BetterDisplay，也不链接、复制或捆绑其代码。**

默认目标为 **1600×900 逻辑分辨率**，不是硬件 DPI。相同逻辑尺寸优先 HiDPI；非 16:9 屏按原画幅选择最接近 1600 宽的模式，不拉伸、不创建虚拟屏或驱动。同尺寸尽量保留原刷新率。可用性受显示器与当前系统模式列表限制，不能保证自定义 HiDPI 档位。

实测发现：本机原 MAG 的 2560×1440 HiDPI 模式只存在于扩展／当前模式列表，切到标准 1600×900 后该原模式消失，公开 API 无法重新枚举。已经用原兼容后端恢复。1.18 要求原模式也存在于系统标准列表；1.19 放宽内置面板：原模式安全且扩展列表存在同逻辑／像素尺寸的另一安全刷新率时，可使用该缩放系列。外接屏仍保留标准列表门槛。此规则是保守兼容判断，不是 Apple 对恢复的保证；恢复时仍需重新枚举并验证，失败保留记录。

1.19 已在本机内置屏实测 2056×1329 HiDPI 120 Hz → 1496×967 HiDPI 120 Hz → 原模式成功，两个显示器原点也与测试前相同。它解决了这条曾被过度拦截的路径，不能推断同学的所有显示器都支持。没有档位时显示安全模式数量和具体原因，可先在系统显示设置选择默认分辨率后刷新。不能把“内置后端已实现”写成“所有 HiDPI 功能已去依赖”。

从系统标准 2560×1440 出发，内置 1600×900 切换及恢复已实际成功，并验证上下排列恢复。缩小屏幕时 macOS 会保持接壤并调整原点，因此仅在恢复原尺寸之后还原精确位置，不在缩放途中强行恢复旧原点。实际连接／断连组合仍需 Duo 复测。

兼容方案 `BetterDisplayBridge.swift` 继续保留，通过官方 CLI 调用运行中的完整 BetterDisplay，仅在主机明确选择时使用。切换方案前断开并恢复原设置；旧恢复日志保留。当前这台 Mac 因自定义模式仍选择兼容方案，默认目标也改为 1600 宽（该外接屏实际为 1600×900 HiDPI）。基础远控不依赖它。

**BetterDisplay 当前 App 不是开源软件**：作者说明当前源码私有，开源的是早期 BetterDummy 和独立 CLI 等。不能直接复制当前 App 或视作可免费捆绑；CLI 开源也不意味着完整 App 无需授权。所请求功能是否需 Pro 服从其授权。

参考：[作者源码 FAQ](https://betterdisplay.pro/guide/faq/general/source-code/)、[公开 CLI](https://github.com/waydabber/betterdisplaycli)、[BetterDisplay 集成说明](https://betterdisplay.pro/guide/integration/)、[Apple 模式枚举](https://developer.apple.com/documentation/coregraphics/cgdisplaycopyalldisplaymodes(_:_:))、[Apple 模式切换](https://developer.apple.com/documentation/coregraphics/cgdisplaysetdisplaymode(_:_:_:))。

## BlackHole / GPLv3

GPLv3 是 GNU 通用公共许可证第 3 版，允许使用、修改和商业使用。主要义务发生在向他人分发受许可代码或衍生作品时，包括保留声明、提供对应源码并遵守相同许可要求。个人运行原版不等于需要公开自己的所有软件；相互独立的软件也不会仅因安装在同一台电脑自动变成 GPL。

BlackHole 作者另外明确要求非 GPLv3 项目取得授权。Chordesk 当前没有复制、链接或捆绑 BlackHole 代码，仅通过 Core Audio 路由到用户选择的虚拟音频设备；但“随闭源产品集成、改名或一起分发”不能据此直接认定免授权。发布前应向作者确认所选集成方式／购买商业授权，或自行实现独立虚拟音频设备后再做驱动签名与验证。

用户明确暂不安装 BlackHole。已下载核验的安装包不纳入源码或发布包，不安装、不接受新许可、不重启音频系统。本轮麦克风链路默认关闭；未完成虚拟输入设备及目标会议应用验证。初期手势测试不需要这个依赖。

参考：[BlackHole 许可原文](https://github.com/ExistentialAudio/BlackHole/blob/master/LICENSE)、[作者开发集成要求](https://github.com/ExistentialAudio/BlackHole#developer-guides)。以上用于工程方案判断，正式分发授权以许可文本和权利人的确认范围为准。

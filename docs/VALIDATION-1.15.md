# 1.15 / build 19 验证记录

日期：2026-10-29。iOS 1.15 / 19，Mac 0.12.0 / 19，显示名称 ChordRemote。

- 75 项 SwiftPM 测试通过，包含新增手机键盘分页、精确符号输入、Shift 状态、修饰键，以及固定端口 TLS 回环。运行前正常停止旧主机释放 49173。没有向真实桌面注入测试输入，也没有在测试中改变实体屏幕排列。
- 三项 Duo 模拟器 UIKit 回归通过：菜单连续短按打开设置／指南、取消与重新打开及键盘快捷菜单、自定义手机键盘的 ABC／123／#+= 与右侧 Dock 不重叠。覆盖合成触摸短按，不把可访问性触发视为物理触摸验证。
- 本轮修复了贴边控件撞上 Duo 系统保留区域的问题，改用 iOS 27.1 的公开 `UIView.LayoutRegion.bar(onEdge:extent:)`，extent 来自实际 Dock 宽度。仅靠传统 safeAreaInsets／statusBarFrame 不足以安置此右侧栏。玻璃是不可接收触摸的背景，原生按钮和普通列表仍负责交互。
- 系统键盘展开时，弹出菜单会暂收键盘，关闭后恢复；保持输入桥接与菜单宿主，避免菜单重建。未确认组合不发送。自定义键盘保留竖向四键 Dock；原生键盘保留靠右横向 Dock。
- 最终 iOS 真机目标签名构建成功，iOS 包和已安装 Mac 包严格签名校验通过。保留既有 bundle ID 和 Apple Development 身份。
- Mac 0.12.0 / 19 已覆盖安装至原有 `~/Applications/DuoWorkbench.app`。安装后 Mac 锁屏，**尚未重新启动和恢复共享**；不把磁盘安装视为主机联调通过。
- 实体 Duo 当前被 Xcode 标记为 unavailable，**1.15 尚未覆盖安装到手机**。待 USB 连接并解锁后继续安装，不将模拟器通过视为真机手感通过。

最后对深色底图下的键帽增加独立系统材料，以保持文字对比度；手机键盘 UI 用例再次通过，已检查截图。

本地日志（不提交构建产物）：`build/chord115-full-tests.log`、`build/chord115-ui7.log`、`build/chord115-key-contrast.log`、`build/chord115-signed-final.log`、`build/chord115-mac-install.log`。截图来自测试画面，不含真实远程桌面。玻璃背景在白色测试图下观感较浅，实机透明度与拇指触感仍需复测。

未进行非 Duo 测试、App Store／TestFlight 上传、公网部署或外部安装包分发。历史真机确认见开发历史，不扩展为本版全部功能已验证。

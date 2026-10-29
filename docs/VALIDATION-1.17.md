# Chordesk 1.17 / build 21 验证记录

日期：2026-10-29。iOS 1.17 / 21、Mac 0.14.0 / 21。

## 实现范围

- 用户澄清语音方向是 **Duo 麦克风 → Mac 应用的麦克风输入**。新协议能力可选协商，旧主机不启用，不发送未知包；手机默认关闭，可保存连接后自动开启偏好。Mac 独立接收开关和虚拟音频设备选择，默认没有路由。
- 固定 24 kHz 单声道 Int16 PCM、20 ms 包、随机流 ID 和递增序号；TLS 传输、固定包长校验、积压丢包和有界播放队列。断连／后台／音频中断／路线变化／Mac 会话离开停止，不保存录音。
- Mac 只打开 Chordesk · Mac 主机；删除本地演示 Window 注册，历史原型源码保留。稳定签名、旧 bundle ID、配对协议标识、Keychain 服务名和安装路径继续保留。
- 网站仓库重命名 Chordesk-site，保留 repo ID 1430051224 与历史。原生主仓库继续 Chordesk。网站重写默认交互：全屏触控、按需键盘、一指＋正面双指窗口总览、双指长按临时触控板。保留并更新 3D 握持模型、右／下两种握法；增加自动示范和键盘替身。

## 检查

- iOS 模拟器、iOS 真机目标签名、Mac App 构建成功；两端严格签名校验通过。另已完成 macOS Release 构建及稳定开发签名校验，产物 `/private/tmp/Chordesk117Release/Chordesk.app`；这是开发签名，不是公证分发包。
- iOS Archive 与 Mac Developer ID／公证 DMG 脚本已准备并通过 shell 语法检查、help 与缺凭据拒绝检查。尚未实际执行分发签名、公证或 TestFlight 上传；当前只检测到 Apple Development 身份。
- 完整 **83 项**逻辑／CGEvent 构造／TLS 回环测试通过，包括新增音频包和旧版能力协商。固定端口测试首次被运行中的主机占用阻止；正常退出旧主机后复测通过。初次大帧与音频一并排队触发正确的音频丢包规则，测试改为依次回包后发送，新增音频 TLS 往返成功。
- 两项 Duo 模拟器 UI 检查分别通过：菜单短按与右侧对齐；音频当前开关和自动开启默认关闭、旧主机无法启用。音频测试初轮未找到滚动后的开关，改为滚动 Form 并回看上一行后通过。
- 网页 JavaScript 语法检查通过；浏览器检查默认触控、菜单模式切换、键盘显隐、操作示范完成后恢复。浏览器多点触摸与真实音频尚未端到端验证。
- 下载 BlackHole 2ch 0.7.1 官方安装包，pkgutil 报告 Developer ID Installer: Existential Audio Inc.、有效公证。SHA256 与 Homebrew 官方 cask 一致：57b540f27a3e29c37e310e01bee0fdfab76733087e47f997ef9dccf851400dcf。用户随后明确暂不安装，安装包不捆绑、不分发。

## 部署状态

- iOS 签名包：`/private/tmp/Chordesk117Signed/Build/Products/Debug-iphoneos/iPhoneDuoDemo.app`。首次查询 unavailable、安装失败；用户重插 USB 后已安装，实际设备查询确认为 **Chordesk 1.17 / 21**。自动启动被设备 Locked 拒绝，需要用户解锁后打开，不宣称已启动。
- Mac **0.14.0 / 21 已覆盖安装并启动**：稳定安装路径 `~/Applications/DuoWorkbench.app`，严格签名通过，UI 确认为 Chordesk · Mac 主机。两项系统控制权限有效、配对凭据保留，恢复更新前 MAG 271QPX E2 共享，二维码和帧数正常。麦克风接收仍关闭、音频设备未选。初次合并覆盖发现旧品牌资源使签名失效，已改为干净整包替换并重新验证。
- GitHub Pages 首次返回 422（当前套餐不支持私有 Pages）。用户随后明确授权仅公开网站仓库；已变更可见性、启用 Pages workflow 与发布变量。网站和公开反馈模板已提交，Pages 工作流 [40824003349](https://github.com/STLAND-admin/Chordesk-site/actions/runs/40824003349) 成功；线上 [Chordesk](https://stland-admin.github.io/Chordesk-site/) HTTP 200、最新和弦文案和反馈入口已核对。原生仓库保持私有。Git 上传两次因网络失败，改用 GitHub Git Data API 上传，并验证远端提交与本地 2e6c7ec 完全一致；未改写历史。浏览器本地视觉检查通过，线上浏览器自动化重连超时，不能称为线上截图复验完成。
- 没有上传 TestFlight，没有购买服务或部署公网远控。网站只模拟输入，不连接真实电脑。

## 待真机复测

- BlackHole 配置后：Duo 允许麦克风、目标 Mac 应用本地测试输入电平；开关关闭后归零。未授权不采音。
- 打开相机背面实验并同时录音，检查键盘和背面组合；切后台／断连／来电／蓝牙路线变化后停止。
- 各会议应用、延迟、音质、长期稳定性尚未验证；不能沿用 1.16 背面手势结果证明新音频功能可用。

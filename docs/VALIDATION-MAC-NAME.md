# Mac 本地应用名修正 · 2026-10-30

## 问题与修正

第一次只给实际 `DuoWorkbench.app` 增加名为 `Chordesk.app` 的符号链接。窗口和菜单已显示 Chordesk，但用户报告 Dock 悬停仍显示 DuoWorkbench，因此 `1be2509` 的处理不完整。

本次正常退出主机，将同一个已签名的实体包重命名为 `~/Applications/Chordesk.app` 并从新路径启动。旧路径只保留隐藏的反向兼容链接。没有复制第二套运行中的主机、重新签名、更换 bundle ID，或读取、修改配对凭据。

安装脚本改为始终安装实体 Chordesk.app；对未迁移旧实体包和 Chordesk 符号链接明确停止，不猜测覆盖。版本仍为 Mac 0.18.1 / build 26，运行代码没有变化。

## 验证

- 改名前后可执行文件、Info.plist、CodeResources 的 SHA-256 相同；整个包通过 `codesign --verify --strict`。
- 新路径启动后，窗口与应用菜单均为 Chordesk，共享内置屏服务已运行。
- 主机设置中的屏幕录制、控制 Mac 两项检查均显示“已允许”。工具单独执行的 CLI probe 得到 screen=true、accessibility=false、input=false，与正常启动的主机界面结果不同；未据此更改或重置系统权限，不宣称该差异原因已确定。
- Dock 自动化读取超时两次，用户随后明确确认悬停名称“已显示 Chordesk”。
- `zsh -n scripts/build-workbench.sh` 与 `git diff --check` 通过。此次未重编译 App，不把脚本语法检查描述为完整安装回归。

重启会断开原远控会话；配对数据保持原样。此处没有改名后的完整远控手势回归结果。

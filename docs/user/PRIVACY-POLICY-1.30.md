# Chordesk 隐私政策（已采用）

隐私政策

2026 年 11 月 5 日 · 适用于内嵌 Tailscale 的 Chordesk 版本

旧公开局域网版本 iOS 1.22.1 / Mac 0.18.1 另见 原版本政策。

一、开发者与基本原则

Chordesk 由 STLAND / Yinji Shentu（申屠寅吉）开发。联系邮箱：styj@zju.edu.cn。
Chordesk 是连接你有权使用的手机与 Mac 的远程控制工具。开发者没有运营用于接收远程桌面、输入内容或账号资料的 Chordesk 业务服务器，没有 Chordesk 云账号，原生客户端没有集成广告 SDK，开发者也不接收用于用户行为分析的数据。可选第三方网络及认证服务有各自的数据处理，详见第四节。源码公开不等于免除隐私义务；可选 Tailscale 服务会处理下述元数据。不得将本政策概括为“所有参与方均不处理任何个人信息”。

二、远程控制数据

你选择共享的 Mac 显示器画面会加密发送给配对手机；点按、滚动、按键、输入文字及显示器/分辨率选择会发往该 Mac。画面可能包含私人文稿和密码界面，请仅共享你有权访问的设备。设备名称、主机标识、IP 地址、显示尺寸、控制状态、帧率与连接计时用于配对、路由与状态显示。自动弹出键盘检查焦点控件的角色、可编辑性、位置和安全输入状态，不读取该控件的文字值。
Chordesk 使用实时内存缓冲，不主动把桌面或输入内容录制到文件，也不自动发送给开发者。被控应用、输入法、操作系统及你主动使用的录屏工具可按各自规则处理内容；本政策不控制这些软件。接收设备由你或你授权的人控制。

三、相机与音频

相机用于扫描 Mac 配对二维码，以及 Duo 上你可关闭的相机辅助背屏交互。二维码含配对凭据，勿公开有效二维码。背屏交互时前台相机采集持续运行，采集帧被丢弃，不作为远控画面显示、保存或传输。相机扫描仅解析二维码，不保存扫描照片。可在系统设置撤销相机权限；不用相机仍可手动输入配对信息和使用正面控制。
当前版本关闭麦克风采集、语音传输及音频接收功能；不会因曾保存的麦克风偏好自动采音。手机麦克风不会自动成为 Mac 的麦克风。

四、可选 Tailscale 公网连接

局域网功能免登录，不要求启用 Tailscale。你主动启用公网后，App 内的 Tailscale tsnet 引擎向 Tailscale 控制服务登记节点，由你在官方认证页面登录自己的账号与私人网络。开发者不接收该登录密码，也不提供共享 tailnet 或通用上网代理。
Tailscale 及你选择的身份提供商会按各自政策处理账号姓名/邮箱、账号与设备标识、节点公钥、设备/系统信息、IP 地址及连接诊断等元数据，用于身份认证、节点协调、连接与故障处理。直连失败时可能使用 Tailscale 中继运输加密流量；这不等于由开发者运营中继。Tailscale/WireGuard 与 Chordesk 配对加密保护传输内容，不隐藏连接所需元数据。具体处理、地点、保留期限、删除方式以服务提供商政策与账户设置为准，可能涉及你所在地以外的处理，不能承诺全部存储在中国大陆。
使用前请阅读 https://tailscale.com/privacy-policy 与 https://tailscale.com/terms 。身份提供商由你在认证页选择。不同意可不启用或断开/退出公网，局域网仍可使用。你可在 Tailscale 管理页面移除 Chordesk 节点、调整访问策略或管理账号；仅退出 Chordesk 不保证删除服务商已有记录。

认证网页与 Cookie。iOS 使用系统认证窗口，当前会话可能复用浏览器登录状态。相关网站可按页面、地区及你的选择使用必要、分析或广告 Cookie，详见 Tailscale Cookie Notice 及其隐私选择。开发者不读取认证网页密码或 Cookie；退出 Chordesk 不会自动清除第三方浏览器状态。可以不启用该服务，继续使用局域网。

服务分析与日志。Chordesk 已关闭内嵌网络引擎的客户端诊断日志上传。这不会消除服务商为账号、节点协调、安全和运行维护处理的元数据；服务商还可能按其政策进行服务分析与改进。当前只集成 tsnet 网络连接，没有接入 Aperture 内容网关或 PAM 会话录制。

第三方删除与账号年龄。退出公网或移除本地配对不会保证删除第三方已有记录。可在 Tailscale 管理页面移除 Chordesk 节点，个人信息请求可联系 privacy@tailscale.com；删除整个私人网络可能影响其他节点。日志、备份及依法保留的资料按服务商规则处理，不承诺立即清除。启用可选账号服务前须符合其年龄要求：Tailscale 现行政策不允许未满 16 岁者开户或管理账号；监护人指导和 App Store 内容分级不替代该要求。

五、本地保存、停止与删除

配对凭据、记住的电脑及 Tailscale 节点状态保存在本机钥匙串；界面偏好、画质与显示恢复状态保存在本机偏好或应用支持目录。系统钥匙串可能在卸载后保留，卸载不等于撤销对端权限。
在手机“连接 Mac”中忘记电脑可移除该条本地配对；它不会让持有同一凭据的其他设备失效。Mac 停止服务后重置配对密钥，可使旧配对凭据整体失效。停止共享/远控、退出公网及撤销系统录屏、控制或相机权限，会停止相应能力。当前不提供自动上传到开发者的桌面日志；诊断界面主要显示本地状态，主动反馈前请删除私密画面、账号、地址与有效密钥。

六、网站、分发与主动反馈

Apple 按其规则处理 App Store/TestFlight 分发、诊断和你主动提交的反馈；开发者可能看到 Apple 提供的测试反馈与诊断。官网由 GitHub Pages 托管，GitHub 可处理访问连接信息；网站在浏览器本地保存语言偏好。网站已移除自愿测试问卷入口。此前通过 Google Forms 主动提交的答复仍仅用于测试邀请与反馈联系，可通过邮箱请求更正或删除。GitHub Issues/讨论是公开的，不适合提交个人隐私。
你通过邮件或 GitHub Issues 联系开发者时，我们会处理你主动提供的联系方式与内容，仅用于回复、安排测试、解决问题及必要的安全/法律事务，不用于出售数据或广告画像。处理完成后不再保留非必要资料；依法必须保留或解决争议所需部分除外。你可用联系邮箱提出查阅、更正或删除请求。没有内容上传不意味着第三方托管、反馈或分发服务没有数据处理。
第三方政策：https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement 、https://policies.google.com/privacy 、https://www.apple.com/legal/privacy/ 。

七、权利、安全与更新

你可通过上述开关撤回可选功能，通过联系邮箱询问开发者持有的信息、请求更正/删除、投诉或行使适用法律赋予的其他权利。第三方账户/节点信息需同时通过相应服务商管理。我们采用配对认证、加密、系统权限和有界缓冲等措施，但不能保证任何系统绝对安全；请保护设备和二维码，只控制有权访问的 Mac。未成年人应在监护人指导下使用，不鼓励提交不必要的个人资料。
本政策不限制你依法享有的权利。数据用途、接收方或功能发生实质改变时，将更新政策和相关提示，依法需要同意的变更会另行征求同意。

Privacy policy

November 5, 2026 · Chordesk versions with embedded Tailscale

For the previous public LAN-only versions (iOS 1.22.1 / Mac 0.18.1), see the earlier policy.

Operator: STLAND / Yinji Shentu. Contact: styj@zju.edu.cn. Updated November 5, 2026.
Chordesk connects phones and Macs you own or are authorized to control. The developer operates no Chordesk backend receiving remote screens, typed content or account profiles, provides no Chordesk cloud account, and does not embed an advertising SDK or receive app-behavior analytics on developer servers. Optional network and authentication providers have separate data practices as described below. Optional third-party services still process personal information; “no developer backend” does not mean “no data processing.”
Selected display frames travel encrypted to the paired phone; pointer, scroll, keyboard, text and display commands travel to the Mac. Names, host IDs, addresses, display geometry, connection/control status and timing support pairing and operation. Automatic keyboard presentation checks focus role, editability, position and secure-input status, not the field's text value. Chordesk uses live memory buffers and does not intentionally record desktop/input content or automatically send it to the developer. Remote apps, keyboards, operating systems and recording tools follow their own practices.
Camera access scans pairing codes and enables optional foreground camera-accessory rear interaction on Duo. Camera frames are discarded, not displayed, stored or transmitted as remote video. QR photos are not saved. A valid QR code contains pairing credentials: do not publish it. You can revoke camera access and use manual pairing/front controls. Audio capture and transport are disabled in this version, including previously saved preferences.
LAN access needs no account or Tailscale. If you enable public-network access, embedded tsnet registers a node in your own Tailscale network using official authentication. Tailscale and your chosen identity provider process account name/email, user/device identifiers, public keys, device/system information, IP addresses and connection diagnostics for authentication, coordination and operation. Encrypted traffic may pass through Tailscale relays when direct connectivity is unavailable. Encryption does not conceal connection metadata. The developer does not receive your login password or operate these relays. Processing locations and retention follow provider policies and may be outside your country/region; China-mainland-only storage is not promised. Read https://tailscale.com/privacy-policy and https://tailscale.com/terms before enabling. You may decline, disconnect or sign out and continue on LAN. Remove nodes/manage accounts in Tailscale's admin console; signing out does not erase provider records.

Authentication websites and cookies. iOS uses a system authentication session that may reuse browser sign-in state. Depending on the page, region and your choices, provider sites may use essential, analytics or advertising cookies; see https://tailscale.com/cookie-notice and their privacy choices. The developer does not read authentication-page passwords or cookies. Signing out of Chordesk does not automatically clear third-party browser state. LAN remains available without enabling this service.
Service analysis and logs. Chordesk disables diagnostic-log uploading by the embedded network client. This does not eliminate provider-side account, node-coordination, security or operational metadata. Providers may also analyze and improve their services under their policies. Chordesk integrates tsnet networking only, not Aperture content processing or PAM session recording.
Provider deletion and account age. Signing out or deleting a local pairing does not guarantee deletion of provider records. Remove Chordesk nodes through the Tailscale admin console; direct personal-information requests to privacy@tailscale.com. Deleting an entire tailnet may affect other nodes. Provider retention rules apply to logs, backups and legally retained records; immediate erasure is not promised. Meet the optional account service's age requirements before enabling it: Tailscale's current policy does not permit under-16s to create or administer accounts. Guardian guidance and the App Store content rating do not replace this requirement.
Pairing records and node state use the local Keychain; preferences and display-restoration state remain local. Keychain records may outlive uninstall. Forgetting a Mac removes that local pairing, not other devices' access. Stopping service and resetting the Mac pairing key revokes old pairing credentials together. System permissions and in-app controls stop corresponding functions. Local diagnostics are not automatically sent to the developer; redact private content and valid credentials before volunteering a report.
Apple handles distribution, diagnostics and voluntary TestFlight feedback; the developer may see the feedback/diagnostics Apple provides. GitHub Pages hosts the website and may process connection logs. The website stores language locally. The optional questionnaire entry has been removed. Responses previously submitted through Google Forms remain limited to testing invitations and feedback contact; email us to request correction or deletion. Public GitHub issues are not private support. Email and GitHub Issues content is used to respond, test, investigate issues and meet necessary security/legal obligations, not sold or used for advertising profiles. Unnecessary information is no longer retained after those purposes are fulfilled, except legal retention/dispute needs. Contact us for access, correction or deletion. Third parties follow their linked policies, including Apple, GitHub and Google.
You can withdraw optional functionality and exercise applicable privacy rights by contacting the developer; separately manage third-party records with those providers. Protect devices and pairing credentials. Authentication, encryption and permission checks reduce risks but cannot guarantee absolute security. Minors should use the app with guardian guidance and avoid unnecessary personal submissions. This policy does not restrict statutory rights. Material changes will be disclosed and additional consent requested when required.

2026-11-05 经开发者明确批准补充认证网页 Cookie、服务分析、第三方删除与账号年龄说明。本文对应当前官网；已上传的 build 46 内置政策文本不会被网页更新替换，下一二进制应同步。

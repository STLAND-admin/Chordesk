# Mac updates, Keychain recovery and removal

Mac 0.27.1 fixes the native Help-menu uninstaller introduced in 0.27.0 and is available as a [signed, notarized GitHub beta release](https://github.com/STLAND-admin/Chordesk/releases/tag/mac-v0.27.1). iOS 1.31 is unchanged.

## Upgrade failures / 升级后无法登录公网

`Keychain read failed (-25293)` means Keychain authentication failed. It is separate from Screen Recording and Mac control. An old item ACL, changed code identity, or locked login keychain can cause access to fail; the error alone does not prove which condition exists on another Mac.

The 0.26 test package uses an ad hoc identity tied to its code hash. Rebuilding changes that identity. In addition, the host deliberately suppresses background Keychain dialogs; the old login button had no explicit recovery path. The 0.26.1 candidate adds a local, user-initiated recovery flow:

1. Click **授权钥匙串并重试**. A fresh process of the same app requests access to the one Chordesk Tailscale item. Complete any system authentication on that Mac; never send a password to the developer. If macOS offers **Always Allow**, verify that the requester is Chordesk and choose that option to retain approval; a one-time allowance may not carry back to the host process. Credential bytes are not printed or returned to the host.
2. If access still fails, **重新绑定本机公网身份…** explicitly removes that local Tailscale login and requires signing in again. The Tailscale address may change, requiring a new QR pairing. Existing LAN pairing is retained.
3. If macOS also refuses item deletion, quit Chordesk and use the maintenance tool's rebind option, or open Keychain Access, search `dev.chordesk.embedded-tailnet`, and delete only the `node-state-v1` item. Do not reset the entire login keychain. Remove the obsolete node separately in your own Tailscale admin page if needed; local deletion is not remote revocation.

Automatic resume remains noninteractive. The app does not widen item ACLs, switch to plaintext files, or silently create another storage namespace on authentication failure.

## Permissions / 三态权限检查

Use **设置 → 权限 → 重新检查授权状态**. The same signed executable starts a short-lived, read-only process using public preflight APIs; no TCC database is read and no access is granted by checking.

| State / 状态 | Action / 操作 |
| --- | --- |
| 未授权 / Not granted | Use that permission's request button and approve in macOS Settings. |
| 已授权 · 需重启 App / Granted, restart needed | Restart Chordesk; do not repeatedly toggle the system switch. |
| 已授权 · 可用 / Granted and available | Start service once both permissions are ready. |

A new-process check can distinguish a cached denial from a grant that is visible to a fresh process. If it cannot complete, the app explains the uncertainty and offers a manual restart; it does not claim to read the private Settings checkbox. Each newly requested grant keeps a restart barrier for that launch. Restarting the App does not restart the Mac.

## Uninstall / 内嵌卸载

Use **Mac 0.27.1 or later**, then the top menu **Help（帮助）→ 卸载 Chordesk…**. No Terminal or exported tool is needed. A read-only helper preflight runs first; choose a scope and confirm **卸载并退出**:

| Choice | Effect |
| --- | --- |
| App only / 仅卸载 App | Move matching Chordesk apps from standard Applications locations to Trash; retain preferences, pairing, login and permissions. |
| Full / 完整卸载 | Reset only Chordesk's system permissions; delete its listed pairing and Tailscale login records; back up preferences and move App, support data, cache and saved-window state to Trash. |

The app first stops remote control, restores display settings and disconnects its embedded node. A temporary, identically signed helper waits for normal app exit before running the bundled maintenance backend. Failed restoration or a host that remains running prevents removal. No elevated privileges, TCC database edits or global resets are used. Other products and isolated First Run identities are excluded.

**0.27.0 / Cocoa error 3587:** the old helper rejected macOS's `/tmp` alias for `/private/tmp` and hid its actual refusal. Update to 0.27.1. The fix resolves aliases before checking the exact helper directory, adds explicit refusal/timeout reporting, and closes the uninstall sheet before one completed shutdown. App-only removal and same-path reinstall were exercised on the developer's Mac; the new GUI full-cleanup path still requires its own user confirmation.

Files in Trash can be restored. Deleted credentials and reset permission decisions require signing in, pairing and granting access again. Removal does not delete nodes from your Tailscale account; manage those in your own admin console. A failed step reports partial cleanup. A privacy-settings row may remain after its permission decision is reset. Custom installation paths or redirected data paths require manual inspection.

**0.26.1** bundled an exportable command tool; **0.26.0's public test installer did not**. The shell backend remains in [scripts/Chordesk-Maintenance.command](../../scripts/Chordesk-Maintenance.command) for recovery and regression testing. Its interactive fallback supports read-only `--plan`, scoped permission reset, Tailscale rebind and the two uninstall scopes; quit Chordesk first and confirm the exact action.

## Stable releases / 稳定升级与“仍要打开”

For ordinary upgrades, quit and replace the app at the same Applications location; do not uninstall/reset permissions as a routine update step.

The production route is **Developer ID Application signing → Hardened Runtime → Apple notarization → staple the ticket**. Keep the bundle ID and publisher identity stable. Apple Distribution is for iOS/App Store distribution, and does not replace Developer ID for a Mac downloaded from GitHub.

Migrating from ad hoc to Developer ID can require one owner-confirmed permission/Keychain migration. Stable identity helps later versions retain trust; macOS upgrades, revoked permission or organizational policy can still require consent. Signing does not auto-grant Screen Recording or Accessibility. A notarized release should pass normal Gatekeeper assessment without relying on “Open Anyway”; a first-launch confirmation or system permission request can still occur.

On November 3, 2026, **0.27.1's App and final DMG were both accepted by Apple**, with stapled tickets, strict signature verification and Gatekeeper acceptance. The public beta contains the verified installer, checksums, build information and installation notes; an anonymous download matched the local DMG hash. The installed copy also passed signature/ticket/Gatekeeper checks. Historical 0.26.0 downloads remain ad hoc and unnotarized; use the 0.27.1 link above.

Sources: [Apple error definition](https://developer.apple.com/documentation/security/errsecauthfailed), [code requirements and ad hoc identities](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements), [Keychain identity tracking](https://developer.apple.com/library/archive/technotes/tn2206/_index.html), [Developer ID](https://developer.apple.com/developer-id/), [notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution). Permission reset scope follows the installed macOS `tccutil(1)` manual.

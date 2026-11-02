# Mac updates, Keychain recovery and removal

Mac 0.26.1 introduces the recovery controls and maintenance tool below. This is a local candidate until the release record says otherwise. iOS 1.31 is unchanged.

## Upgrade failures / 升级后无法登录公网

`Keychain read failed (-25293)` means Keychain authentication failed. It is separate from Screen Recording and Mac control. An old item ACL, changed code identity, or locked login keychain can cause access to fail; the error alone does not prove which condition exists on another Mac.

The 0.26 test package uses an ad hoc identity tied to its code hash. Rebuilding changes that identity. In addition, the host deliberately suppresses background Keychain dialogs; the old login button had no explicit recovery path. The 0.26.1 candidate adds a local, user-initiated recovery flow:

1. Click **授权钥匙串并重试**. A fresh process of the same app requests access to the one Chordesk Tailscale item. Complete any system authentication on that Mac; never send a password to the developer. If macOS offers **Always Allow**, verify that the requester is Chordesk and choose that option to retain approval; a one-time allowance may not carry back to the host process. Credential bytes are not printed or returned to the host.
2. If access still fails, **重新绑定本机公网身份…** explicitly removes that local Tailscale login and requires signing in again. The Tailscale address may change, requiring a new QR pairing. Existing LAN pairing is retained.
3. If macOS also refuses item deletion, quit Chordesk and use the maintenance tool's rebind option, or open Keychain Access, search `dev.chordesk.embedded-tailnet`, and delete only the `node-state-v1` item. Do not reset the entire login keychain. Remove the obsolete node separately in your own Tailscale admin page if needed; local deletion is not remote revocation.

Automatic resume remains noninteractive. The app does not widen item ACLs, switch to plaintext files, or silently create another storage namespace on authentication failure.

## Maintenance tool / 维护与卸载工具

In 0.26.1: **设置 → 维护与卸载 → 保存卸载与维护工具…**. Source: [Chordesk-Maintenance.command](../scripts/Chordesk-Maintenance.command). It uses the standard macOS shell/tools, with no Xcode or Python requirement. Review and run it only if you trust its source.

First stop service and **quit Chordesk normally** so its display settings can restore. The tool refuses modifications while a host is running. It shows its scope and requires an exact confirmation word for each modifying action.

| Option | Effect |
| --- | --- |
| 1 / `--plan` | Read-only installation/scope check |
| 2 | Reset only `dev.iphoneduo.workbench` privacy decisions; allow the app's permissions again |
| 3 | Remove only this Mac's Chordesk Tailscale login; sign in and pair the new address as needed |
| 4 | Move matching Chordesk apps from standard Applications locations to Trash, retaining data and permissions |
| 5 | Reset this app's permissions; delete its listed pairing/login records; back up preferences and move its apps, support data, cache and saved-window state to Trash |

Credential deletion and permission reset require re-enrollment/re-consent. App/data files in Trash are recoverable. A failed step reports incomplete cleanup; it does not claim all records were removed. Custom installation paths and redirected data directories require manual inspection. The app's entry may still appear in system UI after a permission reset; reset decisions and UI row removal are not the same guarantee.

The tool does not use `sudo`, edit TCC databases, change Gatekeeper/SIP, reset other apps, or recreate the login keychain. Isolated First Run identities are excluded.

## Stable releases / 稳定升级与“仍要打开”

For ordinary upgrades, quit and replace the app at the same Applications location; do not uninstall/reset permissions as a routine update step.

The production route is **Developer ID Application signing → Hardened Runtime → Apple notarization → staple the ticket**. Keep the bundle ID and publisher identity stable. Apple Distribution is for iOS/App Store distribution, and does not replace Developer ID for a Mac downloaded from GitHub.

Migrating from ad hoc to Developer ID can require one owner-confirmed permission/Keychain migration. Stable identity helps later versions retain trust; macOS upgrades, revoked permission or organizational policy can still require consent. Signing does not auto-grant Screen Recording or Accessibility. A notarized release should pass normal Gatekeeper assessment without relying on “Open Anyway”; a first-launch confirmation or system permission request can still occur.

Developer ID creation/notarization was previously paused by the owner. The candidate remains explicitly unnotarized until that work is authorized and actually passes verification.

Sources: [Apple error definition](https://developer.apple.com/documentation/security/errsecauthfailed), [code requirements and ad hoc identities](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements), [Keychain identity tracking](https://developer.apple.com/library/archive/technotes/tn2206/_index.html), [Developer ID](https://developer.apple.com/developer-id/), [notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution). Permission reset scope follows the installed macOS `tccutil(1)` manual.

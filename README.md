<p align="center"><img src="Branding/Chordesk-transparent.svg" width="150" alt="Chordesk"></p>

# Chordesk

English · [简体中文](README.zh-CN.md)

**Play a chord. Control your desktop.**

A remote desktop app designed for iPhone Duo. Use your thumbs for touch and typing on the front, while fingers on the back switch interaction modes like holding a chord. Includes an **iOS client** and a **Mac host**.

[Concept & 3D demo](https://stland-admin.github.io/Chordesk-site/) · [Operation guide](OPERATION-GUIDE.md) · [Roadmap](ROADMAP.md) · [Changes since TestFlight](CHANGELOG.md)

The website supports Chinese and English. Detailed operation guides are currently in Chinese.

## Install

### Mac

Download the [Mac 0.25.0 test release](https://github.com/STLAND-admin/Chordesk/releases/tag/mac-v0.25.0-test), open the DMG, and drag Chordesk into Applications.

- Apple Silicon, macOS 15.2 or later. This test build is **not notarized**; follow macOS prompts to allow it on first launch. [Installation guide](docs/MAC-PEER-TEST.txt).
- Approve screen recording and control separately, following each macOS reopen prompt. Start service after both permissions are effective; the built-in display is selected by default. Closing the window keeps the service running in the menu bar.
- The source repository and test releases are public. You can share the download link directly with testers.

### iPhone / iPhone Duo

[Install the TestFlight beta](https://testflight.apple.com/join/WZDXKgvg). Install TestFlight on your iPhone, then open the invitation. Use the Mac host above on the same local network. Regular iPhones use on-screen mode controls; Duo adds rear chords. Availability and device conditions are shown by Apple.

Building from source is also available:

1. Install Xcode 27.1 or later and Go 1.27.1+. Run `./scripts/build-tailnet.sh`, then open `iPhoneDuoDemo.xcodeproj` ([build details](docs/DEVELOPMENT.md)).
2. Select the `iPhoneDuoDemo` target. Under Signing & Capabilities, choose your own Team and a Bundle Identifier you can sign.
3. Connect Duo over USB, enable Developer Mode and trust the Mac as prompted, then select the device and run. A free Personal Team can be used for testing, but requires periodic re-signing.

Version 1.30/build 39 is awaiting Beta Review; the existing invitation still serves the approved build until the update is enabled. Keep the same Bundle Identifier and Team when updating a source-built installation. iOS **1.22.1 / build 28** has passed external TestFlight Beta App Review; this is not an App Store release. [Release record](docs/IOS-RELEASE-1.22.md).

## How it works

Connect both devices to the same local network. Scan the Mac's QR code once, then reconnect from the saved computer list on your phone. Multiple Macs can be remembered, with one connected at a time. If a Mac's IP address changes, scan its QR code again to update the address.

| Gesture or control | Action |
| --- | --- |
| One finger on the front | Direct touch by default; hold and drag to select text |
| Hold one finger on the back + swipe two fingers up/down on the front | Open/close Mission Control |
| Hold one finger on the back + swipe two fingers left/right on the front | Next/previous Mac desktop (Space) |
| Hold two fingers on the back | Temporarily switch the front to trackpad mode; release to return |
| Gray buttons along the right edge | Menu, interaction mode, display selection, and keyboard in one column |

Switching Spaces also requires **System Events automation permission** in the Mac host's Settings → Desktop switching (设置 → 桌面切换), plus the macOS Control + Left/Right shortcuts. This optional permission is separate from basic remote control.

The rear activation area can be moved and resized. Text entry supports the iPhone's system and third-party keyboards. Other iPhones use the on-screen mode switch. Two targeted UI checks passed on an iPhone 18 Pro / iOS 27.0 simulator; regular-iPhone hardware compatibility remains under initial testing.

## Roadmap

- [x] **Cross-network remote control — Mac test release available; iOS update in review:** embedded Tailscale connects both devices through the user’s private network, without an extra app or a self-hosted server. Picture and touch control over cellular are confirmed on the current device pair. Mac 0.25.0 is published; iOS 1.30 is awaiting Beta Review.
- [ ] **P1 — Background energy:** measure capture, JPEG encoding and keep-alive work without a viewer; capture on demand while keeping a low-cost listener available.
- [ ] **Keyboard visibility:** explore a Liquid Glass preview so remote input fields remain visible while typing.
- [ ] **RDP and client-side rendering:** validate Mac current-session feasibility and compare clarity, bandwidth and latency.
- [ ] **Regular-iPhone hardware testing:** validate on-screen controls, keyboards, layouts and reconnection.

See the [public roadmap](ROADMAP.md) for completed work, remaining tests and release preparation. A new TestFlight build is in Beta Review while formal App Store and mainland filing preparation continue.

## Current scope

- **iOS 1.30 /39 is awaiting Beta Review; Mac 0.25.0 /38 is a public unnotarized test release.** Adds IPv6 pairing and current privacy disclosure. [Release and validation](docs/VALIDATION-1.30.md).

- Development **1.29** expands the trackpad across keyboard letterboxing, adds three editable rail shortcuts, groups settings into four categories, and simplifies the in-app guide. [Quick guide (中文)](OPERATION-GUIDE.md) · [Validation and device feedback](docs/VALIDATION-1.29.md).

- iOS **1.22.1 / build 28** separates Forget from Connect, pins rear-contact lights above the desktop, and adds bounded capture recovery. The idle rear-control fix still needs device confirmation. The complete guide and default iPhone keyboard remain. Mac stays **0.18.1 / build 26**. [Current validation](docs/VALIDATION-1.22.1.md); [guide recording plan](docs/GUIDE-RECORDING.md).
- **Public iOS remains LAN-only 1.22.1; 1.30/build 39 has been uploaded and submitted for Beta Review. Mac 0.25.0 is now available as an unnotarized test release.** Development versions iOS **1.29 / build 38** and Mac **0.24.0 / build 37** include embedded Tailscale: LAN needs no login; cross-network mode uses each owner’s private Tailscale account. No additional Tailscale app or system VPN is installed. The user confirmed picture and touch control over cellular with 1.23.2 / 0.19.0. Broader network and long-session testing remain; Mac 0.25.0 is public and iOS 1.30 is awaiting Beta Review. [Setup and limits](docs/TAILSCALE.md).
- Direct-touch and trackpad scrolling share adjustable momentum in development builds: **Settings → Unified scroll inertia**, from **0 (off) to 2**, default **1**. A new touch stops momentum; both ends need the update. [Implementation and validation](docs/VALIDATION-1.24.md).
- Development iOS 1.25 adds optional aspect-preserving keyboard avoidance and a trackpad lift fix; Mac 0.20.1 keeps the listener while the selected display is temporarily offline. Version 1.26 adds authenticated, read-only service reachability checks in the paired-Mac list. The user confirmed keyboard animation, the keyboard button position, both pointer modes with the keyboard visible, H.264, and automatic reconnection over cellular in 1.27. The user clarified that open-lid lock-screen access works; closing the lid causes freezing. Mac 0.22.1 adds an AC-only authenticated-viewer network activity request, which did not resolve closed-lid freezing on the tested Mac; the no-input control also failed. [1.26 validation](docs/VALIDATION-1.26.md). [Validation](docs/VALIDATION-1.25.md) · [Wake and latency audit](docs/HOST-WAKE-LATENCY.md).
- Development 1.27 adds automatic authenticated LAN/Tailscale route selection, animated keyboard avoidance with the keyboard button just above the keyboard, and an optional top-left statistics overlay. H.264 hardware encoding/decoding is preferred; JPEG remains a fallback. Default **Efficient · 15 fps** targets up to 1280 pixels and **1.5 Mbps H.264** (JPEG fallback 65% quality). Saved quality choices are retained; actual fps and bitrate vary. RTT measures an application round trip, not touch-to-photon latency. [1.27 validation](docs/VALIDATION-1.27.md).
- Development 1.28 makes the rear surface black except during active-region editing, adds selectable H.264 / H.265 (HEVC) with hardware fallback, and prioritizes Tailscale with a 350 ms grace for a ready LAN fallback. New hosts reuse the verified connection rather than handshaking twice. [Validation and remaining device checks](docs/VALIDATION-1.28.md).
- Development Mac 0.23.1 has separate screen-recording and control permission buttons. After each grant, follow macOS’s quit/reopen prompt (or use the manual restart button), then continue the remaining step. Both permissions must be effective before service starts; there is no automatic permission sequence or restart countdown. [Validation](docs/VALIDATION-0.23.1.md).
- Display scaling targets **1600 × 900 logical resolution**, using existing safe display modes. Some custom HiDPI modes still need the optional BetterDisplay fallback. [Dependencies](docs/DEPENDENCIES.md).
- Development 1.29 / Mac 0.24.0 temporarily disables microphone capture, forwarding and routing, including saved auto-start preferences. Published older builds still contain the optional feature. [Historical audio design](docs/REMOTE-MICROPHONE.md).
- Rear-screen interaction uses the experimental camera accessory path. Camera frames are not displayed, saved, or transmitted. This does not establish a general-purpose rear-screen API or App Store approval.

[First-run checklist · Mac + iOS](docs/FIRST-RUN-CHECKLIST.md) · [Development & builds](docs/DEVELOPMENT.md) · [Development history](docs/DEVELOPMENT-HISTORY.md) · [Brand assets](Branding/README.md)

## License

[CC BY-NC-SA 4.0](LICENSE): attribution, noncommercial use, and ShareAlike. Applies to project-owned code, docs and assets; third-party licenses remain unchanged. [Scope](NOTICE.md).

Made by STLAND

<p align="center"><img src="Branding/Chordesk-transparent.svg" width="150" alt="Chordesk"></p>

# Chordesk

English · [简体中文](README.zh-CN.md)

**Play a chord. Control your desktop.**

A remote desktop app designed for iPhone Duo. Use your thumbs for touch and typing on the front, while fingers on the back switch interaction modes like holding a chord. Includes an **iOS client** and a **Mac host**.

[Concept & 3D demo](https://stland-admin.github.io/Chordesk-site/) · [Operation guide](OPERATION-GUIDE.md) · [Roadmap](ROADMAP.md)

The website supports Chinese and English. Detailed operation guides are currently in Chinese.

## Install

### Mac

Download the [Mac 0.18.1 test release](https://github.com/STLAND-admin/Chordesk/releases/tag/mac-v0.18.1-test), open the DMG, and drag Chordesk into Applications.

- Apple Silicon, macOS 15.2 or later. This test build is **not notarized**; follow macOS prompts to allow it on first launch. [Installation guide](docs/MAC-PEER-TEST.txt).
- Click **Start service (开始服务)** and follow the screen recording and control permission setup. Once permission checks pass, the app restarts once and starts sharing the built-in display by default. Closing the window keeps the service running in the menu bar.
- The source repository and test releases are public. You can share the download link directly with testers.

### iPhone Duo

Currently installed by **building locally in Xcode**. A TestFlight build is not available yet.

1. Install Xcode 27.1 or later and open `iPhoneDuoDemo.xcodeproj`.
2. Select the `iPhoneDuoDemo` target. Under Signing & Capabilities, choose your own Team and a Bundle Identifier you can sign.
3. Connect Duo over USB, enable Developer Mode and trust the Mac as prompted, then select the device and run. A free Personal Team can be used for testing, but requires periodic re-signing.

Keep the same Bundle Identifier and Team when updating an existing installation. Apple Developer Program enrollment is complete. iOS **1.22 / build 27** is in release preparation; there is no public TestFlight or App Store build yet. TestFlight is optional before App Store submission. [Distribution plan](docs/DISTRIBUTION.md).

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

The rear activation area can be moved and resized. Text entry supports the iPhone's system and third-party keyboards. Other iPhones have an on-screen mode switch, but have not yet been tested.

## Roadmap

- [ ] **Keyboard visibility first:** explore a Liquid Glass preview above the keyboard so remote input fields, such as those in Codex, remain visible while typing.
- [ ] **RDP and client-side rendering:** validate Mac host feasibility and compare clarity, bandwidth, and latency before deciding whether to replace the current image transport.
- [ ] **Internet access and non-Duo testing:** validate remote networks, reconnection, and on-screen controls and layouts on other iPhones.

These are planned tasks. See the [public roadmap](ROADMAP.md) for details and acceptance criteria.

## Current scope

- iOS **1.22.1 / build 28** separates Forget from Connect, pins rear-contact lights above the desktop, and adds bounded capture recovery. The idle rear-control fix still needs device confirmation. The complete guide and default iPhone keyboard remain. Mac stays **0.18.1 / build 26**. [Current validation](docs/VALIDATION-1.22.1.md); [guide recording plan](docs/GUIDE-RECORDING.md).
- **Local network only**, with TLS pairing. Internet access, accounts, and relay services are not implemented. [Network plan](PUBLIC-NETWORK-PLAN.md).
- Display scaling targets **1600 × 900 logical resolution**, using existing safe display modes. Some custom HiDPI modes still need the optional BetterDisplay fallback. [Dependencies](docs/DEPENDENCIES.md).
- Microphone forwarding is off by default. Using Duo as a microphone for Mac apps currently requires a virtual audio device; an integrated driver is not implemented. [Audio details](docs/REMOTE-MICROPHONE.md).
- Rear-screen interaction uses the experimental camera accessory path. Camera frames are not displayed, saved, or transmitted. This does not establish a general-purpose rear-screen API or App Store approval.

[Development & builds](docs/DEVELOPMENT.md) · [Development history](docs/DEVELOPMENT-HISTORY.md) · [Brand assets](Branding/README.md)

## License

[CC BY-NC-SA 4.0](LICENSE): attribution, noncommercial use, and ShareAlike. Applies to project-owned code, docs and assets; third-party licenses remain unchanged. [Scope](NOTICE.md).

Made by STLAND

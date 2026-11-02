<p align="center"><img src="Branding/Chordesk-transparent.svg" width="150" alt="Chordesk"></p>

# Chordesk

English · [简体中文](README.zh-CN.md)

**Play a chord. Control your desktop.**

An iPhone remote desktop client and a Mac host. Use your thumbs for touch and typing, and Duo's rear screen for chord-like mode switches. Other iPhones use on-screen controls.

[Website & demo](https://stland-admin.github.io/Chordesk-site/) · [Operation guide](OPERATION-GUIDE.md) · [Roadmap](ROADMAP.md)

## Install

| Platform | Public release |
| --- | --- |
| iPhone / iPhone Duo | [TestFlight 1.30 (39)](https://testflight.apple.com/join/WZDXKgvg) |
| Apple Silicon Mac · macOS 15.2+ | [Mac 0.26.0 test release](https://github.com/STLAND-admin/Chordesk/releases/tag/mac-v0.26.0-test) |

Open the Mac DMG and drag Chordesk into Applications. This Mac test release is **not notarized**; follow macOS Privacy & Security prompts only if you trust the source. Approve screen recording and Mac control separately; after each permission, reopen the app if macOS asks. Start service once both are effective. [Installation details](docs/MAC-PEER-TEST.txt).

Scan the Mac QR code once, then reconnect from your paired computers. LAN needs no account. For cross-network use, sign in to the same personal Tailscale network inside both Chordesk apps; no separate Tailscale app is required. Multiple Macs can be remembered. [Network setup and limits](docs/TAILSCALE.md).

## Controls

| Gesture | Mac action |
| --- | --- |
| Front tap / hold and drag | Click / select text |
| One rear finger + two front fingers up/down | Open/close Mission Control |
| One rear finger + two front fingers left/right | Next/previous Space |
| Two rear fingers held | Temporarily switch to trackpad; lift to restore |
| Right-side buttons | Menu, mode, display, overview and keyboard |

Spaces require optional System Events permission and enabled macOS Control + arrow shortcuts. Native and third-party iPhone keyboards are supported. [Full guide](OPERATION-GUIDE.md).

## Latest update

**Mac 0.26.0 (39) is released; iOS 1.31 (40) is waiting for TestFlight Beta App Review.** Immediate rear-contact default; independent 480p–2160p, 15–120 fps and target bitrate controls; HEVC default with fallback; bounded connection test and recommendations; clearer buttons and permission steps; drag-to-install DMG; screen capture only while an authenticated viewer is connected. Existing explicitly saved preferences are retained. The iPhone invitation still provides 1.30 until 1.31 is approved and enabled. Independent stream controls and the new rear-contact default require iOS 1.31; existing 1.30 clients can still connect to the Mac host.

Audio is disabled. Closed-lid/system-sleep wake is not guaranteed. IPv4/IPv6 pairing is supported; IPv6-only/NAT64 hardware, ordinary-iPhone hardware and broader networks still need testing. Actual FPS/bitrate depends on hardware and content; HUD RTT is not end-to-end interaction latency. Duo rear input uses Apple's camera accessory API, with camera frames discarded. App Store review remains separate from TestFlight.

## Develop and contribute

[Xcode / Go / Mac build](docs/DEVELOPMENT.md) · [First-run checks](docs/FIRST-RUN-CHECKLIST.md) · [Distribution](docs/DISTRIBUTION.md) · [Documentation index](docs/README.md) · [Development & validation history](docs/DEVELOPMENT-HISTORY.md)

Build the iOS client from `iPhoneDuoDemo.xcodeproj` using your own Team. Keep the original app identity when updating an existing installation. The concept website is maintained separately in [Chordesk-site](https://github.com/STLAND-admin/Chordesk-site).

Project-owned code, documentation and artwork: **[CC BY-NC-SA 4.0](LICENSE)**. Commercial use is not granted. Third-party licenses remain applicable; see [NOTICE](NOTICE.md). Privacy: [English](https://stland-admin.github.io/Chordesk-site/privacy.html?lang=en) · [中文](https://stland-admin.github.io/Chordesk-site/privacy.html?lang=zh). Feedback: styj@zju.edu.cn.

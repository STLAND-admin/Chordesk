# Chordesk changes since the first TestFlight beta

[简体中文](CHANGELOG.zh-CN.md) · [Operation guide](OPERATION-GUIDE.md) · [First-run checklist](../developer/FIRST-RUN-CHECKLIST.md)

Baseline: the first public TestFlight **iOS 1.22.1 /28**, with **Mac 0.18.1 /26**. Mac **0.27.1 /42** is available, signed and notarized. iOS **1.31 /40** passed Beta App Review and was enabled for the existing groups on November 3, 2026, with testers notified. The original public invitation is unchanged. No formal App Store submission has been made.

## Mac 0.27.1 · Signed and notarized beta

- Stable Developer ID signatures, hardened runtime and stapled Apple notarization for both app and DMG.
- Three-state permission checks, explicit local Keychain recovery and a native Help-menu uninstaller; fixes temporary-path alias rejection and the uninstall shutdown stall.
- Source projects and tests grouped under ProjectFiles, with compatible bundle IDs and pairing namespaces preserved.
- No new iOS features since the already uploaded 1.31 /40; internal project renaming only. Existing review was not withdrawn or duplicated.

## 1.31 / Mac 0.26.0 · Public beta

- Keep the service reachable without capturing. Screen capture and encoding start for an authenticated connected viewer and stop on disconnect; presence checks do not start capture. Active remote sessions retain the system privacy indicator.
- Independent resolution (480p, 720p, 1080p, 1440p, 2160p), FPS ceiling (15–120) and target bitrate. New preferences default to 720p /15 fps /1.5 Mbps and HEVC; saved selections and H.264/JPEG fallback remain.
- Bounded Mac-to-phone route sample (up to 512 KiB test payload) recommends bitrate/FPS for manual application. It is not an external ISP speed test or automatic quality controller.
- Two rear contacts immediately activate temporary trackpad mode; lift restores the prior mode. Long press remains selectable and saved preferences are retained.
- Clear Tailscale action buttons, restart guidance beside each permission, and bilingual drag-to-Applications DMG layout without a visible readme file.
- Remove legacy Mac dual-screen and single-window experiments. Keep the concept website and shared components used on iPhone; consolidate old validation/distribution notes into [development history](../developer/DEVELOPMENT-HISTORY.md).

## 1.30 / Mac 0.25.0 · Public beta

- Embedded Tailscale, IPv4/IPv6 local addressing, keyboard/touch improvements, disabled audio, and updated privacy materials reached public testing.
- iOS 1.30 /39 was approved and enabled for the three existing external groups. Mac 0.25.0 /38 offers an unnotarized test DMG. This is separate from formal App Store release.

## Development 1.29 / Mac 0.24.0 interface update

- Trackpad input covers black margins above the keyboard, excluding the scrollable right rail. Absolute touch still maps to the picture.
- Display switching, pointer-mode switching and Mission Control can each be shown or hidden. Four setting categories replace the long action menu.
- The guide uses 0/1/2-rear-finger action tables. Diagnostics controls HUD visibility and corner placement.
- Audio forwarding is temporarily disabled on both ends, including saved auto-start preferences. About uses a transparent monochrome STLAND wordmark.
- The user confirmed black-margin control, shortcuts and menu short taps on Duo. The existing black-background app icons are retained. [Validation](../developer/DEVELOPMENT-HISTORY.md#archive-validation-1-29).

## Connectivity

- Embedded Tailscale on both ends: no separate Tailscale app or system VPN. LAN requires no account; cross-network access uses each owner's private network.
- In-app system authentication, device enrollment confirmation, resume/check-status controls, and bounded background time for completing authentication. Fixed form-row taps firing several actions and opening the website/download flow.
- Mac LAN and authorized Tailscale listeners can run together. The phone supports Automatic, LAN only, and Tailscale only.
- QR invitations and authenticated host updates save both addresses under the same host identity. Names alone never merge computers.
- Automatic connection probes both paths concurrently. Version 1.28 prefers Tailscale; a ready LAN waits at most another 350 ms before falling back. If Tailscale has already failed, LAN is used immediately.
- New hosts reuse the verified winning transport, avoiding the old probe–close–reconnect handshake. Read-only online checks cannot become remote sessions, and another phone's active session is not taken over.
- Foreground disconnections release input and retry route selection up to three times. Manual disconnect/backgrounding cancels retries; this is reconnection, not seamless migration.
- Saved-computer status includes reachability, check time, unavailable capture/session, and another connected device. A timeout does not prove the Mac is off.
- Correct LAN/Tailscale labels and diagnostic timings for route verification, transport reuse, and the first decoded frame.

## Video and performance visibility

- New-install default: **Efficient, 15 fps, maximum dimension 1280**; saved choices remain. Requested fps is not a delivery guarantee.
- Hardware **H.264** encoding/decoding replaces JPEG as the preferred path, with real-time encoding, no frame reordering, low-latency rate control, and JPEG fallback.
- Version 1.28 adds manual **H.265 / HEVC** selection. Unsupported/failed hardware or older peers fall back through HEVC → H.264 → JPEG; the HUD reports the actual format.
- Efficient targets start at **1.5 Mbps H.264 / 1.125 Mbps HEVC**. HEVC targets 75% of the same H.264 quality preset's budget. These are encoder settings, not equal-quality guarantees or strict bandwidth caps. HEVC can also help constrained networks.
- Bounded video writes, frame dropping under backpressure, sequence/keyframe recovery, and packet/pixel validation. TCP/system buffers can still add latency.
- Optional top-left HUD: route, codec, image dimensions, received fps, video payload Mbps, application RTT. RTT is not touch-to-photon latency.
- AV1 is not implemented; RDP/client-side rendering remains exploratory.

## Input, keyboard, and rear chords

- Direct-touch single-finger and trackpad two-finger scrolling share momentum, with a **0–2 coefficient, default 1**; zero disables it. Mac performs deceleration, with cancellation on new touch, mode/menu changes, disconnect, or revoked control.
- Fixed staggered two-finger lift being mistaken for a cancelled scroll. Hardware feel still needs confirmation; diagnostics include lift velocity without recording typed content.
- Optional, default-on keyboard avoidance fits the whole desktop above the keyboard without changing aspect ratio or the Mac resolution. Hiding the keyboard restores the workspace.
- Keyboard-driven resizing follows system animations. The keyboard button and Ctrl/Cmd/Option dock stay just above the keyboard instead of jumping upward.
- Fixed direct-touch/trackpad input availability and mapping while the keyboard is visible; layout changes release old contacts.
- Normal rear content is black, without persistent labels or shading. The active-region outline appears only while editing. Touch reception and the camera accessory session remain; black content does not mean the hardware is powered off.
- In-app and repository guides document current network, codec, keyboard, and gesture behavior.

## Mac onboarding and recovery

- Version 0.23.1 replaces the earlier automatic sequence with two explicit permission buttons. Grant screen recording, follow the system quit/reopen prompt, then request control and reopen again as prompted. A manual restart is available even after a partial grant; service still requires all permissions. Polling never prompts or schedules restarts.
- Build 36 opens Screen Recording settings when a request still reports no access, with the current app name and a manual navigation fallback. Opening Settings never counts as permission granted.
- Fixed exit/relaunch cleanup ordering; the replacement process waits for the old process to exit before continuing service.
- Temporarily missing displays preserve the listener and trigger bounded recovery of the original display. No silent switch to another screen or restoration of revoked permissions.
- New sessions without fresh frames can rebuild the original capture stream; session/power boundaries reset the app's own input source without global key injection or password automation.
- An AC-only, authenticated-viewer network activity request was tried for closed-lid access. **It did not resolve the reported freeze**; the no-password-input control also failed. Open-lid lock-screen access is reported working.
- Isolated **Mac and iOS First Run** builds provide new app identities, empty settings, pairing and Tailscale stores while preserving everyday installations. The Mac QA app now carries its version in its name and runs outside protected user folders; Documents access is not a prerequisite for basic remote control.

## Version index

| iOS | Mac | Main changes |
| --- | --- | --- |
| 1.23 / 29 | 0.19.0 / 27 | Embedded Tailscale, sequential onboarding, optional service disclosures |
| 1.23.1 / 30 | 0.19.0 / 27 | In-app authentication and enrollment continuation |
| 1.23.2 / 31 | 0.19.0 / 27 | Independent form taps; cellular picture/touch confirmed |
| 1.23.3 / 32 | 0.19.1 / 28 | Network labels, complete-permission restart, exit fix; efficient default |
| 1.24 / 33 | 0.20.0 / 29 | Unified adjustable scroll momentum |
| 1.25 / 34 | 0.20.1 / 30 | Optional keyboard avoidance, lift fix, display recovery |
| 1.26 / 35 | 0.21.0 / 31 | Authenticated presence checks and session input cleanup |
| 1.27 / 36 | 0.22.0 / 32 | Automatic routing, H.264, HUD, keyboard animation/input fixes |
| 1.27 / 36 | 0.22.1 / 33 | Closed-lid network activity experiment; still failing |
| 1.28 / 37 | 0.23.0 / 34 | Black rear content, HEVC, Tailscale preference and connection reuse |
| 1.28 / 37 | 0.23.1 / 35–36 | Manual permission restarts; versioned QA outside Documents; Settings fallback when screen access remains denied |

## Validation and remaining work

User-confirmed paths include cellular picture/touch through embedded Tailscale, service status, 1.27 keyboard animation and dock placement, both pointer modes with the keyboard visible, H.264, and automatic cellular reconnection.

Version 1.28 passed 165 full logic/TLS tests, 23 final focused checks, and two simulator UI checks. Generated-image hardware H.264/HEVC round trips, codec switching and encrypted transport reuse passed locally. These are not measurements of Duo HEVC quality, public-network connection improvement, energy savings, or every supported device.

Before release: complete first-run and actual-download checks, trackpad momentum confirmation, 1.28 device checks, cold-start/long-session network tests, performance/energy comparison, and regular-iPhone hardware tests. Closed-lid access and capture-on-demand energy work remain unresolved. Bundled cryptography and optional third-party identity services require updated export-compliance and privacy review; do not reuse the first beta's system-only encryption declaration.

[1.23 validation](../developer/DEVELOPMENT-HISTORY.md#archive-validation-1-23) · [1.24](../developer/DEVELOPMENT-HISTORY.md#archive-validation-1-24) · [1.25](../developer/DEVELOPMENT-HISTORY.md#archive-validation-1-25) · [1.26](../developer/DEVELOPMENT-HISTORY.md#archive-validation-1-26) · [1.27](../developer/DEVELOPMENT-HISTORY.md#archive-validation-1-27) · [1.28](../developer/DEVELOPMENT-HISTORY.md#archive-validation-1-28) · [Roadmap](../developer/ROADMAP.md)

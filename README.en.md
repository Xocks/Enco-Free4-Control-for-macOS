# Enco Free4 Control for macOS · Enco Free4 控制

[简体中文](README.md) | **English**

A native macOS menu bar controller for the **standard edition of OPPO Enco Free4**. It provides a Chinese menu bar panel and a full settings window. Core controls work offline. Only product ID `068C10` is accepted; Dynaudio editions and other models are outside the supported scope.

> **Preview release.** Core settings have passed device readback checks, but full P0 acceptance is incomplete. Real sleep/wake, single-bud and charging scenarios, Bluetooth off/on, denied permission, and full-workday stability still need validation. A confirmed ANC level is not an acoustic measurement.

[Downloads](https://github.com/Xocks/Enco-Free4-Control-for-macOS/releases) · [Feature status (Chinese)](docs/Feature_Status.md) · [Acceptance (Chinese)](docs/Acceptance.md) · [Privacy](PRIVACY.md)

## Features

| Priority | Features | Status |
|---|---|---|
| P0 | Standard-edition identity and binding, separate system/control status, connection and bounded retries | Implemented; basic connection verified; full stability acceptance pending |
| P0 | Left/right/case battery and charging status | Device reports only; unknown/stale data are explicit; charging and single-bud behavior need checking |
| P0 | Off, ANC, transparency, and incoming state updates | ACK plus correlated query confirmation; basic mode readback verified |
| P1 | Deep, medium, light, smart, adaptive ANC, confirmed-level memory | Readback verified; audible differences need checking |
| P1 | Standard-edition presets, custom EQ create/edit/delete, hold-mode cycle | Readback verified; one preset depends on firmware version |
| P1 | Everyday gestures, wear detection, multipoint switch and device list | Some readback checks passed; physical actions and complex scenarios pending |
| P1 | Local preferences, optional launch at login, diagnostic export | Login launch defaults off; a complete login cycle remains untested |
| P2 | Earbud spatial sound, low latency, prompt volume | Changes and restoration confirmed by query; no measured latency or spatial-effect claim |
| P2 | Read existing Golden Sound, ear-scan data and prompt presets | Read verified; writing and complete test flows deferred |
| P2 | **Prompt content/timbre replacement**, find earbuds, advanced switching, backup/restore | Deferred with documented prerequisites |
| P3 | Firmware updates, AI, accounts and phone-only services | Research only; firmware flashing is not implemented |

## Installation

Requires Apple Silicon and macOS 14 or newer. The app UI is currently Chinese; this English page covers installation and feature limitations.

1. Download the DMG from [Releases](https://github.com/Xocks/Enco-Free4-Control-for-macOS/releases), then drag **Enco Free4 控制.app** into Applications.
2. Pair and connect Enco Free4 in macOS Bluetooth settings. Open the app and allow Bluetooth access.
3. Select the earbuds. Settings become available only after the standard-edition product ID is confirmed.
4. Use the menu bar for daily noise controls, or open the full settings window for levels, EQ and gestures.
5. Wait for device confirmation. Rejected or timed-out operations retain the last reported state.

The app uses ad-hoc signing and is not notarized with a Developer ID. If macOS blocks opening it, follow the system Privacy & Security instructions. Quit the previous version and **replace the entire app bundle** when updating. Binding and preferences remain in the local app container.

## Behavior

- “—” means no usable battery value. Disconnected or expired data are marked stale; case battery is never inferred.
- System Bluetooth and the control channel have separate status. The control channel does not replace the system audio connection.
- A write requires an ACK and a matching response to a later query. Asynchronous settings are re-queried within a deadline; sending a packet alone never counts as success.
- Manual control disconnection suppresses immediate reconnection during the current system connection.
- Earbud spatial sound can conflict with high-quality mode. macOS negotiates the actual audio codec.
- Prompt **volume** and prompt **content/timbre** are separate capabilities. Content replacement is not implemented.

## Build

Install Apple Command Line Tools, then run from the project root:

```sh
Scripts/test-protocol.sh
Scripts/build-app.sh
Scripts/build-dmg.sh 0.1.0
```

Artifacts are written to `dist/`. There are no third-party Swift package dependencies. The app does not require Android, JADX, Wireshark, an account or network access at runtime. The standalone protocol script works without XCTest; a full Xcode setup may also run `swift test`.

## Privacy and feedback

This public snapshot excludes private commit history, personal email, local paths, Bluetooth addresses, raw acceptance logs, personal presets, phone APKs and diagnostic exports. The app does not automatically upload diagnostics. Redact personal information before filing issues; see [Privacy](PRIVACY.md).

## Credits and license

Based on [OPPO Pods for macOS](https://github.com/ssigpoy/OPPO-Pods-for-macOS), with protocol references from [EncoFree4Menu](https://github.com/wang29a/EncoFree4Menu) and [QuickBuds](https://github.com/spizganed/QuickBuds). Pinned revisions and reuse details are in [Third-party notices](THIRD_PARTY_NOTICES.md). Licensed under [GPL-3.0](LICENSE).

This is an unofficial community tool, not affiliated with OPPO or HeyMelody.

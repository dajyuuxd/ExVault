# ExVault v1.0.0 ⚡

ExVault turns your vintage iOS devices (such as an old **iPhone 5s on iOS 12.5.8**) into a private, high-performance, self-hosted offline LAN cloud vault.

---

## 🌟 Highlights & Features

- **Zero External Dependencies**: 100% native Swift 5 and POSIX sockets. Zero CocoaPods, zero SPM dependencies in the iOS target, zero external JS libraries or CDNs.
- **Engineered for Legacy Devices**: Tailored for **iOS 12.0+** with 64-bit arm64 architecture (iPhone 5s / iPad Air 1 / iPad mini 2 and newer).
- **Strict RAM Budget (<80 MB)**: All HTTP uploads, downloads, range queries, and compression streams use 64KB rolling buffers to avoid jetsam watchdog termination on 1GB devices.
- **On-the-Fly DEFLATE Compression**: Automatically detects compressible formats (text, source code, JSON, logs) and streams compressed data with Apple's native `Compression` framework.
- **HTTP Range 206 Streaming**: Full support for video and audio scrubbing without requiring heavy on-device transcoding.
- **Full-Featured Vanilla Web UI**:
  - Bilingual localization (**Vietnamese** & **English**).
  - Dual themes: Light Cream (`#f5f0e1`) & Deep Dark (`#111111`).
  - List & Grid view (S / M / L).
  - Multi-select (Shift / Ctrl / Cmd + A), drag-and-drop uploads, inline renaming (F2), folder hierarchy, tags, trash bin with restoration.
  - Multi-file on-the-fly streaming ZIP downloads.
  - Media previewer for photos (pan & zoom), video/audio, PDF, and syntax-aware text files.
- **Always-On KeepAlive Engine**:
  - In-memory silent audio playback loop prevents iOS background suspension.
  - One-tap **[Dim screen]** button drops screen brightness to 0 with a pure black overlay to conserve battery and eliminate OLED/LCD burn-in.
- **SQLite3 WAL Crash Recovery**: ACID metadata storage with automated reconciliation of interrupted uploads upon reboot.

---

## 📦 Release Assets

- **`ExVault-unsigned.ipa`**: The iOS application bundle for iOS 12.0+ devices.
- **`exvault-cli`**: Standalone executable CLI server for macOS.

---

## 📲 Installation Guide

### iOS App (`ExVault-unsigned.ipa`)
1. Download `ExVault-unsigned.ipa` on your computer or device.
2. Install via your preferred tool on your jailbroken / sideloaded device:
   - **TrollStore** (iOS 14.0 - 17.0): Open in TrollStore directly.
   - **AltStore / Sideloadly**: Sideload with your Apple ID.
   - **Filza / AppSync Unified** (iOS 12.0 - 14.x jailbroken): Install `AppSync Unified` from Karen's Repo (`cydia.akemi.ai`), open the `.ipa` in Filza and tap **Install**.
   - **Terminal / SSH**: Run `ipainstaller ExVault-unsigned.ipa`.
3. Open **ExVault** on your iPhone, connect to local Wi-Fi, and plug into a charger.
4. Note the URL and temporary credentials shown on the screen (e.g. `http://192.168.1.15:8080`).
5. Open the URL in any modern browser on your PC or phone and enjoy your private local cloud!

### macOS CLI (`exvault-cli`)
```bash
chmod +x exvault-cli
./exvault-cli --port 8080 --data-dir ~/ExVaultData --web-root ./Web
```

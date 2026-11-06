# ExVault v1.0.2 ⚡ — Offline LAN Private Cloud Storage

> **Transform legacy iOS devices (iPhone 5s / iOS 12.0+) into a high-performance, private, self-hosted offline LAN cloud storage vault — 100% offline, zero Internet required, zero external dependencies.**

---

## 🆕 What's New in v1.0.2

- 🔢 **Simple Credentials (Username & 6-Digit PIN)**:
  - Replaced complex random character passwords with a friendly, memorable 6-digit numeric PIN integer (e.g. `User: admin`, `Pass: 482915`).
- 📱 **Clean, Regular Monospace Typography**:
  - The password line on the iPhone dashboard is now displayed in clean, regular monospace font matching the rest of the interface (`configureMonospaceLabel`), removing unnecessary bold styling.
- 📡 **Real-Time Connection Keep-Alive & Fast Disconnect Detection**:
  - Added background heartbeat ping (`/api/ping` every 5 seconds) to maintain active sessions while browsing.
  - Reduced idle disconnection timeout from 7 days down to **15 seconds** (15,000 ms).
  - Integrated `navigator.sendBeacon('/api/logout')` on page unload/close for instant session release (0 ms).
  - Active session counter on the iPhone dashboard (`Sessions: X/3`) now accurately drops immediately when a user closes the tab or disconnects from Wi-Fi.
- 📝 **Comprehensive, Meaningful Activity Logging**:
  - Enriched server log buffer with detailed operational events:
    - Login success & failed attempts with remote IP.
    - File upload initiation, completion, and cancellation with byte sizes.
    - File download requests with byte sizes and Range requests.
    - Folder creation, rename, move, and trash/restore actions.
    - Session connections, timeouts, and logouts with active counts.
    - HTTP API requests and response status codes.
- 🏷️ **Version Bump**:
  - Core version updated to `1.0.2` (`CFBundleShortVersionString: 1.0.2`, `CFBundleVersion: 3`).

---

## 🌟 Key Highlights & Features

- 🚀 **Zero External Dependencies**: Built strictly with native **Swift 5** and POSIX sockets. No CocoaPods, no SwiftPM dependencies in the iOS target, no external JS frameworks, no CDNs, and no web fonts.
- 📱 **Engineered for Vintage Hardware**: Runs smoothly on **iOS 12.0+** with 64-bit arm64 architecture (iPhone 5s, iPad Air 1, iPad mini 2 and newer). Steady-state memory footprint strictly under **80 MB RAM**.
- 🎬 **Native Media Streaming**: Video and audio are streamed directly using `HTTP Range` requests (`206 Partial Content`), allowing instant seeking without battery-draining on-device transcoding.
- 🗜️ **Adaptive On-the-Fly DEFLATE Compression**: Automatically detects compressible formats (text, source code, JSON, logs) and streams compressed data with Apple's native `Compression` framework. Photos, videos, and archives remain untouched.
- 🎨 **Full-Featured Vanilla Web UI**:
  - **Bilingual localization**: Seamless switching between **Tiếng Việt** and **English**.
  - **Dual themes**: Deep Dark (`#111111`) & Light Cream (`#f5f0e1`).
  - **Layouts**: Responsive List view & customizable Grid view (S / M / L).
  - **Organization**: Drag-and-drop chunked uploads, inline renaming (`F2`), folder hierarchy, colored tags, and trash bin with instant restoration.
  - **Instant ZIP Streaming**: Packs and streams selected files and folders as a `.zip` archive on the fly.
  - **Built-in Media Viewer**: Full-screen previewers for photos (with smooth pan & zoom), video/audio, PDF, and syntax-aware text documents.
- 🔋 **Always-On Background & Screen Dimmer**:
  - In-memory silent audio playback loop keeps the server active in background.
  - One-tap **[Dim screen]** button drops screen brightness to 0 with a pure black overlay to conserve battery, minimize heat, and eliminate OLED/LCD burn-in during 24/7 plugged-in operation.
- 🛡️ **SQLite3 WAL Crash Resilience**: ACID metadata storage with automated reconciliation of interrupted uploads upon reboot (`.part` cleanup and WAL journal recovery).

---

## 📦 Release Assets

| Asset Name | Target Platform | Description |
|---|---|---|
| **`ExVault-unsigned.ipa`** | iOS 12.0+ (arm64) | Standalone application bundle for iPhone / iPad |
| **`exvault-cli`** | macOS (x86_64 / arm64) | Lightweight standalone terminal server for Mac |

---

## 📲 Installation Guide

### iOS App (`ExVault-unsigned.ipa`)

1. **Download**: Download `ExVault-unsigned.ipa` from the Assets below.
2. **Install on iOS**:
   * **Jailbroken Devices (iOS 12.0 – 14.x)**:
     1. Install **AppSync Unified** from Karen's repo (`https://cydia.akemi.ai/`) via Cydia/Sileo/Zebra.
     2. Transfer `ExVault-unsigned.ipa` to your iPhone (via AirDrop, Filza, or Safari download).
     3. Open the `.ipa` in **Filza** và chọn **Install**.
   * **TrollStore (iOS 14.0 – 17.0)**:
     * Open `ExVault-unsigned.ipa` directly in TrollStore to install permanently without revokes.
   * **AltStore / Sideloadly (Non-jailbroken)**:
     * Sideload `ExVault-unsigned.ipa` using your Apple ID via AltStore or Sideloadly from your PC/Mac.
3. **Usage**:
   * Launch **ExVault** on your iPhone, connect to local Wi-Fi, and plug into a charger.
   * Note the URL and credentials shown on the screen (e.g. `http://192.168.1.15:8080`, User: `admin`, Pass: `482915`).
   * Tap **[Dim screen]** to keep the phone running cool with a black display.
   * On any PC, tablet, or smartphone in the same Wi-Fi, open the URL in your browser and log in!

### macOS CLI (`exvault-cli`)

```bash
chmod +x exvault-cli
./exvault-cli --port 8080 --data ~/ExVaultData --web ./Web
```

---

*Open Source Repository*: [https://github.com/dajyuuxd/ExVault](https://github.com/dajyuuxd/ExVault)

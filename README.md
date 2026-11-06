# ExVault ⚡

[![Build Status](https://github.com/dajyuuxd/ExVault/actions/workflows/build.yml/badge.svg)](https://github.com/dajyuuxd/ExVault/actions)
![iOS Target](https://img.shields.io/badge/iOS-12.0%2B-blue?logo=apple)
![Architecture](https://img.shields.io/badge/Architecture-arm64-green)
![Language](https://img.shields.io/badge/Language-Swift%205-orange?logo=swift)
![Dependencies](https://img.shields.io/badge/Dependencies-Zero-brightgreen)

**ExVault** is an ultra-lightweight, high-performance offline LAN storage server designed to repurpose legacy iOS devices (such as a jailbroken **iPhone 5s on iOS 12.5.8**) into a private, self-hosted file vault similar to MediaFire or MEGA.

Operates **100% offline within your local Wi-Fi / LAN**. Simply launch the app on your old iPhone, read the auto-generated credentials on the screen, and open `http://<iPhone-IP>:8080` from any computer or smartphone to upload, manage, stream, and download your files.

---

## 🌟 Key Highlights

- 🚀 **Zero External Dependencies**: Built strictly with native **Swift 5** and POSIX sockets. No CocoaPods, no SwiftPM dependencies in the iOS target, no external JS frameworks, no CDNs, and no web fonts.
- 📱 **Engineered for Vintage Hardware**: Runs smoothly on **iOS 12.0+** with an A7 64-bit processor. RAM usage strictly budgeted at under **80 MB** during normal operation.
- ⚡ **Adaptive On-the-Fly Compression**: Utilizes Apple's native `Compression` framework (zlib raw DEFLATE) to transparently compress text, code, and document files while streaming. Photos, videos, and already-compressed files are automatically preserved untouched.
- 🎬 **Native Media Streaming**: Video and audio are streamed directly using `HTTP Range` requests (`206 Partial Content`), allowing instant seeking without battery-draining on-device transcoding.
- 📦 **Resumable Chunked Uploads**: Client-side chunking (4MB chunks) with rolling CRC32 checksum verification and automatic retry capabilities.
- 🎨 **Refined Vanilla Web UI**: Clean, responsive interface built with pure HTML5/CSS3/ES2017. Features:
  - Dual themes: Light Cream (`#f5f0e1`) & Deep Dark (`#111111`).
  - Bilingual localization (**Vietnamese** and **English**).
  - List view & customizable Grid view (S / M / L).
  - Folder hierarchy, inline rename, batch move, tag tagging, trash bin with recovery, and on-the-fly multi-file ZIP archive streaming.
  - Built-in previewers for photos (with zoom), video, PDF, and syntax-aware text documents.
- 🔋 **Always-On Background Engine**: Combines `isIdleTimerDisabled`, a looped silent audio stream (`UIBackgroundModes: audio`), and a one-tap OLED/LCD screen dimmer to prevent iOS from suspending the server.
- 🔒 **Ephemeral LAN Security**: Generates fresh, random session credentials displayed on the iPhone screen at each server launch. Supports up to 3 active concurrent sessions with rate-limited login brute-force protection.

---

## 🏛️ System Architecture

```
Desktop / Mobile Browser  ─── HTTP / LAN (Port 8080) ───▶  iPhone (ExVault.app)
                                                             ├─ UIKit Shell (Credentials, IP, Live Logs, Dimming)
                                                             ├─ KeepAlive (Audio loop + Idle timer)
                                                             └─ ExVaultCore
                                                                  ├─ HTTP/1.1 POSIX Socket Server (64KB streaming buffers)
                                                                  ├─ Ephemeral Auth & Sessions (RateLimiter)
                                                                  ├─ Blob Storage & Apple Compression
                                                                  ├─ SQLite Metadata (WAL mode, parameterized queries)
                                                                  └─ Responsive Static Web Assets (Vanilla JS)
```

---

## 🚀 Quick Start Guide

### 1. Download
Download the latest unsigned `.ipa` package from the **[GitHub Actions Artifacts](https://github.com/dajyuuxd/ExVault/actions)** (build artifact `ExVault-unsigned-ipa`).

### 2. Installation (Jailbroken iPhone)
Install the IPA onto your jailbroken iOS device (requires **AppSync Unified** or direct installation tools):
- **Via Filza**: Transfer the `.ipa` via AirDrop/Filza and tap **Install**.
- **Via CLI**: Run `ipainstaller ExVault-unsigned.ipa` through SSH or terminal.

### 3. Running ExVault
1. Connect your iPhone to your local Wi-Fi network and plug it into a charger.
2. Open **ExVault**. The screen displays your connection details:
   ```text
   EXVAULT  v1.0.1
   Status   : RUNNING  (uptime 00:05:12)
   URL      : http://192.168.1.15:8080
   User     : kxqmt
   Pass     : p7f3n8zw
   Disk     : 7.8 GB free
   Sessions : 1/3
   ```
3. Tap **[Dim screen]** to dim the display to black while keeping the server running in the foreground.
4. On your PC, Mac, or phone, open your browser and navigate to the displayed URL (e.g. `http://192.168.1.15:8080`).
5. Enter the username and password shown on the iPhone screen to begin!

---

## ⌨️ Web Interface & Shortcuts

| Action | Shortcut / Gesture | Description |
|---|---|---|
| **Open Item** | `Enter` / Double Click | Opens folder or launches file viewer |
| **Rename** | `F2` | Quick in-place inline file/folder rename |
| **Delete / Trash** | `Delete` / `Backspace` | Moves selected items into the Trash Bin |
| **Select All** | `Ctrl + A` / `Cmd + A` | Selects all items in current view |
| **Range Select** | `Shift + Click` | Selects a contiguous range of files |
| **Toggle Select** | `Ctrl + Click` / `Cmd + Click` | Adds/removes individual items to selection |
| **Cancel / Close** | `Esc` | Clears selection or closes modals/viewers |
| **Upload Files** | Drag & Drop | Drag files directly from your desktop into the window |
| **Download as ZIP** | Batch Toolbar Button | Packs and streams selected files/folders as a `.zip` on the fly |

---

## ⚙️ Technical Specifications

| Parameter | Specification |
|---|---|
| **Language** | Swift 5 (`SWIFT_VERSION=5.0`), C POSIX APIs |
| **iOS Target** | iOS 12.0+ (Deployment Target 12.0, arm64) |
| **Server Engine** | POSIX `socket`, `bind`, `listen`, `accept`, HTTP/1.1 |
| **Max Concurrent Sockets** | 8 concurrent connections (`DispatchSemaphore`) |
| **Socket Buffer** | 64 KB streaming buffer (no large file buffered into RAM) |
| **Database** | SQLite3 in WAL mode with Foreign Keys enabled |
| **Storage Layout** | Content-addressable shards: `blobs/<xx>/<blob_id>` |
| **Compression** | Apple `compression_stream` (zlib raw DEFLATE) |
| **Client Tech** | Pure HTML5, CSS3 Variables, ES2017 JavaScript (Zero dependencies) |
| **RAM Budget** | `< 80 MB` steady-state |

---

## 🛠️ Build & CI

Builds and automated tests are continuously executed on macOS runners via **GitHub Actions** (`.github/workflows/build.yml`):
- **Core Library & macOS CLI**: Built with Swift Package Manager (`swift build`, `swift test`).
- **iOS Application**: Built using **XcodeGen** (`xcodegen generate`) and `xcodebuild` targeting `arm64` device deployment without code signing.

---

## ⚠️ Operational Guidelines & Resilience

1. **Power Supply & Aging Battery**: Vintage devices (like iPhone 5s) often possess degraded lithium batteries. Always keep the device connected to a stable 5V/1A power adapter when serving files over LAN.
2. **Thermal & Display Care**: Use the **[Dim screen]** button in the app. This turns brightness to 0 and displays a black overlay, significantly lowering power draw, heat generation, and preventing backlight/OLED burn-in during 24/7 operation.
3. **RAM Budget & iOS Jetsam Watchdog**: Older devices have 1GB of total RAM where iOS jetsam aggressively kills processes exceeding ~120MB. ExVault strictly streams all data using 64KB buffers (never loading full files or chunks into RAM) to guarantee steady-state memory below **80 MB**.
4. **Crash Resilience & Power Loss**:
   - SQLite runs in write-ahead log (`WAL`) mode with automatic journal recovery.
   - Any upload interrupted by unexpected power failure or forced termination is automatically reconciled on the next boot: incomplete `.part` temporary files are pruned, and incomplete upload records are marked as `error`.
5. **Storage & Backup Exclusion**: The vault storage directory (`<Documents>/ExVault`) is explicitly tagged with `isExcludedFromBackup = true` to prevent ballooning your iCloud or iTunes backup sizes.
6. **Ephemeral Credentials**: Login username and password are regenerated upon each app launch. Active sessions are kept in volatile memory, while uploaded files and metadata persist across restarts.

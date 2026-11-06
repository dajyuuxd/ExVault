# 07 — App iOS, KeepAlive, XcodeGen, CI, IPA

## 1. Màn hình app (`App/ViewController.swift`)

UIKit viết bằng code, nền đen `UIColor.black`, chữ trắng, font đơn cách `Menlo` 13pt (phải vừa màn 320pt của 5s). Một `UIScrollView` chứa `UIStackView` dọc, `UILabel` các dòng:

```
EXVAULT  v1.0
Status : RUNNING  (uptime 00:12:31)
URL    : http://192.168.1.5:8080
User   : kxqmt
Pass   : p7f3n8zw
Disk   : 7.4 GB free
Sessions: 1/3
--- log (latest 10) ---
...
```
Chữ Pass cỡ 22pt đậm để dễ đọc. Nút `UIButton` ở cuối: **[Dim screen]** và **[Copy pass]** (đưa vào `UIPasteboard.general`). Timer 1 giây (`Timer.scheduledTimer`) cập nhật uptime/disk/sessions/log (đọc `Log.recentLines()` 10 dòng cuối). Nếu không có IP (chưa vào Wi-Fi) hiển thị `URL : (no network)` và thử lại mỗi giây. Nhiều IP thì hiện mỗi dòng một cái.

## 2. AppDelegate (`App/AppDelegate.swift`)

```swift
@UIApplicationMain
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    var server: VaultServer?
    let keepAlive = KeepAlive()
    func application(_:didFinishLaunchingWithOptions:) -> Bool
    func applicationDidReceiveMemoryWarning(_:)
    func applicationDidEnterBackground(_:)       // bắt đầu beginBackgroundTask một lần để có thêm thời gian
    func applicationWillEnterForeground(_:)
    func applicationWillTerminate(_:)            // server?.stop()
}
```
- `didFinishLaunching`: tạo `window` (`UIScreen.main.bounds`), `rootViewController = ViewController(app: self)`, `makeKeyAndVisible`; `keepAlive.start()`; khởi tạo server trên `DispatchQueue.global()`:
  - `dataDir = Documents/ExVault` (tạo, đặt `isExcludedFromBackup`), `webRoot = Bundle.main.resourceURL!.appendingPathComponent("Web")`.
  - `try VaultServer(config:)`, `try start()`; lỗi ⇒ `Log.error` và ViewController hiện dòng `Status : ERROR <msg>`.
- `applicationDidReceiveMemoryWarning`: `Log.warn("memory warning")` (server không giữ cache lớn, không cần làm gì thêm).
- Không có SceneDelegate. `Info.plist` không khai báo `UIApplicationSceneManifest`.

## 3. KeepAlive (`App/KeepAlive.swift`)

```swift
final class KeepAlive {
    func start()                       // idleTimerDisabled = true; bật audio im lặng
    func stop()
    func setDim(_ on: Bool)            // on: lưu brightness cũ, đặt 0.0; off: khôi phục
    private func startSilentAudio()
    static func makeSilentWav(seconds: Int) -> Data
}
```
- `UIApplication.shared.isIdleTimerDisabled = true` (phải gọi trên main thread).
- Audio im lặng: `AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])` (API Swift 4.2+: `setCategory(_:mode:options:)` có từ iOS 10; chấp nhận được), `setActive(true)`. `makeSilentWav(1)`: WAV PCM 16-bit mono 8000Hz, 1 giây toàn số 0 (44 byte header + 16000 byte dữ liệu). Ghi vào `NSTemporaryDirectory()/silence.wav`, `AVAudioPlayer(contentsOf:)`, `numberOfLoops = -1`, `volume = 0.0` (đặt 0.01 nếu iOS bỏ qua volume 0 làm hệ thống ngắt phiên; ghi chú trong code), `prepareToPlay()`, `play()`.
- Quan sát `AVAudioSession.interruptionNotification`: khi `.ended` ⇒ `setActive(true)` rồi `player.play()` lại. Quan sát `UIApplication.didBecomeActiveNotification` ⇒ nếu player không `isPlaying` thì phát lại.
- `setDim(true)`: hiện thêm view đen phủ toàn màn (`UIView` đen alpha 1) + `UIScreen.main.brightness = 0`; chạm bất kỳ chỗ nào ⇒ `setDim(false)`.

## 4. Info.plist (sinh từ `project.yml`)

| Khóa | Giá trị |
|---|---|
| `CFBundleIdentifier` | `dev.exvault.app` |
| `CFBundleDisplayName` | `ExVault` |
| `CFBundleShortVersionString` / `CFBundleVersion` | `1.0` / `1` |
| `MinimumOSVersion` (từ `IPHONEOS_DEPLOYMENT_TARGET`) | `12.0` |
| `UIBackgroundModes` | `[audio]` |
| `UILaunchStoryboardName` | `LaunchScreen` |
| `UIRequiredDeviceCapabilities` | `[arm64]` |
| `UISupportedInterfaceOrientations` | Portrait, LandscapeLeft, LandscapeRight |
| `UIStatusBarStyle` | `UIStatusBarStyleLightContent` |
| `UIViewControllerBasedStatusBarAppearance` | `false` |
| `UIFileSharingEnabled` | `true` (cho phép xem thư mục Documents qua Files/iTunes, tiện kiểm tra) |
| `LSSupportsOpeningDocumentsInPlace` | `true` |

**LaunchScreen.storyboard là bắt buộc**: nếu thiếu, iOS chạy app ở chế độ khung 320x480 phóng lớn. Nội dung tối thiểu (nền đen):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<document type="com.apple.InterfaceBuilder3.CocoaTouch.Storyboard.XIB" version="3.0" toolsVersion="14460.31" targetRuntime="iOS.CocoaTouch" propertyAccessControl="none" useAutolayout="YES" launchScreen="YES" useTraitCollections="YES" useSafeAreas="YES" colorMatched="YES" initialViewController="01J-lp-oVM">
    <dependencies>
        <plugIn identifier="com.apple.InterfaceBuilder.IBCocoaTouchPlugin" version="14460.20"/>
        <capability name="Safe area layout guides" minToolsVersion="9.0"/>
    </dependencies>
    <scenes>
        <scene sceneID="EHf-IW-A2E">
            <objects>
                <viewController id="01J-lp-oVM" sceneMemberID="viewController">
                    <view key="view" contentMode="scaleToFill" id="Ze5-6b-2t3">
                        <rect key="frame" x="0.0" y="0.0" width="375" height="667"/>
                        <autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>
                        <color key="backgroundColor" white="0.0" alpha="1" colorSpace="custom" customColorSpace="genericGamma22GrayColorSpace"/>
                        <viewLayoutGuide key="safeArea" id="6Tk-OE-BBY"/>
                    </view>
                </viewController>
                <placeholder placeholderIdentifier="IBFirstResponder" id="iYj-Kq-Ea1" userLabel="First Responder" sceneMemberID="firstResponder"/>
            </objects>
            <point key="canvasLocation" x="53" y="375"/>
        </scene>
    </scenes>
</document>
```

## 5. `project.yml` (XcodeGen)

```yaml
name: ExVault
options:
  bundleIdPrefix: dev.exvault
  deploymentTarget:
    iOS: "12.0"
settings:
  base:
    SWIFT_VERSION: "5.0"
    IPHONEOS_DEPLOYMENT_TARGET: "12.0"
    TARGETED_DEVICE_FAMILY: "1,2"
    ARCHS: arm64
    ENABLE_BITCODE: NO
    CODE_SIGNING_ALLOWED: NO
    CODE_SIGNING_REQUIRED: NO
    CODE_SIGN_IDENTITY: ""
targets:
  ExVault:
    type: application
    platform: iOS
    sources:
      - path: App
        excludes: ["Info.plist"]
      - path: Sources/ExVaultCore
      - path: Web
        type: folder
        buildPhase: resources
    info:
      path: App/Info.plist
      properties:
        CFBundleDisplayName: ExVault
        CFBundleShortVersionString: "1.0"
        CFBundleVersion: "1"
        UIBackgroundModes: [audio]
        UILaunchStoryboardName: LaunchScreen
        UIRequiredDeviceCapabilities: [arm64]
        UISupportedInterfaceOrientations: [UIInterfaceOrientationPortrait, UIInterfaceOrientationLandscapeLeft, UIInterfaceOrientationLandscapeRight]
        UIStatusBarStyle: UIStatusBarStyleLightContent
        UIViewControllerBasedStatusBarAppearance: false
        UIFileSharingEnabled: true
        LSSupportsOpeningDocumentsInPlace: true
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: dev.exvault.app
        PRODUCT_NAME: ExVault
        INFOPLIST_FILE: App/Info.plist
```
`LaunchScreen.storyboard` nằm trong `App/` nên tự vào resources. Nếu XcodeGen báo lỗi cú pháp ở phiên bản trên runner, đọc tài liệu XcodeGen (`ProjectSpec.md`) và chỉnh cho đúng mà **không đổi ý nghĩa**.

## 6. `.github/workflows/build.yml`

```yaml
name: build
on: [push, pull_request, workflow_dispatch]
jobs:
  core:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4
      - run: swift --version && xcodebuild -version
      - run: swift build -c release
      - run: swift test
      - run: node scripts/check-i18n.js        # bỏ qua nếu chưa có Web/js/i18n.js (T14)
        if: hashFiles('scripts/check-i18n.js') != ''
      - run: bash scripts/integration.sh        # có từ T13
        if: hashFiles('scripts/integration.sh') != ''
  ios:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4
      - run: brew install xcodegen
      - run: xcodegen generate
      - run: |
          xcodebuild -project ExVault.xcodeproj -scheme ExVault \
            -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
            -derivedDataPath build ARCHS=arm64 ONLY_ACTIVE_ARCH=NO \
            CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build
      - run: |
          APP=build/Build/Products/Release-iphoneos/ExVault.app
          test -d "$APP"
          /usr/libexec/PlistBuddy -c "Print :MinimumOSVersion" "$APP/Info.plist"
          lipo -info "$APP/ExVault"
          test -f "$APP/Web/index.html"
          mkdir -p out/Payload && cp -R "$APP" out/Payload/
          (cd out && zip -qry ExVault-unsigned.ipa Payload)
      - uses: actions/upload-artifact@v4
        with:
          name: ExVault-unsigned-ipa
          path: out/ExVault-unsigned.ipa
```
- `MinimumOSVersion` in ra phải là `12.0`; `lipo -info` phải là `arm64`.
- Nếu `xcodebuild` báo deployment target iOS 12.0 không được hỗ trợ ⇒ thêm bước `sudo xcode-select -s /Applications/Xcode_15.4.app` (kiểm tra tên bằng `ls /Applications | grep Xcode` trong log) và ghi vào `PROGRESS.md`.
- Job `ios` chạy từ T00 với app rỗng (ViewController hiện chữ) để phát hiện sớm vấn đề toolchain; Web/ lúc đó chỉ có `index.html` placeholder.

## 7. Cài đặt lên máy (ngoài phạm vi code)

IPA tạo ra là **không ký**. Trên iPhone 5s đã jailbreak cần có công cụ cho phép cài/chạy app không ký (thường là tweak AppSync Unified) rồi cài `.ipa` bằng Filza, `ipainstaller` hoặc công cụ tương tự; phần này bạn tự xử lý. Một số cách cài yêu cầu ký giả bằng `ldid -S` lên file nhị phân; nếu cần, agent có thể thêm bước tùy chọn đó vào CI sau khi bạn xác nhận (không bắt buộc ở bản đầu).

# T00 — Scaffold + CI

**Mục tiêu**: khung repo biên dịch được trên CI (core + CLI + test + IPA rỗng). Chưa có logic.
**Đọc**: `docs/01`, `docs/07`.

## File tạo
1. `.gitignore`: `.build/`, `build/`, `out/`, `*.xcodeproj`, `.DS_Store`, `DerivedData/`, `xcuserdata/`.
2. `Package.swift` (tools 5.5):
   ```swift
   // swift-tools-version:5.5
   import PackageDescription
   let package = Package(
     name: "ExVault",
     platforms: [.macOS(.v10_15), .iOS(.v12)],
     products: [.library(name: "ExVaultCore", targets: ["ExVaultCore"]),
                .executable(name: "exvault-cli", targets: ["exvault-cli"])],
     targets: [
       .target(name: "ExVaultCore"),
       .executableTarget(name: "exvault-cli", dependencies: ["ExVaultCore"]),
       .testTarget(name: "ExVaultCoreTests", dependencies: ["ExVaultCore"])
     ])
   ```
3. `Sources/ExVaultCore/VaultServer.swift`: chỉ `public enum ExVaultInfo { public static let version = "1.0" }`.
4. `Sources/exvault-cli/main.swift`: `import ExVaultCore; print("exvault-cli \(ExVaultInfo.version)")`.
5. `Tests/ExVaultCoreTests/SmokeTests.swift`: test `XCTAssertEqual(ExVaultInfo.version, "1.0")` với `@testable import ExVaultCore`.
6. `App/AppDelegate.swift`, `App/ViewController.swift`: màn đen, một `UILabel` trắng "ExVault " + version ở giữa. Dùng `#if canImport(ExVaultCore) import ExVaultCore #endif`. `@UIApplicationMain`, có `window`. Không SceneDelegate.
7. `App/LaunchScreen.storyboard`: nội dung đúng như `docs/07` mục 4.
8. `Web/index.html`: trang placeholder `<h1>ExVault</h1>`.
9. `project.yml`: đúng `docs/07` mục 5.
10. `.github/workflows/build.yml`: đúng `docs/07` mục 6.
11. `scripts/` (thư mục rỗng có `.gitkeep`).

## Tiêu chí nghiệm thu
- [ ] CI job `core` xanh (`swift build`, `swift test` chạy 1 test).
- [ ] CI job `ios` xanh, log in `MinimumOSVersion` = `12.0`, `lipo -info` = `arm64`, có `Web/index.html` trong `.app`.
- [ ] Artifact `ExVault-unsigned-ipa` tải được.
- [ ] Không file nào ngoài danh sách.

// swift-tools-version:5.5
import PackageDescription

let package = Package(
  name: "ExVault",
  platforms: [.macOS(.v10_15), .iOS(.v12)],
  products: [
    .library(name: "ExVaultCore", targets: ["ExVaultCore"]),
    .executable(name: "exvault-cli", targets: ["exvault-cli"])
  ],
  targets: [
    .target(name: "ExVaultCore"),
    .executableTarget(name: "exvault-cli", dependencies: ["ExVaultCore"]),
    .testTarget(name: "ExVaultCoreTests", dependencies: ["ExVaultCore"])
  ]
)

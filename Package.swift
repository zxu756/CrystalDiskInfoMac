// swift-tools-version: 6.0
import Foundation
import PackageDescription

let cltTestingMacros = "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib"
let testSwiftSettings: [SwiftSetting] = FileManager.default.fileExists(atPath: cltTestingMacros)
    ? [.unsafeFlags(["-load-plugin-library", cltTestingMacros])]
    : []

let package = Package(
    name: "CrystalDiskInfoMac",
    platforms: [
        .macOS("27.0")
    ],
    products: [
        .library(name: "CrystalDiskInfoMacCore", targets: ["CrystalDiskInfoMacCore"]),
        .executable(name: "CrystalDiskInfoMac", targets: ["CrystalDiskInfoMac"])
    ],
    targets: [
        .target(
            name: "CrystalDiskInfoMacCore",
            path: "Sources/CrystalDiskInfoMacCore"
        ),
        .executableTarget(
            name: "CrystalDiskInfoMac",
            dependencies: ["CrystalDiskInfoMacCore"],
            path: "Sources/CrystalDiskInfoMac"
        ),
        .testTarget(
            name: "CrystalDiskInfoMacCoreTests",
            dependencies: ["CrystalDiskInfoMacCore"],
            path: "Tests/CrystalDiskInfoMacCoreTests",
            swiftSettings: testSwiftSettings
        )
    ],
    swiftLanguageModes: [.v5]
)

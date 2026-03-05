// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AIBattery",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "AIBatteryCore", targets: ["AIBatteryCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")
    ],
    targets: [
        .target(
            name: "AIBatteryCore",
            dependencies: ["Sparkle"],
            path: "AIBattery",
            exclude: ["Info.plist", "AIBattery.entitlements", "AIBattery-AppStore.entitlements"],
            resources: [.copy("PrivacyInfo.xcprivacy")],
            swiftSettings: [.define("ENABLE_SPARKLE")]
        ),
        .executableTarget(
            name: "AIBattery",
            dependencies: ["AIBatteryCore"],
            path: "AIBatteryApp",
            swiftSettings: [.define("ENABLE_SPARKLE")]
        ),
        .testTarget(
            name: "AIBatteryCoreTests",
            dependencies: ["AIBatteryCore"],
            path: "Tests/AIBatteryCoreTests",
            swiftSettings: [.define("ENABLE_SPARKLE")]
        )
    ]
)

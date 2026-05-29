// swift-tools-version: 6.0
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
        .package(url: "https://github.com/sparkle-project/Sparkle", "2.6.0"..<"3.0.0")
    ],
    targets: [
        .target(
            name: "AIBatteryCore",
            dependencies: ["Sparkle"],
            path: "AIBattery",
            exclude: ["Info.plist", "AIBattery.entitlements", "AIBattery-AppStore.entitlements"],
            resources: [.copy("PrivacyInfo.xcprivacy")],
            swiftSettings: [
                .define("ENABLE_SPARKLE"),
                .define("ENABLE_VERSION_CHECKER"),
                .swiftLanguageMode(.v6)
            ]
        ),
        .executableTarget(
            name: "AIBattery",
            dependencies: ["AIBatteryCore"],
            path: "AIBatteryApp",
            swiftSettings: [
                .define("ENABLE_SPARKLE"),
                .define("ENABLE_VERSION_CHECKER"),
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "AIBatteryCoreTests",
            dependencies: ["AIBatteryCore"],
            path: "Tests/AIBatteryCoreTests",
            swiftSettings: [
                .define("ENABLE_SPARKLE"),
                .define("ENABLE_VERSION_CHECKER"),
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)

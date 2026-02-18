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
    targets: [
        .target(
            name: "AIBatteryCore",
            path: "AIBattery",
            exclude: ["Info.plist", "AIBattery.entitlements"]
        ),
        .executableTarget(
            name: "AIBattery",
            dependencies: ["AIBatteryCore"],
            path: "AIBatteryApp"
        ),
        .testTarget(
            name: "AIBatteryCoreTests",
            dependencies: ["AIBatteryCore"],
            path: "Tests/AIBatteryCoreTests"
        )
    ]
)

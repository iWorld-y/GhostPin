// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TodoPin",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "TodoPin", targets: ["TodoPin"]),
        .executable(name: "todopin-cli", targets: ["TodoPinCLI"]),
        .executable(name: "TodoPinCoreChecks", targets: ["TodoPinCoreChecks"])
    ],
    targets: [
        .target(
            name: "TodoPinCore",
            path: "Sources/TodoPinCore"
        ),
        .executableTarget(
            name: "TodoPin",
            dependencies: ["TodoPinCore", "WhisperFramework"],
            path: "Sources/TodoPin",
            resources: [
                .copy("Resources")
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Carbon"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("UserNotifications")
            ]
        ),
        .executableTarget(
            name: "TodoPinCoreChecks",
            dependencies: ["TodoPinCore"],
            path: "Tests/TodoPinCoreChecks"
        ),
        .executableTarget(
            name: "TodoPinCLI",
            dependencies: ["TodoPinCore"],
            path: "Sources/TodoPinCLI"
        ),
        .binaryTarget(
            name: "WhisperFramework",
            url: "https://github.com/ggml-org/whisper.cpp/releases/download/v1.8.6/whisper-v1.8.6-xcframework.zip",
            checksum: "654f6534b1d109cf1f53c3ac94de14d1aedbc08600bf9743e2b331c1619a863f"
        )
    ],
    swiftLanguageModes: [.v5]
)

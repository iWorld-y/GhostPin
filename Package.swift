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
        .target(
            name: "TodoPinMCP",
            dependencies: ["TodoPinCore"],
            path: "Sources/TodoPinMCP"
        ),
        .executableTarget(
            name: "TodoPin",
            dependencies: ["TodoPinCore"],
            path: "Sources/TodoPin",
            resources: [
                .copy("Resources")
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("UserNotifications")
            ]
        ),
        .executableTarget(
            name: "TodoPinCoreChecks",
            dependencies: ["TodoPinCore", "TodoPinMCP"],
            path: "Tests/TodoPinCoreChecks"
        ),
        .executableTarget(
            name: "TodoPinCLI",
            dependencies: ["TodoPinCore", "TodoPinMCP"],
            path: "Sources/TodoPinCLI"
        )
    ],
    swiftLanguageModes: [.v5]
)

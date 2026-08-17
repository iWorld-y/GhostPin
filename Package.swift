// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GhostPin",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "GhostPin", targets: ["GhostPin"]),
        .executable(name: "ghostpin-cli", targets: ["GhostPinCLI"]),
        .executable(name: "GhostPinCoreChecks", targets: ["GhostPinCoreChecks"])
    ],
    targets: [
        .target(
            name: "GhostPinCore",
            path: "Sources/GhostPinCore"
        ),
        .executableTarget(
            name: "GhostPin",
            dependencies: ["GhostPinCore"],
            path: "Sources/GhostPin",
            resources: [
                .copy("Resources")
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("UserNotifications")
            ]
        ),
        .executableTarget(
            name: "GhostPinCoreChecks",
            dependencies: ["GhostPinCore"],
            path: "Tests/GhostPinCoreChecks"
        ),
        .executableTarget(
            name: "GhostPinCLI",
            dependencies: ["GhostPinCore"],
            path: "Sources/GhostPinCLI"
        )
    ],
    swiftLanguageModes: [.v5]
)

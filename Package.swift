// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MegaplanMenuBarApp",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "MegaplanMenuBarApp",
            targets: ["MegaplanMenuBarApp"]
        )
    ],
    targets: [
        .executableTarget(
            name: "MegaplanMenuBarApp",
            dependencies: [],
            path: ".",
            exclude: [
                "MegaplanMenuBarApp.xcodeproj",
                "Package.swift",
                "Info.plist",
                "MegaplanMenuBarApp.entitlements"
            ],
            sources: [
                "MegaplanMenuBarApp.swift",
                "AppState.swift",
                "Models",
                "Services",
                "Utils",
                "Views"
            ],
            resources: [
                .process("Resources")
            ]
        )
    ]
)


// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AgentsAnywhereClient",
    platforms: [.macOS(.v13), .iOS(.v14)],
    targets: [
        .target(
            name: "ClientCore",
            path: "Agents Anywhere/Agents Anywhere",
            exclude: [
                "App", "Assets.xcassets", "Resources", "Services", "Stores", "Views",
                "ios-dark.icon", "Business/AccountAvatarProcessor.swift",
            ],
            sources: ["API", "Network", "Models", "Domain", "Business", "Repositories"]
        ),
        .testTarget(
            name: "ClientCoreTests",
            dependencies: ["ClientCore"],
            path: "Tests/ClientCoreTests",
            resources: [.copy("Fixtures")]
        ),
    ],
    swiftLanguageModes: [.v5]
)

// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "kk",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "kk", targets: ["kk"])
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts.git", from: "3.0.1"),
        .package(url: "https://github.com/LiYanan2004/MarkdownView.git", from: "3.0.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.10.1")
    ],
    targets: [
        .executableTarget(
            name: "kk",
            dependencies: [
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
                .product(name: "MarkdownView", package: "MarkdownView"),
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/kk",
            exclude: ["Resources/Info.plist", "Resources/AppIcon.icns"],
            resources: [.copy("Resources/Mermaid")]
        ),
        .testTarget(
            name: "kkTests",
            dependencies: ["kk"],
            path: "Tests/kkTests"
        )
    ]
)

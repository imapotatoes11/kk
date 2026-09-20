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
        .package(url: "https://github.com/LiYanan2004/MarkdownView.git", from: "3.0.0")
    ],
    targets: [
        .executableTarget(
            name: "kk",
            dependencies: [
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
                .product(name: "MarkdownView", package: "MarkdownView")
            ],
            path: "Sources/kk",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "kkTests",
            dependencies: ["kk"],
            path: "Tests/kkTests"
        )
    ]
)

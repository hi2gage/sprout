// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "sprout",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
        .package(url: "https://github.com/dduan/TOMLDecoder.git", from: "0.4.0"),
        .package(url: "https://github.com/swiftlang/swift-subprocess.git", branch: "main"),
    ],
    targets: [
        .executableTarget(
            name: "sprout",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "TOMLDecoder", package: "TOMLDecoder"),
                .product(name: "Subprocess", package: "swift-subprocess"),
            ]
        ),
    ]
)

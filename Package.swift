// swift-tools-version: 6.2

import PackageDescription

// The NSException shim is Objective-C, so it exists only on Apple platforms. This manifest is
// compiled on the build host, so gating here keeps a non-Apple build (this repo's ubuntu CI
// leg) from ever trying to compile Objective-C sources. The matching source-side gate is
// `#if canImport(ObjCExceptionCatcher)` in GitService.swift, where the non-Apple path needs no
// shim: with no Objective-C runtime, `Process` cannot raise an `NSException` to intercept.
#if os(macOS)
let exceptionCatcherTargets: [Target] = [
    // Objective-C shim that traps `NSException`s (e.g. from `Process`) so Swift callers
    // can recover instead of aborting the process.
    .target(name: "ObjCExceptionCatcher"),
]
let exceptionCatcherDependencies: [Target.Dependency] = ["ObjCExceptionCatcher"]
#else
let exceptionCatcherTargets: [Target] = []
let exceptionCatcherDependencies: [Target.Dependency] = []
#endif

let package = Package(
    name: "sprout",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "sprout", targets: ["sprout"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
        .package(url: "https://github.com/dduan/TOMLDecoder.git", from: "0.4.0"),
    ],
    targets: exceptionCatcherTargets + [
        .executableTarget(
            name: "sprout",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "TOMLDecoder", package: "TOMLDecoder"),
            ] + exceptionCatcherDependencies
        ),
        .testTarget(
            name: "sproutTests",
            dependencies: ["sprout"]
        ),
    ]
)

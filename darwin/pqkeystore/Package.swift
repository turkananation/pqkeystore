// swift-tools-version: 5.9
// Shared iOS + macOS source (pubspec: sharedDarwinSource: true).

import PackageDescription

let package = Package(
    name: "pqkeystore",
    platforms: [
        .iOS("15.0"),
        .macOS("12.0"),
    ],
    products: [
        .library(name: "pqkeystore", targets: ["pqkeystore"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "pqkeystore",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ],
            resources: [
                // The plugin collects no data and uses no required-reason APIs;
                // the manifest declares that explicitly.
                .process("PrivacyInfo.xcprivacy")
            ],
            linkerSettings: [
                .linkedFramework("Security"),
                .linkedFramework("LocalAuthentication"),
            ]
        )
    ]
)

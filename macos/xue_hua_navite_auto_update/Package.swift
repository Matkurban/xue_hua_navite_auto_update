// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "xue_hua_navite_auto_update",
    platforms: [
        .macOS("12.0"),
    ],
    products: [
        .library(
            name: "xue-hua-navite-auto-update",
            targets: ["xue_hua_navite_auto_update"]
        ),
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
    ],
    targets: [
        .target(
            name: "xue_hua_navite_auto_update",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
            ],
            resources: [
                .process("PrivacyInfo.xcprivacy"),
            ]
        ),
    ]
)

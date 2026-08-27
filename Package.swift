// swift-tools-version:5.9
//  Copyright RNA Digital PTY LTD

import PackageDescription

let package = Package(
    name: "MonitaSDK",
    platforms: [
        .iOS(.v14),
        .macOS(.v11),
    ],
    products: [
        .library(name: "MonitaSDK", targets: ["MonitaSDK"]),
    ],
    targets: [
        .target(
            name: "MonitaSDK",
            path: "Sources/MonitaSDK"
        ),
        .testTarget(
            name: "MonitaSDKTests",
            dependencies: ["MonitaSDK"],
            path: "Tests/MonitaSDKTests",
            resources: [
                .copy("Fixtures"),
            ]
        ),
    ]
)

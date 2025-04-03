// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MonitaSDK",
    platforms: [.iOS(.v13),],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "MonitaSDK",
            targets: ["MonitaSDK"]),
    ],
    dependencies: [
            .package(url: "https://github.com/divar-ir/NetShears.git", from: "3.2.3"),
            .package(url: "https://github.com/1024jp/GzipSwift", .upToNextMajor(from: "6.1.0")),
          ],
    targets: [
        .target(
            name: "MonitaSDK", dependencies: ["NetShears", .product(name: "Gzip", package: "GzipSwift")], path: "Sources/MonitaSDK"),
        .testTarget(
            name: "MonitaSDKTests",
            dependencies: ["MonitaSDK"]
        ),
    ]
)

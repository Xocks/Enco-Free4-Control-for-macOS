// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "OppoPodsMac",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "OppoPodsMac", targets: ["OppoPodsMac"]),
        .library(name: "OppoPodsCore", targets: ["OppoPodsCore"]),
    ],
    targets: [
        .target(name: "OppoPodsCore"),
        .executableTarget(
            name: "OppoPodsMac",
            dependencies: ["OppoPodsCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("IOBluetooth"),
                .linkedFramework("CoreBluetooth"),
                .linkedFramework("UserNotifications"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .testTarget(name: "OppoPodsCoreTests", dependencies: ["OppoPodsCore"]),
    ]
)

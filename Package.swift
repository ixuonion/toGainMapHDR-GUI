// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "GainMapHDR",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "GainMapHDR", targets: ["GainMapHDRApp"])
    ],
    targets: [
        .executableTarget(
            name: "GainMapHDRApp",
            exclude: ["Resources/backend"],
            resources: [
                .process("Resources/en.lproj"),
                .process("Resources/zh-Hans.lproj")
            ]
        ),
        .testTarget(
            name: "GainMapHDRAppTests",
            dependencies: ["GainMapHDRApp"]
        )
    ]
)

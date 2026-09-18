// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "GainMapHDR",
    defaultLocalization: "en",
    platforms: [
        .macOS("27.0")
    ],
    products: [
        .executable(name: "GainMapHDR", targets: ["GainMapHDRApp"])
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-subprocess.git", exact: "1.0.0")
    ],
    targets: [
        .executableTarget(
            name: "GainMapHDRApp",
            dependencies: [.product(name: "Subprocess", package: "swift-subprocess")],
            exclude: ["Resources/backend"],
            resources: [
                .process("Resources/en.lproj"),
                .process("Resources/zh-Hans.lproj")
            ],
            swiftSettings: [.swiftLanguageMode(.v6), .unsafeFlags(["-strict-concurrency=complete"])]
        ),
        .testTarget(
            name: "GainMapHDRAppTests",
            dependencies: ["GainMapHDRApp"]
        )
    ]
)

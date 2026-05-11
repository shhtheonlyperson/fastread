// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "FastRead",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "FastReadCore", targets: ["FastReadCore"]),
        .executable(name: "FastReadCoreVerifier", targets: ["FastReadCoreVerifier"]),
        .executable(name: "FastReadPerformanceVerifier", targets: ["FastReadPerformanceVerifier"]),
        .executable(name: "FastReadTokenizerStats", targets: ["FastReadTokenizerStats"]),
    ],
    dependencies: [
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.19"),
    ],
    targets: [
        .target(
            name: "FastReadCore",
            dependencies: [
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
            ]
        ),
        .executableTarget(
            name: "FastReadCoreVerifier",
            dependencies: ["FastReadCore"],
            path: "Tools/FastReadCoreVerifier"
        ),
        .executableTarget(
            name: "FastReadPerformanceVerifier",
            dependencies: ["FastReadCore"],
            path: "Tools/FastReadPerformanceVerifier"
        ),
        .executableTarget(
            name: "FastReadTokenizerStats",
            dependencies: ["FastReadCore"],
            path: "Tools/FastReadTokenizerStats"
        ),
        .testTarget(
            name: "FastReadCoreTests",
            dependencies: ["FastReadCore"],
            path: "Tests",
            sources: ["FastReadCoreTests"],
            resources: [
                .copy("Fixtures"),
            ]
        ),
    ]
)

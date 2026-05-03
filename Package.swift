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
    ],
    targets: [
        .target(name: "FastReadCore"),
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
        .testTarget(
            name: "FastReadCoreTests",
            dependencies: ["FastReadCore"]
        ),
    ]
)

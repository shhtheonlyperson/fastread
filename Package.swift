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
    ],
    targets: [
        .target(name: "FastReadCore"),
        .executableTarget(
            name: "FastReadCoreVerifier",
            dependencies: ["FastReadCore"],
            path: "Tools/FastReadCoreVerifier"
        ),
    ]
)

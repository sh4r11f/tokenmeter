// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "TokenMeter",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "TokenMeterCore", targets: ["TokenMeterCore"]),
        .executable(name: "TokenMeter", targets: ["TokenMeter"]),
    ],
    targets: [
        .target(name: "TokenMeterCore"),
        .executableTarget(name: "TokenMeter", dependencies: ["TokenMeterCore"]),
        .testTarget(name: "TokenMeterCoreTests", dependencies: ["TokenMeterCore"]),
    ]
)

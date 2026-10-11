// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "UsagePace", platforms: [.macOS(.v14)], products: [
    .executable(name: "UsagePace", targets: ["UsagePace"])
], targets: [
    .target(name: "PaceCore"),
    .executableTarget(name: "UsagePace", dependencies: ["PaceCore"])
])

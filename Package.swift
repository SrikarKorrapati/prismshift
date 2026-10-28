// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "PrismShift",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "PrismShift", targets: ["PrismShift"])
    ],
    targets: [
        .executableTarget(
            name: "PrismShift",
            path: "Sources/PrismShift"
        )
    ],
    swiftLanguageModes: [.v5]
)

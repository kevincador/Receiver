// swift-tools-version:5.0
import PackageDescription

let package = Package(
    name: "Receiver",
    platforms: [
        .iOS(.v10),
        .macOS(.v10_12),
        .tvOS(.v10),
        .watchOS(.v3)
    ],
    products: [
        .library(
            name: "Receiver",
            targets: ["Receiver"]
        )
    ],
    targets: [
        .target(
            name: "Receiver",
            path: "Receiver/Sources"
        ),
        .testTarget(
            name: "ReceiverTests",
            dependencies: ["Receiver"],
            path: "ReceiverTests",
            exclude: ["Info.plist"]
        )
    ],
    swiftLanguageVersions: [.v5]
)

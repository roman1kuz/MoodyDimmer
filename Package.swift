// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "MoodyDimmer",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "MoodyDimmer",
            path: "Sources/MoodyDimmer",
            swiftSettings: [.unsafeFlags(["-Osize"], .when(configuration: .release))]
        )
    ]
)

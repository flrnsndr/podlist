// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PodlistKit",
    defaultLocalization: "en",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "PodlistKit", targets: ["PodlistKit"])
    ],
    targets: [
        .target(name: "PodlistKit"),
        .testTarget(
            name: "PodlistKitTests",
            dependencies: ["PodlistKit"],
            resources: [.copy("Fixtures")]
        ),
    ],
    swiftLanguageModes: [.v6]
)

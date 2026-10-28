// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "SpadesEngine",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "SpadesEngine", targets: ["SpadesEngine"]),
    ],
    targets: [
        .target(name: "SpadesEngine"),
        .testTarget(name: "SpadesEngineTests", dependencies: ["SpadesEngine"]),
    ]
)

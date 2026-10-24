// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TrafficReloader",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "TrafficReloader", targets: ["TrafficReloader"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "TrafficReloader",
            dependencies: [],
            path: "Sources/TrafficReloader"
        )
    ]
)

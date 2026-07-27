// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Mercury",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Mercury",
            path: "Sources/Mercury"
        )
    ]
)

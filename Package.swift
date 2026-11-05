// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Mercury",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")
    ],
    targets: [
        .executableTarget(
            name: "Mercury",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/Mercury",
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        )
    ]
)

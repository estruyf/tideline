// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Tideline",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Tideline",
            path: "Sources/Tideline"
        )
    ]
)

// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MultiClip",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "MultiClip",
            path: "Sources/MultiClip",
            linkerSettings: [.linkedLibrary("sqlite3")]
        )
    ]
)

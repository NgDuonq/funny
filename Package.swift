// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MusicIsland",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "MusicIsland", targets: ["MusicIsland"])],
    targets: [
        .target(name: "IslandCore"),
        .executableTarget(name: "MusicIsland", dependencies: ["IslandCore"], resources: [.process("Resources")]),
        .testTarget(name: "IslandCoreTests", dependencies: ["IslandCore"])
    ]
)

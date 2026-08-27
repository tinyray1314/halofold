// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "CodexIsland",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "CodexIsland", targets: ["CodexIsland"])
    ],
    targets: [
        .systemLibrary(
            name: "CSQLite",
            pkgConfig: "sqlite3",
            providers: [.brew(["sqlite3"]), .apt(["libsqlite3-dev"])]
        ),
        .executableTarget(
            name: "CodexIsland",
            dependencies: ["CSQLite"],
            path: "Sources/CodexIsland"
        ),
        .testTarget(
            name: "CodexIslandTests",
            dependencies: ["CodexIsland"],
            path: "Tests/CodexIslandTests"
        )
    ],
    swiftLanguageVersions: [.v5]
)

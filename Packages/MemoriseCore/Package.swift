// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MemoriseCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "MemoriseCore", targets: ["MemoriseCore"]),
    ],
    targets: [
        .target(
            name: "MemoriseCore",
            // `.copy` keeps the `Decks/` sub-directory intact inside the bundle.
            resources: [.copy("Resources/Decks"), .copy("Resources/Shapes")]
        ),
        .testTarget(name: "MemoriseCoreTests", dependencies: ["MemoriseCore"]),
    ],
    swiftLanguageModes: [.v6]
)

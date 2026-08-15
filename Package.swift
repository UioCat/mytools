// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "MacTools",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "MacTools", targets: ["MacTools"]),
        .library(name: "MacToolsCore", targets: ["MacToolsCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.29.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.5")
    ],
    targets: [
        .executableTarget(
            name: "MacTools",
            dependencies: [
                "MacToolsCore",
                .product(name: "Sparkle", package: "Sparkle")
            ],
            resources: [.process("Resources")]
        ),
        .target(
            name: "MacToolsCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ]
        ),
        .testTarget(
            name: "MacToolsCoreTests",
            dependencies: [
                "MacToolsCore",
                .product(name: "GRDB", package: "GRDB.swift")
            ]
        ),
        .testTarget(
            name: "MacToolsTests",
            dependencies: ["MacTools", "MacToolsCore"]
        )
    ]
)

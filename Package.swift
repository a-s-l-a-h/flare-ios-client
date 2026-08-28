// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "FlareClient",
    platforms: [
        .iOS(.v14)
    ],
    products: [
        .library(name: "FlareClient", targets: ["FlareClient"]),
        .library(name: "FlareClientExtensionsBuiltin", targets: ["FlareClientExtensionsBuiltin"])
    ],
    dependencies: [
        .package(url: "https://github.com/divkit/divkit-ios.git", exact: "32.52.0")
    ],
    targets: [
        .target(
            name: "FlareClient",
            dependencies: [
                .product(name: "DivKit", package: "divkit-ios")
            ],
            path: "FlareClient",
            sources: ["Sources"],
            resources: [
                .process("Resources")
            ]
        ),
        .target(
            name: "FlareClientExtensionsBuiltin",
            dependencies: ["FlareClient"],
            path: "FlareClientExtensionsBuiltin",
            sources: ["Sources"]
        )
    ]
)
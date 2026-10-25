// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "WhoSaidWhat",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(url: "https://github.com/Desert-Ant-Labs/desert-ant-core.git", from: "4.1.0"),
    ],
    targets: [
        .executableTarget(
            name: "WhoSaidWhat",
            dependencies: [
                .product(name: "Who", package: "desert-ant-core"),
                .product(name: "Voz", package: "desert-ant-core"),
                .product(name: "Ear", package: "desert-ant-core"),
                .product(name: "Tongue", package: "desert-ant-core"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(name: "WhoSaidWhatTests", dependencies: ["WhoSaidWhat"]),
        // SDK model downloads are confined to this build-time packaging tool.
        .executableTarget(name: "BundleModels", dependencies: [
            .product(name: "Who", package: "desert-ant-core"),
            .product(name: "Voz", package: "desert-ant-core"),
            .product(name: "Ear", package: "desert-ant-core"),
        ], path: "Tools/BundleModels", swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)

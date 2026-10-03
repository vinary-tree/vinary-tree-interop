// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "vinary-tree-interop",
    platforms: [.macOS(.v13)],
    products: [.library(name: "VinaryTreeInterop", targets: ["VinaryTreeInterop"])],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-docc-plugin", exact: "1.5.0"),
    ],
    targets: [
        .systemLibrary(name: "CVinaryTreeInterop"),
        .target(name: "VinaryTreeInterop", dependencies: ["CVinaryTreeInterop"]),
    ]
)

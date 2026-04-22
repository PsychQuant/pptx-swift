// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PPTXSwift",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PPTXSwift", targets: ["PPTXSwift"])
    ],
    dependencies: [
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.0"),
        .package(url: "https://github.com/PsychQuant/ooxml-swift.git", from: "0.7.0")
    ],
    targets: [
        .target(
            name: "PPTXSwift",
            dependencies: [
                "ZIPFoundation",
                .product(name: "OOXMLSwift", package: "ooxml-swift")
            ]
        ),
        .testTarget(
            name: "PPTXSwiftTests",
            dependencies: ["PPTXSwift"],
            resources: [.copy("Fixtures")]
        )
    ]
)

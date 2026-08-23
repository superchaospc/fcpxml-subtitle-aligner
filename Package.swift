// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FCPXMLSubtitleAligner",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "FCPXMLAlignerCore", targets: ["FCPXMLAlignerCore"]),
        .executable(name: "FCPXMLSubtitleAligner", targets: ["FCPXMLSubtitleAlignerApp"]),
        .executable(name: "fcpxml-aligner", targets: ["FCPXMLAlignerCLI"]),
    ],
    targets: [
        .target(name: "FCPXMLAlignerCore"),
        .executableTarget(name: "FCPXMLSubtitleAlignerApp", dependencies: ["FCPXMLAlignerCore"]),
        .executableTarget(name: "FCPXMLAlignerCLI", dependencies: ["FCPXMLAlignerCore"]),
        .testTarget(
            name: "FCPXMLAlignerCoreTests",
            dependencies: ["FCPXMLAlignerCore"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "FCPXMLSubtitleAlignerAppTests",
            dependencies: ["FCPXMLSubtitleAlignerApp"]
        ),
        .testTarget(
            name: "FCPXMLAlignerCLITests",
            dependencies: ["FCPXMLAlignerCLI", "FCPXMLAlignerCore"]
        ),
    ]
)

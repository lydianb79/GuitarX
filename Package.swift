// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "GuitarX",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "GuitarX",
            path: "Sources/GuitarX",
            linkerSettings: [
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreText")
            ]
        )
    ]
)

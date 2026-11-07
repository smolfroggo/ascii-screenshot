// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AsciiScreenshotKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "AsciiScreenshotKit", targets: ["AsciiScreenshotKit"]),
        .executable(name: "asciiscreenshot", targets: ["asciiscreenshot"]),
    ],
    targets: [
        .target(name: "AsciiScreenshotKit"),
        .executableTarget(name: "asciiscreenshot", dependencies: ["AsciiScreenshotKit"]),
        .testTarget(
            name: "AsciiScreenshotKitTests",
            dependencies: ["AsciiScreenshotKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)

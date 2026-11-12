// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SideReel",
    platforms: [.macOS(.v26)],
    targets: [
        .target(name: "SlideshowKit"),
        .executableTarget(name: "SideReel", dependencies: ["SlideshowKit"]),
        .executableTarget(name: "SlideshowSelfTest", dependencies: ["SlideshowKit"]),
    ],
    swiftLanguageModes: [.v5]
)
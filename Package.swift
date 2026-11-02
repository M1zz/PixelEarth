// swift-tools-version:5.9
// Pixel Earth — a Terraria-like 2D sandbox for macOS, built on SpriteKit with zero dependencies.
// Open this file in Xcode (File > Open… > Package.swift) and press Run, or use `swift run -c release`.
import PackageDescription

let package = Package(
    name: "PixelEarth",
    defaultLocalization: "ko",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "PixelEarth",
            path: "Sources/PixelEarth",
            resources: [.copy("Resources"), .process("Localizable.xcstrings")],
            swiftSettings: [
                // The world generator and light propagation are hot loops; keep them optimized even in Xcode's Debug scheme.
                .unsafeFlags(["-O"])
            ]
        )
    ]
)

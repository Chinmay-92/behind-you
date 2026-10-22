// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "BehindYou",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "behindyou",
            path: "Sources/BehindYou",
            linkerSettings: [
                // Embed Info.plist so macOS shows our camera usage string.
                .unsafeFlags([
                    "-Xlinker", "-sectcreate", "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist", "-Xlinker", "Support/Info.plist",
                ]),
            ]
        ),
    ],
    swiftLanguageModes: [.v5]
)

// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "papyrus_macos",
    platforms: [.macOS(.v10_15)],
    products: [
        .library(name: "papyrus-macos", targets: ["papyrus_macos"]),
    ],
    targets: [
        .target(
            name: "papyrus_macos",
            path: "../Classes",
            resources: [.process("../Resources")]
        ),
    ]
)

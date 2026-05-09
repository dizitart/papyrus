// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "papyrus_ios",
    platforms: [.iOS(.v12)],
    products: [
        .library(name: "papyrus-ios", targets: ["papyrus_ios"]),
    ],
    targets: [
        .target(
            name: "papyrus_ios",
            path: "../Classes",
            resources: [.process("../Resources")]
        ),
    ]
)

// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FixMyWordsCore",
    platforms: [.macOS("26.0")],
    products: [.library(name: "FixMyWordsCore", targets: ["FixMyWordsCore"])],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "3.1.0"),
    ],
    targets: [
        .target(name: "FixMyWordsCore", dependencies: ["KeyboardShortcuts"]),
    ]
)

// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "copymac-clipboard",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(name: "copymac-clipboard", targets: ["CopyMacClipboard"])
    ],
    targets: [
        .executableTarget(
            name: "CopyMacClipboard",
            path: "Sources"
        )
    ]
)

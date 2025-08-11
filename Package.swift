// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "copymac-clipboard",
    platforms: [
        .macOS(.v13)  // Changed from .v12 to .v13
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
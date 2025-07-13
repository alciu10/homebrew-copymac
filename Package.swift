// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MySwiftProject",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "MySwiftProject", targets: ["MySwiftProject"])
    ],
    targets: [
        .executableTarget(
            name: "MySwiftProject",
            path: "Sources"
        )
    ]
)
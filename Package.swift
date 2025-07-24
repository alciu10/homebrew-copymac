// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "GraMac",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(
            name: "GraMac",
            targets: ["GraMac"])
    ],
    targets: [
        .executableTarget(
            name: "GraMac",
            dependencies: [],
            path: "Sources",
            sources: ["main.swift"]
        )
    ]
)
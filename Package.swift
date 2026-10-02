// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "XKCDDiagrams",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "DiagramCore", targets: ["DiagramCore"]),
        .executable(name: "XKCDDiagrams", targets: ["DiagramApp"]),
        .executable(name: "diagram", targets: ["DiagramCLI"])
    ],
    targets: [
        .target(name: "DiagramCore", resources: [.copy("Resources")]),
        .executableTarget(name: "DiagramApp", dependencies: ["DiagramCore"]),
        .executableTarget(name: "DiagramCLI", dependencies: ["DiagramCore"]),
        .executableTarget(name: "DiagramChecks", dependencies: ["DiagramCore"], path: "Tests/DiagramChecks")
    ],
    swiftLanguageModes: [.v5]
)

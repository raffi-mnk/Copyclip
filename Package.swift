// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Copyclip",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Copyclip", targets: ["Copyclip"])],
    targets: [
        .executableTarget(name: "Copyclip", path: "Sources/Copyclip")
    ]
)

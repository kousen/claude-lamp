// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MoonsideAgentLamp", platforms: [.macOS(.v13)],
    products: [.executable(name: "MoonsideAgentLamp", targets: ["MoonsideAgentLamp"])],
    targets: [
        .target(name: "LampCore"),
        .executableTarget(name: "MoonsideAgentLamp", dependencies: ["LampCore"]),
        .executableTarget(name: "LampTests", dependencies: ["LampCore"], path: "Tests")
    ]
)

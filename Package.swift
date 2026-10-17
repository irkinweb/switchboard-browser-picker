// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Switchboard",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "SwitchboardCore"),
        .executableTarget(name: "Switchboard", dependencies: ["SwitchboardCore"]),
        .executableTarget(name: "SwitchboardSelfCheck", dependencies: ["SwitchboardCore"]),
    ],
    swiftLanguageModes: [.v5]
)

// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ShortcutsBar",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "ShortcutsBar", targets: ["ShortcutsBar"]),
        .library(name: "ShortcutsBarCore", targets: ["ShortcutsBarCore"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "ShortcutsBarCore",
            dependencies: [],
            path: "Sources/ShortcutsBarCore"
        ),
        .executableTarget(
            name: "ShortcutsBar",
            dependencies: ["ShortcutsBarCore"],
            path: "Sources/ShortcutsBar"
        ),
        .testTarget(
            name: "ShortcutsBarTests",
            dependencies: ["ShortcutsBarCore"],
            path: "Tests/ShortcutsBarTests"
        )
    ]
)

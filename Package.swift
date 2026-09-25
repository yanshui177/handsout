// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Handsout",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Handsout",
            path: "Sources/Handsout",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .linkedFramework("Cocoa"),
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement"),
            ]
        )
    ]
)

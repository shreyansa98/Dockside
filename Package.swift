// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Dockside",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Dockside",
            path: "Sources/Dockside",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("EventKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("WebKit"),
            ]
        )
    ]
)

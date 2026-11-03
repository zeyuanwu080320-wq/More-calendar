// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "SchoolEventInbox",
    defaultLocalization: "zh-Hans",
    platforms: [
        .macOS("15.0")
    ],
    products: [
        .executable(name: "SchoolEventInbox", targets: ["SchoolEventInbox"]),
        .executable(name: "SchoolEventInboxSelfTest", targets: ["SchoolEventInboxSelfTest"])
    ],
    targets: [
        .target(
            name: "SchoolEventInboxCore",
            path: "Sources/SchoolEventInboxCore"
        ),
        .executableTarget(
            name: "SchoolEventInbox",
            dependencies: ["SchoolEventInboxCore"],
            path: "Sources/SchoolEventInbox",
            resources: [
                .process("Resources")
            ]
        ),
        // The Command Line Tools installation on this Mac has no XCTest
        // framework, so local verification uses a dependency-free executable
        // harness. Release cleanup removed the XCTest fixtures/tests.
        .executableTarget(
            name: "SchoolEventInboxSelfTest",
            dependencies: ["SchoolEventInboxCore"],
            path: "Tests/SelfTest"
        )
    ]
)

// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "InterviewAssistant",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "InterviewAssistant",
            path: "App",
            exclude: ["Support"]
        ),
        .testTarget(
            name: "InterviewAssistantTests",
            dependencies: ["InterviewAssistant"],
            path: "Tests/InterviewAssistantTests"
        ),
    ]
)

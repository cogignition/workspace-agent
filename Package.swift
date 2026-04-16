// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "WorkspaceAgent",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        // Local LLM inference via llama.cpp with Swift async/await
        .package(url: "https://github.com/tattn/LocalLLMClient.git", branch: "main"),
    ],
    targets: [
        .executableTarget(
            name: "WorkspaceAgent",
            dependencies: [
                .product(name: "LocalLLMClient", package: "LocalLLMClient"),
                .product(name: "LocalLLMClientLlama", package: "LocalLLMClient"),
            ],
            path: "Sources/WorkspaceAgent",
            swiftSettings: [
                .interoperabilityMode(.Cxx)
            ]
        ),
        .testTarget(
            name: "WorkspaceAgentTests",
            dependencies: ["WorkspaceAgent"],
            path: "Tests/WorkspaceAgentTests",
            swiftSettings: [
                .interoperabilityMode(.Cxx)
            ]
        ),
    ]
)

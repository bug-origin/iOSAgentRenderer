// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "iOSAgentRenderer",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "AgentRendererCore", targets: ["AgentRendererCore"]),
        .library(name: "AgentRenderer", targets: ["AgentRenderer"]),
        .library(name: "AgentRendererExamples", targets: ["AgentRendererExamples"]),
        .executable(name: "renderer-snapshots", targets: ["RendererSnapshots"]),
        .executable(name: "renderer-validate", targets: ["RendererValidate"]),
    ],
    targets: [
        .target(name: "AgentRendererCore", resources: [.process("Resources")]),
        .target(name: "AgentRenderer", dependencies: ["AgentRendererCore"], resources: [.process("Resources")]),
        .target(name: "AgentRendererExamples", dependencies: ["AgentRendererCore", "AgentRenderer"], resources: [.process("Resources")]),
        .executableTarget(name: "RendererValidate", dependencies: ["AgentRendererCore"]),
        .executableTarget(name: "RendererSnapshots", dependencies: ["AgentRenderer", "AgentRendererExamples"]),
        .testTarget(name: "AgentRendererTests", dependencies: ["AgentRenderer", "AgentRendererExamples"]),
    ],
    swiftLanguageModes: [.v6]
)

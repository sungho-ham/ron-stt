// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WhisperPaste",
    defaultLocalization: "ko",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "WhisperPaste", targets: ["WhisperPaste"])],
    targets: [
        .target(name: "WhisperPasteCore", resources: [.process("Resources")]),
        .executableTarget(name: "WhisperPaste", dependencies: ["WhisperPasteCore"],
                          linkerSettings: [.linkedFramework("Carbon")]),
        .testTarget(name: "WhisperPasteCoreTests", dependencies: ["WhisperPasteCore"])
    ]
)

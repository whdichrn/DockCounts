// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "DockCounts", platforms: [.macOS(.v15)], products: [.executable(name: "DockCounts", targets: ["DockCounts"])], targets: [.executableTarget(name: "DockCounts", resources: [.process("Resources")]), .testTarget(name: "DockCountsTests", dependencies: ["DockCounts"])], swiftLanguageModes: [.v5])

// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "KotobaOverlay", platforms: [.macOS("27.0")], products: [.executable(name: "KotobaOverlay", targets: ["KotobaOverlay"])], targets: [.executableTarget(name: "KotobaOverlay", swiftSettings: [.enableUpcomingFeature("StrictConcurrency")]), .testTarget(name: "KotobaOverlayTests", dependencies: ["KotobaOverlay"])], swiftLanguageModes: [.v5])

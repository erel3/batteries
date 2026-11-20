// swift-tools-version:6.2
import PackageDescription

let swift6: [SwiftSetting] = [.swiftLanguageMode(.v6)]

let package = Package(
  name: "Batteries",
  platforms: [.macOS(.v15)],
  products: [
    .library(name: "BatteriesCore", targets: ["BatteriesCore"]),
    .executable(name: "batteries", targets: ["batteries"]),
    .executable(name: "BatteriesApp", targets: ["BatteriesApp"]),
    .executable(name: "BatteriesWidget", targets: ["BatteriesWidget"])
  ],
  targets: [
    .target(name: "BatteriesCore", path: "Sources/BatteriesCore", swiftSettings: swift6),
    .target(name: "BatteriesUI", dependencies: ["BatteriesCore"], path: "Sources/BatteriesUI", swiftSettings: swift6),
    .executableTarget(name: "batteries", dependencies: ["BatteriesCore"], path: "Sources/batteries", swiftSettings: swift6),
    // The agent app; `just app` wraps it and the widget into dist/Batteries.app.
    .executableTarget(
      name: "BatteriesApp",
      dependencies: ["BatteriesCore", "BatteriesUI"],
      path: "Sources/BatteriesApp",
      swiftSettings: swift6
    ),
    // The WidgetKit extension's binary. Extensions may only use extension-safe API.
    .executableTarget(
      name: "BatteriesWidget",
      dependencies: ["BatteriesCore", "BatteriesUI"],
      path: "Sources/BatteriesWidget",
      swiftSettings: swift6 + [.unsafeFlags(["-application-extension"])],
      // Xcode links every extension with entry point _NSExtensionMain: it sets up ExtensionFoundation,
      // then runs the @main Widget. Entered at main directly, the widget traps at launch.
      linkerSettings: [.unsafeFlags(["-Xlinker", "-application_extension", "-Xlinker", "-e", "-Xlinker", "_NSExtensionMain"])]
    ),
    .testTarget(name: "BatteriesCoreTests", dependencies: ["BatteriesCore"], path: "Tests/BatteriesCoreTests", swiftSettings: swift6),
    .testTarget(name: "BatteriesUITests", dependencies: ["BatteriesUI"], path: "Tests/BatteriesUITests", swiftSettings: swift6),
    .testTarget(name: "BatteriesAppTests", dependencies: ["BatteriesApp"], path: "Tests/BatteriesAppTests", swiftSettings: swift6)
  ]
)

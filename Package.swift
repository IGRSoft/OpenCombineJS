// swift-tools-version:6.3
import PackageDescription
let package = Package(
  name: "OpenCombineJS",
  platforms: [
    .macOS(.v15),
    .iOS(.v18),
  ],
  products: [
    .executable(name: "OpenCombineJSExample", targets: ["OpenCombineJSExample"]),
    .library(name: "OpenCombineJS", targets: ["OpenCombineJS"]),
  ],
  dependencies: [
    .package(
      url: "https://github.com/swiftwasm/JavaScriptKit.git",
      from: "0.54.1"
    ),
    .package(url: "https://github.com/OpenCombine/OpenCombine.git", from: "0.14.0"),
  ],
  targets: [
    .target(
      name: "OpenCombineJSExample",
      dependencies: [
        "OpenCombineJS",
      ]
    ),
    .target(
      name: "OpenCombineJS",
      dependencies: [
        "JavaScriptKit", "OpenCombine",
      ]
    ),
  ],
  swiftLanguageModes: [.v5]
)

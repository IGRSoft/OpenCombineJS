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
    .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.4.0"),
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
    .testTarget(
      name: "OpenCombineJSTests",
      dependencies: [
        "OpenCombineJS",
        "JavaScriptKit",
        "OpenCombine",
        // Installs the JavaScriptEventLoop global executor at startup so async tests can be
        // resumed by JS timers/promises. Only meaningful (and only linked) on WASI.
        .product(
          name: "JavaScriptEventLoopTestSupport",
          package: "JavaScriptKit",
          condition: .when(platforms: [.wasi])
        ),
        // Provides `JSPromise.value` (async) consumed by the differential tests (#13).
        .product(
          name: "JavaScriptEventLoop",
          package: "JavaScriptKit",
          condition: .when(platforms: [.wasi])
        ),
      ]
    ),
  ],
  swiftLanguageModes: [.v6]
)

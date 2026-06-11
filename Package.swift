// swift-tools-version:6.3
import PackageDescription

/// Platforms WITHOUT native Combine (`#if canImport(Combine)` is false there, so the
/// sources fall back to `import OpenCombine` — see JSPromise.swift, #11/#15).
/// Must list EVERY non-Apple platform PackageDescription 6.3 exposes, not just .wasi:
/// dropping one (e.g. .linux) would silently unlink OpenCombine for its consumers and
/// break their builds.  (.freebsd exists in the 6.3 swiftinterface but is gated
/// @available(_PackageDescription 999.0) and therefore not usable yet.)
/// On Apple platforms the condition keeps OpenCombine out of the build graph entirely:
/// it is still FETCHED at dependency-resolution time, but never compiled or linked.
let openCombinePlatforms: [Platform] = [.wasi, .linux, .android, .windows, .openbsd]

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
        .product(
          name: "OpenCombine",
          package: "OpenCombine",
          condition: .when(platforms: openCombinePlatforms)
        ),
      ]
    ),
    .target(
      name: "OpenCombineJS",
      dependencies: [
        "JavaScriptKit",
        .product(
          name: "OpenCombine",
          package: "OpenCombine",
          condition: .when(platforms: openCombinePlatforms)
        ),
      ]
    ),
    .testTarget(
      name: "OpenCombineJSTests",
      dependencies: [
        "OpenCombineJS",
        "JavaScriptKit",
        .product(
          name: "OpenCombine",
          package: "OpenCombine",
          condition: .when(platforms: openCombinePlatforms)
        ),
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

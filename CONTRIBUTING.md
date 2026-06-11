# Contributing to OpenCombineJS

## Build & test

Two lanes must stay green ([ci.yml](.github/workflows/ci.yml)). The host lane builds against
native Combine, the wasm lane against OpenCombine (`#if canImport(Combine)`, #11).

**Host (macOS, Swift 6.3+ via Xcode):**

```console
swift build
swift test          # host-runnable tests; wasm-only suites self-gate via #if os(WASI)
```

**Wasm (official swift.org toolchain + version-matched wasm Swift SDK, Node ≥ 20):**

```console
# One-time: install the wasm SDK matching your swift.org toolchain version, e.g.
swift sdk install "https://download.swift.org/swift-6.3.2-release/wasm-sdk/swift-6.3.2-RELEASE/swift-6.3.2-RELEASE_wasm.artifactbundle.tar.gz" --checksum <official-sha256>

swift build --swift-sdk swift-6.3.2-RELEASE_wasm --build-tests
swift package --disable-sandbox --swift-sdk swift-6.3.2-RELEASE_wasm js test
```

Notes:

- The Xcode toolchain has no wasm backend — select a swift.org toolchain for wasm builds
  (e.g. `TOOLCHAINS=org.swift.<id> swift build …` on macOS). Toolchain and SDK versions must
  match exactly; checksums live in [ci.yml](.github/workflows/ci.yml).
- **Never mix Xcode and swift.org toolchains in one `.build`** — their host-tool modules are
  incompatible. Run `swift package clean` whenever you switch between host and wasm invocations.
- `js test` needs `--disable-sandbox` (the PackageToJS plugin runs npm) and the default scratch
  path (no `--scratch-path`).
- Run `swiftformat --lint .` (repo `.swiftformat`: 2-space indent) before committing; new Swift
  files carry the Apache header.

## Dependency version policy

- Minimum **JavaScriptKit 0.54.1** (ships `JSPromise.value`, required by the async bridge, #13).
- **OpenCombine is platform-conditional** (#15): the product dependency carries
  `condition: .when(platforms: [.wasi, .linux, .android, .windows, .openbsd])` — every
  non-Apple platform the 6.3 `PackageDescription` exposes. On Apple platforms the sources use
  native Combine (`#if canImport(Combine)`, #11) and OpenCombine is neither compiled nor
  linked; it is still fetched at resolution time because the package-level declaration stays.
  When editing the platform list, keep it in sync with "platforms where `canImport(Combine)`
  is false" — dropping one silently breaks that platform's build. Full removal of the
  declaration is deferred until the Publisher surface is retired.
- Weekly canaries ([canary-upstreams.yml](.github/workflows/canary-upstreams.yml)) build against
  the latest JavaScriptKit release and OpenCombine main. They are allowed to fail and auto-file
  `canary-failure` issues instead of breaking CI. Note the OpenCombine canary must build the
  **wasm lane** — a macOS host build no longer compiles OpenCombine at all.
- The moment JavaScriptKit ships a native `TopLevelDecoder` conformance, our retroactive one
  becomes a duplicate-conformance build error: delete `Sources/OpenCombineJS/JSValueDecoder.swift`
  and tag a minor release (#9). The JSKit canary exists to catch this early.

## Release & semver policy

- Every PR is gated by [api-contract.yml](.github/workflows/api-contract.yml):
  `swift package diagnose-api-breaking-changes` against the **PR's base branch** — the gate
  catches breakage introduced by the PR, not historical breakage.
- Intentional breaking changes must be **declared** in `CHANGELOG.md` (under
  `# Unreleased (x.y.z)`) with the matching semver bump — never hidden.
- Cutting a release: run the digester against the last release tag, declare every reported
  change, stamp the `Unreleased` CHANGELOG section with version + date, then tag.

## Code of conduct

This project follows the [SwiftWasm Code of Conduct](https://github.com/swiftwasm/.github/blob/main/CODE_OF_CONDUCT.md).

# 0.5.0 (2026-06-11)

**Additions (strictly non-breaking — the public API is additive only):**

- New virtual-clock seam for deterministic scheduling: the `JSClockSource` protocol
  (current time + a timer factory mirroring `JSTimer`'s shape, returning a
  `JSClockCancellable` token) and the production `DefaultJSClockSource` backed by
  `JSDate.now()`/`JSTimer`. `JSScheduler` routes every scheduling path — immediate,
  one-shot, repeating, and the async `sleep(for:)`/`timer(interval:)` bridges — through
  the seam. The new `JSScheduler.init(clock:)` injects a custom clock; the existing
  `init()` is unchanged and keeps the default behavior
  ([#14](https://github.com/IGRSoft/OpenCombineJS/issues/14))
- Deterministic scheduler tests via a manually advanced `VirtualClock` test double; the
  exact-value timing suites need no JavaScript runtime and now run on the host lane as
  well as on wasm ([#14](https://github.com/IGRSoft/OpenCombineJS/issues/14))

**Documentation:**

- `JSScheduler`'s concurrency model is now an explicit documented contract: the class is
  intentionally **not** `Sendable` (its unsynchronized state is only safe on the
  single-threaded JS event loop, and Apple-side Combine could legally call a `Sendable`
  scheduler from arbitrary threads, so `@unchecked Sendable` was evaluated and rejected).
  The module overview gains a "Deterministic testing" guide for the clock seam
  ([#14](https://github.com/IGRSoft/OpenCombineJS/issues/14))

# 0.4.0 (2026-06-11)

**Declared change — Apple platforms only:**

- The library now builds against **native Combine** on Apple platforms via
  `#if canImport(Combine)`; WASI (and any platform without Combine) keeps OpenCombine.
  Apple consumers receive native `Future`, `AnyCancellable`, `Scheduler`, and
  `TopLevelDecoder` types from `JSPromise.publisher`, `JSScheduler`, and `JSValueDecoder`.
  This changes type identity on Apple platforms (e.g. `PromisePublisher` now conforms to
  `Combine.Publisher` instead of `OpenCombine.Publisher`) and is a declared break for any
  Apple-platform consumer that pipelined these types into OpenCombine operators. WASI/WASM
  consumers are unaffected. The package still depends on OpenCombine unconditionally;
  full removal is tracked for 1.0 ([#11](https://github.com/IGRSoft/OpenCombineJS/issues/11),
  [#15](https://github.com/IGRSoft/OpenCombineJS/issues/15))

**Additions:**

- Async/await bridge APIs alongside the Combine publishers (strictly additive — nothing is
  deprecated): `JSScheduler.sleep(for:)` suspends via a one-shot `setTimeout`, and
  `JSScheduler.timer(interval:)` returns an `AsyncStream` of repeating `setInterval` ticks
  whose termination cancels the underlying JS timer. JavaScriptKit's existing
  `JSPromise.value` (`JavaScriptEventLoop` module) is documented as the async counterpart
  of `.publisher`. New wasm-gated differential tests prove the legacy Combine path and the
  new async path yield identical outcomes for the same inputs
  ([#13](https://github.com/IGRSoft/OpenCombineJS/issues/13))
- `CONTRIBUTING.md` with host/wasm build-and-test instructions (including the
  toolchain-mixing warning), the dependency version policy (minimum JavaScriptKit 0.54.1,
  weekly upstream canaries, the `JSValueDecoder` deletion trigger), and the release/semver
  policy ([#12](https://github.com/IGRSoft/OpenCombineJS/issues/12))

# 0.3.0 (2026-06-11)

This release fixes four long-standing `JSScheduler` bugs and adds the package's first automated
test suite.

**Fixed bugs:**

- `SchedulerTimeType.Stride.microseconds(_:)` and `.nanoseconds(_:)` returned the reciprocal of
  the correct duration; they now convert to milliseconds correctly
  ([#2](https://github.com/IGRSoft/OpenCombineJS/issues/2))
- Cancelling the `Cancellable` returned by `schedule(after:interval:tolerance:options:_:)` before
  the first fire crashed on a force-unwrapped `nil` timer and left the pending timeout running;
  cancellation is now safe at any point (before the first fire, between fires, and when called
  repeatedly) and stops both timers
  ([#3](https://github.com/IGRSoft/OpenCombineJS/issues/3))
- One-shot timers were never removed from the scheduler's internal storage because their cleanup
  closures captured a still-`nil` timer reference, leaking every timer; timers are now tracked by
  value tokens and removed after firing or on cancellation
  ([#4](https://github.com/IGRSoft/OpenCombineJS/issues/4))
- The repeating schedule's interval timer was created as a one-shot `setTimeout` and fired only
  once; it now passes `isRepeating: true` and fires repeatedly at the requested cadence
  ([#5](https://github.com/IGRSoft/OpenCombineJS/issues/5))

**Additions:**

- New `OpenCombineJSTests` test target using Swift Testing: host-runnable
  `SchedulerTimeType`/`Stride` tests plus wasm-gated suites covering `JSScheduler` runtime
  behavior, `JSPromise.publisher`, and the `JSValueDecoder` `TopLevelDecoder` conformance.
  Run on wasm with `swift package --swift-sdk <wasm-sdk> js test` (Node.js required)
  ([#7](https://github.com/IGRSoft/OpenCombineJS/issues/7))
- `Sources/OpenCombineJSExample/main.swift` modernized: all force unwraps replaced with
  `guard`/`if-let` and graceful error messages displayed in the DOM; added comments
  explaining the JS event-loop execution context; README example block updated to match
  ([#8](https://github.com/IGRSoft/OpenCombineJS/issues/8))
- `JSValueDecoder.swift` now carries a documentation comment explaining the retroactive
  `TopLevelDecoder` conformance, the duplicate-conformance build-break risk, and the
  maintenance action required if JavaScriptKit or OpenCombine ever ships the conformance
  natively; audited against JavaScriptKit 0.54.1 (2026-06-11)
  ([#9](https://github.com/IGRSoft/OpenCombineJS/issues/9))
- DocC `///` documentation added to all previously undocumented public symbols across
  `JSPromise.swift`, `JSScheduler.swift`, and `JSValueDecoder.swift`; new
  `Sources/OpenCombineJS/Documentation.docc/OpenCombineJS.md` landing page with overview,
  quick-start snippet, and Topics section; `swift-docc-plugin` 1.4.0 added to Package.swift
  ([#10](https://github.com/IGRSoft/OpenCombineJS/issues/10))

# 0.2.0 (5 April 2022)

This release updates dependencies on OpenCombine and JavaScriptKit to their 0.13.0 versions.

# 0.1.2 (22 November 2021)

This is a bugfix release that fixes infinite recursion in the use of `JSValueDecoder`.

**Merged pull requests:**

- Fix infinite recursion in `JSValueDecoder` ([#6](https://github.com/swiftwasm/OpenCombineJS/pull/6)) via [@MaxDesiatov](https://github.com/MaxDesiatov)

# 0.1.1 (22 January 2021)

This release uses upstream OpenCombine 0.12.0 instead of an OpenCombine fork as it did previously.

# 0.1.0 (22 January 2021)

This release adds compatibility with JavaScriptKit 0.10, which removes generic parameters from the
`JSPromise` type.

**Merged pull requests:**

- Update `JSPromise` publisher for JSKit 0.10 ([#4](https://github.com/swiftwasm/OpenCombineJS/pull/4)) via [@MaxDesiatov](https://github.com/MaxDesiatov)

# 0.0.1 (24 November 2020)

Initial release of OpenCombineJS with `JSScheduler`, `TopLevelDecoder` implementation on
`JSValueDecoder`, and a `publisher` property on `JSPromise`.

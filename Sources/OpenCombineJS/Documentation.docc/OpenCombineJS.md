# ``OpenCombineJS``

Combine and async/await helpers for JavaScriptKit/WebAssembly APIs.

## Overview

OpenCombineJS bridges [JavaScriptKit](https://github.com/swiftwasm/JavaScriptKit) and the
Combine ecosystem so you can use idiomatic Combine pipelines — and their async/await
counterparts — in browser-targeting Swift packages compiled to WebAssembly (WASM).

The library provides these components:

| Component | Description |
|---|---|
| ``JSScheduler`` | A Combine `Scheduler` backed by `setTimeout`/`setInterval` that enables time-based operators in the browser. |
| ``JSScheduler/sleep(for:)`` / ``JSScheduler/timer(interval:)`` | Async/await counterparts of the scheduling APIs: a one-shot JS-timer delay and an `AsyncStream` of repeating ticks. |
| ``JSClockSource`` | The injectable time-and-timer seam behind ``JSScheduler``; swap in a virtual clock for deterministic tests. ``DefaultJSClockSource`` is the production implementation. |
| `JSPromise.publisher` | A `Publisher` property on `JSPromise` that resolves or rejects in lock-step with the underlying JavaScript `Promise`. Its async counterpart is JavaScriptKit's `JSPromise.value` (`import JavaScriptEventLoop`). |
| `JSValueDecoder` (`TopLevelDecoder`) | A retroactive conformance that lets `JSValueDecoder` work with the `.decode(type:decoder:)` Combine operator. |

### Combine on Apple platforms, OpenCombine on WASI

The library selects its Combine backend at compile time (`#if canImport(Combine)`): on
Apple platforms it builds against the **native Combine framework**, so `JSPromise.publisher`,
``JSScheduler``, and the `JSValueDecoder` conformance vend native `Combine` types; on WASI
(and any platform without Combine) it builds against
[OpenCombine](https://github.com/OpenCombine/OpenCombine). The two modules mirror each other
symbol-for-symbol — only the module identity differs, so the same consumer code compiles on
both backends.

### Async/await usage

`await`-based APIs require the `JavaScriptEventLoop` global executor on WASI
(`JavaScriptEventLoop.installGlobalExecutor()`), so suspended tasks are resumed by JS
timers and promises:

```swift
import JavaScriptEventLoop

JavaScriptEventLoop.installGlobalExecutor()

let value = try await promise.value            // async counterpart of .publisher

let scheduler = JSScheduler()
await scheduler.sleep(for: .milliseconds(300)) // one-shot setTimeout delay

for await _ in scheduler.timer(interval: .seconds(1)) {  // repeating setInterval ticks
  refresh()
}
```

The Combine surface is not deprecated: publishers and async APIs are supported side by side.

### Deterministic testing with a custom clock

``JSScheduler`` performs all time observation and timer creation through the ``JSClockSource``
seam. ``JSScheduler/init()`` uses ``DefaultJSClockSource`` (`JSDate.now()` + `JSTimer`);
``JSScheduler/init(clock:)`` accepts any conforming implementation. Because **every**
scheduling path flows through the seam — immediate, one-shot, repeating, and the async
``JSScheduler/sleep(for:)``/``JSScheduler/timer(interval:)`` bridges — injecting a manually
advanced clock makes scheduler behavior fully deterministic: no real timers, no jitter
tolerance bands, and no JavaScript runtime required, so such tests can run on any platform:

```swift
final class VirtualClock: JSClockSource {
  private(set) var now: Double = 0
  // makeTimer(millisecondsDelay:isRepeating:callback:) records pending timers;
  // advance(by:) fires the due ones in order and moves `now`.
}

let clock = VirtualClock()
let scheduler = JSScheduler(clock: clock)

var fired = false
scheduler.schedule(
  after: scheduler.now.advanced(by: .milliseconds(50)),
  tolerance: scheduler.minimumTolerance,
  options: nil
) { fired = true }

clock.advance(by: 49) // fired == false — not due yet
clock.advance(by: 1) //  fired == true  — exactly on time
```

The package's own test suite contains a complete reference implementation
(`Tests/OpenCombineJSTests/VirtualClock.swift`) that mirrors JavaScript timer semantics:
due-time ordering with creation-order ties, negative delays clamping to zero, and repeating
timers firing once per elapsed period.

### JavaScript event-loop context

All code in OpenCombineJS runs on the single-threaded JavaScript event loop. There is no
multi-threading, no POSIX signals, and no async/await suspension across JS frames. Timer
callbacks and promise resolutions are delivered by the browser's scheduler; top-level
executable code only needs to register state and return — execution continues via the event
loop thereafter.

Because of this invariant, none of the types exposed by OpenCombineJS are `Sendable`; they
must not cross Swift concurrency domains.

### Quick start

The example below runs a repeating timer that fetches a UUID from a remote server, decodes
it, and renders the result into a DOM paragraph element:

```swift
import JavaScriptKit
import OpenCombine
import OpenCombineJS

let document = JSObject.global.document
var p = document.createElement("p")
_ = document.body.appendChild(p)

var subscription: AnyCancellable?

let timer = JSTimer(millisecondsDelay: 1000, isRepeating: true) {
  guard let fetchFn = JSObject.global.fetch.function,
        let promiseObj = fetchFn("https://httpbin.org/uuid").object,
        let fetchPromise = JSPromise(promiseObj) else { return }

  subscription = fetchPromise
    .publisher
    .flatMap { responseValue -> JSPromise.PromisePublisher in
      guard let obj = responseValue.object,
            let jsonFn = obj.json.function,
            let jsonObj = jsonFn().object,
            let jsonPromise = JSPromise(jsonObj) else {
        return JSPromise(resolver: { resolve in
          resolve(.failure(JSPromise.PromiseError(.string("bad response"))))
          return .undefined
        }).publisher
      }
      return jsonPromise.publisher
    }
    .mapError { $0 as Error }
    .map { jsonValue -> Result<String, Error> in
      if let uuid = jsonValue.uuid.string { return .success(uuid) }
      return .failure(DecodingError.valueNotFound(String.self,
          .init(codingPath: [], debugDescription: "uuid field missing")))
    }
    .catch { Just(.failure($0)) }
    .sink { result in
      let time = JSDate().toLocaleTimeString()
      switch result {
      case let .success(uuid): p.innerText = .string("At \(time) uuid \(uuid)")
      case let .failure(error): p.innerText = .string("At \(time) error \(error)")
      }
    }
}
```

## Topics

### Scheduling

- ``JSScheduler``
- ``JSScheduler/SchedulerTimeType``
- ``JSScheduler/SchedulerTimeType/Stride``
- ``JSScheduler/SchedulerOptions``

### Async Scheduling

- ``JSScheduler/sleep(for:)``
- ``JSScheduler/timer(interval:)``

### Clock Injection

- ``JSClockSource``
- ``JSClockCancellable``
- ``DefaultJSClockSource``
- ``JSScheduler/init(clock:)``

### JavaScript Promise Integration

OpenCombineJS extends `JSPromise` (from JavaScriptKit) with a `publisher` property and two
nested types: `JSPromise.PromisePublisher` (the Combine publisher) and `JSPromise.PromiseError`
(the typed rejection wrapper). Because `JSPromise` is declared in JavaScriptKit, its extension
members appear in the inherited-symbols section of the generated archive rather than here.

The async counterpart of `.publisher` is `JSPromise.value` (`get async throws(JSException)`),
shipped by JavaScriptKit's `JavaScriptEventLoop` module — not by this package. Both paths
observe the same promise settlement; on rejection the raw JS reason is available as
`PromiseError.value` (publisher path) or `JSException.thrownValue` (async path).

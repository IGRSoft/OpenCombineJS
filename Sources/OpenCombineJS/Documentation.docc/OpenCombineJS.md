# ``OpenCombineJS``

OpenCombine helpers for JavaScriptKit/WebAssembly APIs.

## Overview

OpenCombineJS bridges [JavaScriptKit](https://github.com/swiftwasm/JavaScriptKit) and
[OpenCombine](https://github.com/OpenCombine/OpenCombine) so you can use idiomatic Combine
pipelines in browser-targeting Swift packages compiled to WebAssembly (WASM).

The library provides three components:

| Component | Description |
|---|---|
| ``JSScheduler`` | A Combine `Scheduler` backed by `setTimeout`/`setInterval` that enables time-based operators in the browser. |
| `JSPromise.publisher` | A `Publisher` property on `JSPromise` that resolves or rejects in lock-step with the underlying JavaScript `Promise`. |
| `JSValueDecoder` (`TopLevelDecoder`) | A retroactive conformance that lets `JSValueDecoder` work with the `.decode(type:decoder:)` Combine operator. |

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

### JavaScript Promise Integration

OpenCombineJS extends `JSPromise` (from JavaScriptKit) with a `publisher` property and two
nested types: `JSPromise.PromisePublisher` (the Combine publisher) and `JSPromise.PromiseError`
(the typed rejection wrapper). Because `JSPromise` is declared in JavaScriptKit, its extension
members appear in the inherited-symbols section of the generated archive rather than here.

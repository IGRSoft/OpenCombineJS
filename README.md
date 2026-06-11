# OpenCombineJS

[OpenCombine](https://github.com/OpenCombine/OpenCombine) helpers for JavaScriptKit/WebAssembly
APIs. Currently it provides:

- A `JSScheduler` class that implements [the `Scheduler`
  protocol](https://developer.apple.com/documentation/combine/scheduler). This allows you to use
  time-dependent Combine operators such as
  [`measureInterval`](<https://developer.apple.com/documentation/combine/publisher/measureinterval(using:options:)>),
  [`debounce`](<https://developer.apple.com/documentation/combine/publisher/debounce(for:scheduler:options:)>),
  [`throttle`](<https://developer.apple.com/documentation/combine/publisher/throttle(for:scheduler:latest:)>),
  and
  [`timeout`](<https://developer.apple.com/documentation/combine/publisher/timeout(_:scheduler:options:customerror:)>)
  in the browser environment.
- A [`TopLevelDecoder`](https://developer.apple.com/documentation/combine/topleveldecoder)
  implementation on [`JSValueDecoder`](https://swiftwasm.github.io/JavaScriptKit/JSValueDecoder/).
- A `publisher` property on [`JSPromise`](https://swiftwasm.github.io/JavaScriptKit/JSPromise/),
  which converts your [JavaScript `Promise`](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Promise) instances to Combine publishers.

On Apple platforms the library builds against the **native Combine framework and links no
OpenCombine at all** — the OpenCombine dependency is declared platform-conditionally, so Apple
consumers get a zero-OpenCombine build (it is still fetched at dependency-resolution time). On
WASI, Linux, and other platforms without Combine it builds against
[OpenCombine](https://github.com/OpenCombine/OpenCombine).

## Example

Here's an example of a timer that fetches a UUID from a remote server every second, parses it
with `JSValueDecoder`, and then displays the result as text:

```swift
import JavaScriptKit
import OpenCombine
import OpenCombineJS

// All code runs on the single-threaded JS event loop — no concurrency needed.
let document = JSObject.global.document
var p = document.createElement("p")
_ = document.body.appendChild(p)

// Holds the active subscription across timer ticks; reassignment cancels the previous one.
var subscription: AnyCancellable?

// JSTimer wraps setInterval; the closure fires every 1 000 ms on the event loop.
let timer = JSTimer(millisecondsDelay: 1000, isRepeating: true) {
  // Resolve `fetch` safely — no force unwrap.
  guard
    let fetchFn = JSObject.global.fetch.function,
    let promiseObj = fetchFn("https://httpbin.org/uuid").object,
    let fetchPromise = JSPromise(promiseObj)
  else {
    p.innerText = .string("fetch unavailable")
    return
  }

  subscription = fetchPromise
    .publisher
    // Chain the .json() call, again without force unwraps.
    .flatMap { responseValue -> JSPromise.PromisePublisher in
      guard
        let obj = responseValue.object,
        let jsonFn = obj.json.function,
        let jsonObj = jsonFn().object,
        let jsonPromise = JSPromise(jsonObj)
      else {
        return JSPromise(resolver: { resolve in
          resolve(.failure(JSPromise.PromiseError(.string("Unexpected response shape"))))
          return .undefined
        }).publisher
      }
      return jsonPromise.publisher
    }
    .mapError { $0 as Error }
    .map { jsonValue -> Result<String, Error> in
      if let uuid = jsonValue.uuid.string {
        return .success(uuid)
      }
      return .failure(DecodingError.valueNotFound(
        String.self,
        .init(codingPath: [], debugDescription: "uuid field missing or not a string")
      ))
    }
    .catch { Just(.failure($0)) }
    .sink { result in
      let time = JSDate().toLocaleTimeString()
      switch result {
      case let .success(uuid):
        p.innerText = .string("At \(time) received uuid \(uuid)")
      case let .failure(error):
        // Short, user-facing message in the DOM; full error in the dev console.
        JSObject.global.console.error("fetch pipeline failed: \(error)")
        p.innerText = .string("At \(time) the request failed — see console for details")
      }
    }
}
```

### Code of Conduct

This project adheres to the [Contributor Covenant Code of
Conduct](https://github.com/swiftwasm/.github/blob/main/CODE_OF_CONDUCT.md).
By participating, you are expected to uphold this code. Please report
unacceptable behavior to hello@swiftwasm.org.

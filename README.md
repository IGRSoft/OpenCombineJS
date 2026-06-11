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
        // `Response.json` must be called with the response as `this`.
        let jsonObj = jsonFn(this: obj).object,
        let jsonPromise = JSPromise(jsonObj)
      else {
        return JSPromise(resolver: { resolve in
          // Resolver rejection value is a raw JSValue (boxed into PromiseError downstream).
          resolve(.failure(.string("Unexpected response shape")))
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

## Running the example

The example is a WebAssembly program: it needs a browser. It cannot run as a native
process on macOS or an iOS simulator — JavaScriptKit's native builds exist only for
editor/type-checking support (the JS bridge is compiled `#if __wasm32__`), so a native
launch aborts immediately.

1. Bundle for the browser (requires the official wasm Swift SDK matching your toolchain,
   e.g. `swift-6.3.2-RELEASE_wasm`):

   ```console
   swift package --disable-sandbox --swift-sdk swift-6.3.2-RELEASE_wasm \
     js --use-cdn --product OpenCombineJSExample
   ```

2. Put an `index.html` next to the produced bundle
   (`.build/plugins/PackageToJS/outputs/Package/`):

   ```html
   <script type="module">
     import { init } from "./index.js";
     await init();
   </script>
   ```

3. Serve the bundle directory and open it — any browser works, including Safari inside
   a booted iOS simulator:

   ```console
   python3 -m http.server 8741 --directory .build/plugins/PackageToJS/outputs/Package
   open http://127.0.0.1:8741/index.html                          # host browser
   xcrun simctl openurl booted http://127.0.0.1:8741/index.html   # iOS Simulator Safari
   ```

`--use-cdn` resolves the WASI shim dependency from a CDN; without it, browsers cannot
resolve the bundle's bare `@bjorn3/browser_wasi_shim` import unless you `npm install`
in the output directory and serve through a bundler.

### Code of Conduct

This project adheres to the [Contributor Covenant Code of
Conduct](https://github.com/swiftwasm/.github/blob/main/CODE_OF_CONDUCT.md).
By participating, you are expected to uphold this code. Please report
unacceptable behavior to hello@swiftwasm.org.

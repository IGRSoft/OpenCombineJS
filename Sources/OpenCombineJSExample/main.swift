// Copyright 2020 OpenCombineJS contributors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

// This file is the executable entry point for the OpenCombineJS WebAssembly example.
// It runs entirely on the JavaScript event loop: there is no multi-threading, no
// async/await suspension across JS frames, and no POSIX signal handling. `JSTimer`
// callbacks are invoked by the browser's scheduler, so the top-level code only needs
// to register state and return — execution continues via the event loop thereafter.

import JavaScriptKit
import OpenCombine
import OpenCombineJS

// MARK: - Helpers

/// Wraps the browser's `fetch` global as a typed Swift function.
///
/// Returns `nil` and prints a diagnostic if `window.fetch` is unavailable (e.g., when
/// running under Node.js without a fetch polyfill), rather than crashing with a force unwrap.
@MainActor
func fetch(_ url: String) -> JSPromise? {
  // `fetch` is a function on the global object in all modern browsers.
  // Guard against environments where it may be absent (Node without polyfill, old JSDOM).
  guard let fetchFunction = JSObject.global.fetch.function else {
    JSObject.global.console.error("fetch is not available in this environment")
    return nil
  }
  // `fetch(url)` returns a JS Promise object; wrap it in a typed `JSPromise`.
  guard let promiseObject = fetchFunction(url).object else {
    JSObject.global.console.error("fetch(\(url)) did not return an object")
    return nil
  }
  return JSPromise(promiseObject)
}

// MARK: - DOM setup

/// Obtain a reference to `document` from the JS global scope.
let document = JSObject.global.document

/// Create a <p> element that will display the latest UUID or error message.
var p = document.createElement("p")
_ = document.body.appendChild(p)

// MARK: - Subscription storage

/// Holds the active subscription so it is not deallocated between timer ticks.
/// Reassigned on every tick, which cancels the previous subscription automatically.
var subscription: AnyCancellable?

// MARK: - Periodic UUID fetch

/// `JSTimer` schedules a repeating callback on the JS event loop using `setInterval`.
/// The callback fires every 1 000 ms and starts a new Combine pipeline to fetch a UUID.
let timer = JSTimer(millisecondsDelay: 1000, isRepeating: true) {
  // Resolve `fetch` and construct the first promise; bail out gracefully if unavailable.
  guard let fetchPromise = fetch("https://httpbin.org/uuid") else {
    p.innerText = .string("fetch unavailable — cannot reach httpbin.org/uuid")
    return
  }

  subscription = fetchPromise
    .publisher
    // The response is a Response object; call .json() to get a second Promise with the
    // parsed body. Guard against unexpected values to avoid silent data loss.
    .flatMap { responseValue -> JSPromise.PromisePublisher in
      guard
        let responseObject = responseValue.object,
        let jsonFn = responseObject.json.function,
        let jsonPromiseObject = jsonFn().object,
        let jsonPromise = JSPromise(jsonPromiseObject)
      else {
        // Return a publisher that immediately fails if the response is malformed.
        // JSPromise's resolver receives a Result<JSValue, JSValue>; the rejection value
        // is a raw JSValue (wrapped into PromiseError by the publisher layer).
        let dummy = JSPromise(resolver: { resolve in
          resolve(.failure(.string("Unexpected response shape")))
        })
        return dummy.publisher
      }
      return jsonPromise.publisher
    }
    // Surface JS rejection reasons as Swift `Error` values for uniform error handling.
    .mapError { $0 as Error }
    // Extract the UUID string, packaging both success and failure in a `Result` so the
    // `.catch` operator can forward error descriptions to the same `.sink` handler.
    .map { jsonValue -> Result<String, Error> in
      if let uuid = jsonValue.uuid.string {
        return .success(uuid)
      } else {
        return .failure(DecodingError.valueNotFound(
          String.self,
          .init(codingPath: [], debugDescription: "uuid field missing or not a string")
        ))
      }
    }
    .catch { Just(.failure($0)) }
    .sink { result in
      // All DOM updates happen here, on the JS event loop, so no synchronization is needed.
      let time = JSDate().toLocaleTimeString()
      switch result {
      case let .success(uuid):
        p.innerText = .string("At \(time) received uuid \(uuid)")
      case let .failure(error):
        // Show a short, user-facing message in the DOM; keep the full error
        // (which may include raw JS rejection values) in the developer console.
        JSObject.global.console.error("fetch pipeline failed: \(error)")
        p.innerText = .string("At \(time) the request failed — see console for details")
      }
    }
}

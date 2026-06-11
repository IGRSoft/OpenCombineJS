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

import JavaScriptKit

// Dual Combine backend (issue #11): on Apple platforms the library is built against the
// native Combine framework, so consumers receive native `Future`, `AnyCancellable`,
// `Scheduler`, and `TopLevelDecoder` types; on WASI (and any platform without Combine)
// it is built against OpenCombine. All consumed symbols are mirrored 1:1 between the two
// modules — only the module identity differs. The host (macOS) test lane exercises the
// Combine backend; the wasm test lane exercises the OpenCombine backend.
#if canImport(Combine)
import Combine
#else
import OpenCombine
#endif

/// Extensions that expose a Combine `Publisher` interface on `JSPromise`.
///
/// Import `OpenCombineJS` to access the `.publisher` property and associated types.
/// All API in this extension is safe to call only from the JavaScript event loop thread;
/// do not dispatch across concurrency domains.
public extension JSPromise {
  /// A typed error wrapping a JavaScript rejection value.
  ///
  /// When a `JSPromise` is rejected, the rejection reason arrives as an untyped `JSValue`.
  /// `PromiseError` boxes that value so it can be forwarded as a typed Swift `Error` through
  /// Combine pipelines without losing the original JS context.
  ///
  /// ## Sendable rationale
  ///
  /// The type is marked `@unchecked Sendable` because `JSValue` itself is not `Sendable` in
  /// JavaScriptKit; however, the WASM runtime is single-threaded and all JavaScript execution
  /// occurs on one event-loop thread, so the wrapped value never crosses isolation domains in
  /// practice. The annotation is required because Swift 6's `Error` protocol refines `Sendable`.
  struct PromiseError: Error, Equatable, @unchecked Sendable {
    /// The raw JavaScript value that caused the promise rejection.
    public let value: JSValue

    /// Creates a `PromiseError` wrapping the given JavaScript rejection value.
    ///
    /// - Parameter value: The `JSValue` passed to the promise's rejection handler.
    public init(_ value: JSValue) {
      self.value = value
    }
  }

  /// A `Publisher` that emits the resolved value of a `JSPromise` exactly once, then
  /// completes; or forwards the rejection reason as a `PromiseError` failure.
  ///
  /// `PromisePublisher` is backed by a `Future<JSValue, PromiseError>` so that the resolved
  /// or rejected value is cached and replayed to late subscribers — consistent with the
  /// settled semantics of a JavaScript `Promise`.
  ///
  /// ## Output and Failure types
  ///
  /// | Associated type | Concrete type |
  /// |---|---|
  /// | `Output` | `JSValue` |
  /// | `Failure` | `PromiseError` |
  final class PromisePublisher: Publisher {
    /// The resolved JavaScript value emitted by this publisher.
    public typealias Output = JSValue

    /// The error type emitted when the underlying promise is rejected.
    public typealias Failure = PromiseError

    /// `Future` instance that handles subscriptions to this publisher.
    private var future: Future<JSValue, PromiseError>

    fileprivate init(promise: JSPromise) {
      future = .init { resolver in
        promise.then(success: {
          resolver(.success($0))
          return JSValue.undefined
        }, failure: {
          resolver(.failure(PromiseError($0)))
          return JSValue.undefined
        })
      }
    }

    /// Attaches a subscriber to this publisher.
    ///
    /// Delegates to the underlying `Future`, which replays the settled value to each
    /// subscriber independently.
    ///
    /// - Parameter subscriber: The subscriber to attach. Must accept `JSValue` input and
    ///   `PromiseError` failures.
    public func receive<Downstream: Subscriber>(subscriber: Downstream)
      where Downstream.Input == JSValue, Downstream.Failure == PromiseError
    {
      future.receive(subscriber: WrappingSubscriber(inner: subscriber))
    }
  }

  /// A Combine publisher that resolves or rejects in lock-step with this `JSPromise`.
  ///
  /// Use this property to integrate JavaScript promises into Combine pipelines:
  ///
  /// ```swift
  /// fetch("https://httpbin.org/uuid")
  ///     .publisher
  ///     .flatMap { $0.json().publisher }   // chain further JS promises
  ///     .sink { ... }
  /// ```
  ///
  /// ## Async/await counterpart
  ///
  /// JavaScriptKit's `JavaScriptEventLoop` module ships `JSPromise.value`
  /// (`get async throws(JSException)`), the async counterpart of this publisher:
  ///
  /// ```swift
  /// import JavaScriptEventLoop
  ///
  /// let value = try await promise.value
  /// ```
  ///
  /// Both paths observe the same settlement: the resolved `JSValue`, or — on rejection —
  /// the same raw JS reason (`PromiseError.value` here, `JSException.thrownValue` there).
  /// `.publisher` is not deprecated and remains fully supported alongside the async path;
  /// any soft-deprecation decision is deferred to 1.0 (issue #13).
  var publisher: PromisePublisher {
    .init(promise: self)
  }

  /** Helper type that wraps a given `inner` subscriber and holds references to both stored promises
   of `PromisePublisher`, as `PromisePublisher` itself can be deallocated earlier than its
   subscribers.
   */
  private struct WrappingSubscriber<Inner: Subscriber>: Subscriber {
    typealias Input = Inner.Input
    typealias Failure = Inner.Failure

    let inner: Inner

    var combineIdentifier: CombineIdentifier {
      inner.combineIdentifier
    }

    func receive(subscription: Subscription) {
      inner.receive(subscription: subscription)
    }

    func receive(_ input: Input) -> Subscribers.Demand {
      inner.receive(input)
    }

    func receive(completion: Subscribers.Completion<Failure>) {
      inner.receive(completion: completion)
    }
  }
}

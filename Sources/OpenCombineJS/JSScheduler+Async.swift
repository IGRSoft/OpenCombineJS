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

// Async/await bridge over JSScheduler's JS timer semantics (issue #13).
// Strictly additive: the Combine `Scheduler` surface is unchanged and not deprecated.

// Dual Combine backend — see JSPromise.swift for the canonical rationale (issue #11).
#if canImport(Combine)
import Combine
#else
import OpenCombine
#endif

public extension JSScheduler {
  /// Suspends the current task for the given interval, driven by a JavaScript timer.
  ///
  /// This is the async/await counterpart of ``JSScheduler/schedule(after:tolerance:options:_:)``.
  /// The delay is implemented with `setTimeout` — **not** `Task.sleep` — so it follows exactly
  /// the same JS macrotask semantics as the Combine scheduling APIs and shares the scheduler's
  /// internal timer bookkeeping (the timer entry is removed when it fires; nothing leaks).
  /// Like every scheduling path, the delay is driven by the scheduler's ``JSClockSource``, so
  /// an injected deterministic clock controls this suspension too.
  ///
  /// The method never resumes early: the continuation is resumed by the JS timer callback, which
  /// the JS runtime fires no earlier than the requested delay. Zero or negative intervals resume
  /// on the next event-loop turn (JS timers clamp negative delays to `0`).
  ///
  /// ## Executor requirement (WASI)
  ///
  /// On WASI, `await`-ing requires the `JavaScriptEventLoop` global executor so suspended tasks
  /// are resumed by JS timers/promises. Call `JavaScriptEventLoop.installGlobalExecutor()` once
  /// at startup (the `JavaScriptEventLoopTestSupport` target installs it automatically in tests).
  ///
  /// - Parameter interval: How long to suspend, e.g. `.milliseconds(300)`.
  func sleep(for interval: SchedulerTimeType.Stride) async {
    await withCheckedContinuation { (continuation: CheckedContinuation<(), Never>) in
      schedule(
        after: now.advanced(by: interval),
        tolerance: minimumTolerance,
        options: nil
      ) {
        continuation.resume()
      }
    }
  }

  /// Returns an `AsyncStream` that yields once per `interval`, backed by the same repeating
  /// JS timer (`setInterval`) semantics as
  /// ``JSScheduler/schedule(after:interval:tolerance:options:_:)`` — and, like that path,
  /// driven by the scheduler's ``JSClockSource``.
  ///
  /// The first tick arrives one full `interval` after the call — the same first-fire semantics
  /// as the Combine repeating schedule. The stream never finishes on its own; iteration ends
  /// when the consumer breaks out of the loop or the consuming task is cancelled. Stream
  /// termination cancels the underlying timer through the scheduler's token bookkeeping
  /// (both the pending timeout and the interval timer are released; nothing leaks):
  ///
  /// ```swift
  /// for await _ in scheduler.timer(interval: .milliseconds(500)) {
  ///   refresh()
  ///   if done { break }  // cancels the underlying JS timer
  /// }
  /// ```
  ///
  /// If the consumer is slower than the tick cadence, pending ticks are coalesced: the stream
  /// buffers at most one tick (`bufferingNewest(1)`), mirroring how a UI-driven `setInterval`
  /// callback would observe time, instead of queueing stale ticks unboundedly.
  ///
  /// ## Executor requirement (WASI)
  ///
  /// On WASI, iterating the stream requires the `JavaScriptEventLoop` global executor — see
  /// ``JSScheduler/sleep(for:)``.
  ///
  /// - Parameter interval: The period between successive ticks.
  /// - Returns: An infinite `AsyncStream` of `Void` ticks.
  func timer(interval: SchedulerTimeType.Stride) -> AsyncStream<()> {
    AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
      let cancellable = SendableCancellableBox(
        schedule(
          after: now,
          interval: interval,
          tolerance: minimumTolerance,
          options: nil
        ) {
          continuation.yield(())
        }
      )
      // `onTermination` must be `@Sendable`; the boxed `Cancellable` is not. This is safe on
      // the single-threaded JS event loop (the same invariant documented on `JSScheduler`):
      // termination handlers run on the only thread there is.
      continuation.onTermination = { _ in
        cancellable.cancellable.cancel()
      }
    }
  }
}

/// Wrapper that carries a non-`Sendable` `Cancellable` into the `@Sendable` stream-termination
/// handler. Safe because `JSScheduler` (and everything it schedules) lives on the
/// single-threaded JS event loop; see the `JSScheduler` class documentation.
private final class SendableCancellableBox: @unchecked Sendable {
  let cancellable: any Cancellable

  init(_ cancellable: any Cancellable) {
    self.cancellable = cancellable
  }
}

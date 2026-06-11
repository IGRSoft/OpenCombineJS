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

// Virtual-clock seam for JSScheduler (issue #14). Strictly additive: the default
// implementation reproduces the historical JSDate.now()/JSTimer behavior exactly.

import JavaScriptKit

/// A cancellation token for a timer created by a ``JSClockSource``.
///
/// ``JSScheduler`` keeps the token alive while the timer is pending and calls ``cancel()``
/// exactly when the timer must stop firing (on explicit cancellation, or as harmless cleanup
/// after a one-shot timer has already fired — implementations must treat cancelling a fired
/// or already-cancelled timer as a no-op, mirroring JavaScript's `clearTimeout`).
///
/// Conforming types should also stop the timer when the token is deinitialized, mirroring
/// `JSTimer`'s reference semantics. `JSScheduler` always cancels explicitly before releasing
/// a token, so deinit-cancellation is only a defensive backstop.
public protocol JSClockCancellable: AnyObject {
  /// Stops the timer. Calling this on a fired or already-cancelled timer is a no-op.
  func cancel()
}

/// The time-and-timer seam used by ``JSScheduler``.
///
/// `JSScheduler` performs **all** of its time observation and timer creation through this
/// protocol — the immediate, one-shot, and repeating Combine scheduling paths as well as the
/// async ``JSScheduler/sleep(for:)`` and ``JSScheduler/timer(interval:)`` bridges. Injecting
/// a deterministic implementation via ``JSScheduler/init(clock:)`` therefore makes every
/// scheduler behavior reproducible without real timers — including on platforms without a
/// JavaScript runtime (see the "Deterministic testing" section in the module overview).
///
/// The default implementation, ``DefaultJSClockSource``, is backed by `JSDate.now()` and
/// `JSTimer` (`setTimeout`/`setInterval`) and is what ``JSScheduler/init()`` uses.
///
/// Implementations inherit the scheduler's single-threaded contract: all calls are made from
/// the thread that owns the scheduler, and conforming types are not required to be `Sendable`.
public protocol JSClockSource {
  /// The current time in milliseconds since the Unix epoch (the `Date.now()` convention).
  var now: Double { get }

  /// Creates and starts a timer, mirroring `JSTimer.init(millisecondsDelay:isRepeating:callback:)`.
  ///
  /// - Parameters:
  ///   - millisecondsDelay: Delay before the first (or only) firing, in milliseconds.
  ///     Negative values must clamp to `0`, matching JavaScript timer semantics.
  ///   - isRepeating: When `true`, `callback` fires repeatedly every `millisecondsDelay`
  ///     milliseconds until the returned token is cancelled; when `false`, it fires once.
  ///   - callback: The closure to invoke when the timer fires.
  /// - Returns: A token that keeps the timer alive and stops it when cancelled.
  func makeTimer(
    millisecondsDelay: Double,
    isRepeating: Bool,
    callback: @escaping () -> ()
  ) -> any JSClockCancellable
}

/// The production ``JSClockSource``: real JavaScript time and timers.
///
/// `now` reads `JSDate.now()`; ``makeTimer(millisecondsDelay:isRepeating:callback:)`` creates
/// a `JSTimer` (`setTimeout`/`setInterval`) — exactly the behavior `JSScheduler` had before
/// the seam existed. Requires a live JavaScript runtime (WebAssembly/browser/Node.js);
/// constructing the value itself is side-effect free.
public struct DefaultJSClockSource: JSClockSource {
  /// Creates the default JavaScript-backed clock source.
  public init() {}

  /// The current time as reported by `Date.now()`, in milliseconds since the Unix epoch.
  public var now: Double {
    JSDate.now()
  }

  /// Starts a `JSTimer` and returns a token whose cancellation releases the timer
  /// (dropping the last `JSTimer` reference calls `clearTimeout`/`clearInterval`).
  public func makeTimer(
    millisecondsDelay: Double,
    isRepeating: Bool,
    callback: @escaping () -> ()
  ) -> any JSClockCancellable {
    JSTimerCancellable(
      JSTimer(millisecondsDelay: millisecondsDelay, isRepeating: isRepeating, callback: callback)
    )
  }
}

/// Token wrapping a `JSTimer`. `JSTimer` has no explicit `invalidate()` — releasing the last
/// strong reference clears the underlying JS timer in `deinit` — so cancellation simply drops
/// the reference. Repeated cancellation is a natural no-op.
private final class JSTimerCancellable: JSClockCancellable {
  private var timer: JSTimer?

  init(_ timer: JSTimer) {
    self.timer = timer
  }

  func cancel() {
    timer = nil
  }
}

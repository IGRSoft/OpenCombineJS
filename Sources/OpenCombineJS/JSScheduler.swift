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

// Dual Combine backend — see JSPromise.swift for the canonical rationale (issue #11).
#if canImport(Combine)
import Combine
#else
import OpenCombine
#endif

/// A Combine `Scheduler` backed by JavaScript timers (`setTimeout`/`setInterval`).
///
/// Use `JSScheduler` with any time-dependent Combine operator — `debounce`, `throttle`,
/// `delay`, `measureInterval`, `timeout` — when targeting a WebAssembly/browser environment:
///
/// ```swift
/// publisher
///     .debounce(for: .milliseconds(300), scheduler: JSScheduler())
///     .sink { ... }
/// ```
///
/// ## Concurrency model
///
/// `JSScheduler` is intentionally **not** `Sendable` — that is the documented contract, not
/// an omission. Its mutable state (the pending-timer token table) is unsynchronized and is
/// safe only because, in its intended WebAssembly deployment, every scheduling call and every
/// timer callback runs on the single-threaded JavaScript event loop. The type also compiles
/// on Apple platforms (against native Combine), where Combine operators may legally invoke a
/// `Sendable` scheduler from arbitrary threads — which is exactly why this class must not be
/// marked `@unchecked Sendable`: the single-thread invariant cannot be guaranteed there.
///
/// All time observation and timer creation flow through a single injectable seam
/// (``JSClockSource``), so the class body holds no other environment-dependent state and the
/// single-thread invariant is straightforward to audit.
///
/// - Important: Instances must not be shared across concurrency domains or moved off the
///   thread that created them (on WebAssembly: the JS event-loop thread).
///
/// ## Deterministic testing
///
/// Inject a manually advanced ``JSClockSource`` via ``init(clock:)`` to drive every scheduling
/// path — including ``sleep(for:)`` and ``timer(interval:)`` — without real timers or a
/// JavaScript runtime. See the "Deterministic testing" section in the module overview.
public final class JSScheduler: Scheduler {
  /// The time-and-timer seam. All scheduling paths read time and create timers exclusively
  /// through this value; `JSDate`/`JSTimer` are never touched directly.
  private let clock: any JSClockSource

  /// Creates a new `JSScheduler` backed by the current JavaScript runtime
  /// (equivalent to `JSScheduler(clock: DefaultJSClockSource())`).
  public init() {
    clock = DefaultJSClockSource()
  }

  /// Creates a `JSScheduler` driven by the given clock source.
  ///
  /// Use this initializer to inject a deterministic clock in tests; production code can keep
  /// using ``init()``, which is backed by `JSDate.now()` and `JSTimer`.
  ///
  /// - Parameter clock: The source of current time and timers for all scheduling paths.
  public init(clock: any JSClockSource) {
    self.clock = clock
  }

  private final class CancellableTimer: Cancellable {
    let cancellation: () -> ()

    init(_ cancellation: @escaping () -> ()) {
      self.cancellation = cancellation
    }

    func cancel() {
      cancellation()
    }
  }

  /// A point in time measured in milliseconds since the Unix epoch, as reported by `Date.now()`.
  ///
  /// Conforms to `Strideable` so Combine operators can compute time differences and advances.
  public struct SchedulerTimeType: Strideable {
    let millisecondsValue: Double

    /// Returns a time advanced by the given stride.
    ///
    /// - Parameter n: The stride (in milliseconds) to add to this time.
    /// - Returns: A new `SchedulerTimeType` offset by `n`.
    public func advanced(by n: Stride) -> Self {
      .init(millisecondsValue: millisecondsValue + n.magnitude)
    }

    /// Returns the stride from this time to `other`.
    ///
    /// - Parameter other: The target time.
    /// - Returns: A `Stride` representing `other − self` in milliseconds.
    public func distance(to other: Self) -> Stride {
      .init(millisecondsValue: other.millisecondsValue - millisecondsValue)
    }

    /// A time interval expressed in milliseconds.
    ///
    /// Conforms to `SchedulerTimeIntervalConvertible` so Combine operators can accept
    /// standard time-literal arguments (`.seconds(1)`, `.milliseconds(500)`, etc.).
    public struct Stride: SchedulerTimeIntervalConvertible, Comparable, SignedNumeric {
      /// Time interval magnitude in milliseconds.
      public var magnitude: Double

      /// Creates a `Stride` from an exact integer source, or returns `nil` if the value
      /// cannot be represented losslessly as a `Double`.
      ///
      /// - Parameter source: The integer value to convert.
      public init?<T>(exactly source: T) where T: BinaryInteger {
        guard let magnitude = Double(exactly: source) else { return nil }
        self.magnitude = magnitude
      }

      /// Creates a `Stride` with the given millisecond value.
      ///
      /// - Parameter millisecondsValue: Duration in milliseconds.
      public init(millisecondsValue: Double) {
        magnitude = millisecondsValue
      }

      /// Creates a `Stride` from a floating-point literal, interpreted as seconds.
      ///
      /// - Parameter value: Duration in seconds (e.g. `1.5` → 1 500 ms).
      public init(floatLiteral value: Double) {
        self = .seconds(value)
      }

      /// Creates a `Stride` from an integer literal, interpreted as seconds.
      ///
      /// - Parameter value: Duration in seconds.
      public init(integerLiteral value: Int) {
        self = .seconds(value)
      }

      /// Returns a stride representing the given number of microseconds.
      ///
      /// - Parameter us: Duration in microseconds.
      public static func microseconds(_ us: Int) -> Self {
        .init(millisecondsValue: Double(us) / 1000)
      }

      /// Returns a stride representing the given number of milliseconds.
      ///
      /// - Parameter ms: Duration in milliseconds.
      public static func milliseconds(_ ms: Int) -> Self {
        .init(millisecondsValue: Double(ms))
      }

      /// Returns a stride representing the given number of nanoseconds.
      ///
      /// - Parameter ns: Duration in nanoseconds.
      public static func nanoseconds(_ ns: Int) -> Self {
        .init(millisecondsValue: Double(ns) / 1_000_000)
      }

      /// Returns a stride representing the given number of seconds (floating-point).
      ///
      /// - Parameter s: Duration in seconds.
      public static func seconds(_ s: Double) -> Self {
        .init(millisecondsValue: s * 1000)
      }

      /// Returns a stride representing the given number of seconds (integer).
      ///
      /// - Parameter s: Duration in seconds.
      public static func seconds(_ s: Int) -> Self {
        .init(millisecondsValue: Double(s) * 1000)
      }

      public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.magnitude < rhs.magnitude
      }

      public static func * (lhs: Self, rhs: Self) -> Self {
        .init(millisecondsValue: lhs.magnitude * rhs.magnitude)
      }

      public static func + (lhs: Self, rhs: Self) -> Self {
        .init(millisecondsValue: lhs.magnitude + rhs.magnitude)
      }

      public static func - (lhs: Self, rhs: Self) -> Self {
        .init(millisecondsValue: lhs.magnitude - rhs.magnitude)
      }

      public static func -= (lhs: inout Self, rhs: Self) {
        lhs.magnitude -= rhs.magnitude
      }

      public static func *= (lhs: inout Self, rhs: Self) {
        lhs.magnitude *= rhs.magnitude
      }

      public static func += (lhs: inout Self, rhs: Self) {
        lhs.magnitude += rhs.magnitude
      }
    }
  }

  /// Opaque options type; `JSScheduler` has no configurable scheduling options.
  public struct SchedulerOptions {}

  /// The current time as reported by the scheduler's clock source, expressed in milliseconds.
  /// For the default clock this is `Date.now()`.
  public var now: SchedulerTimeType {
    .init(millisecondsValue: clock.now)
  }

  /// The minimum tolerance accepted by the scheduler.
  ///
  /// Returns the smallest representable positive `Double` because JavaScript timers do not
  /// provide sub-millisecond precision guarantees; callers should not rely on tolerances
  /// smaller than one millisecond.
  public var minimumTolerance: SchedulerTimeType.Stride {
    .init(millisecondsValue: .leastNonzeroMagnitude)
  }

  /// Monotonically increasing token identifying entries in `scheduledTimers`. Tokens are
  /// generated *before* the corresponding `JSTimer` is created so that cleanup closures capture
  /// a plain value instead of the timer itself (capturing the implicitly-unwrapped timer variable
  /// in a `[weak …]` list evaluated while it was still `nil` made cleanup unreachable and leaked
  /// every timer, see issue #4).
  private var nextTimerToken: UInt64 = 0

  /// Storage keeping scheduled timers alive. Entries are removed when a one-shot timer fires or
  /// when a repeating schedule is cancelled; removal cancels the clock-source token, which (for
  /// the default clock) drops the last strong reference to the `JSTimer`, whose `deinit` clears
  /// the underlying JS timer. Internal (not `private`) so the test suite can verify cleanup via
  /// `@testable import`.
  var scheduledTimers = [UInt64: any JSClockCancellable]()

  private func nextToken() -> UInt64 {
    defer { nextTimerToken += 1 }
    return nextTimerToken
  }

  /// Removes the timer registered under `token` (if any) and cancels it. Cancelling a fired
  /// one-shot timer is a documented no-op on `JSClockCancellable`, so this is also used as
  /// the post-fire cleanup path.
  private func removeTimer(_ token: UInt64) {
    scheduledTimers.removeValue(forKey: token)?.cancel()
  }

  /// Schedules `action` for immediate execution on the next event-loop turn.
  ///
  /// Wraps `setTimeout(action, 0)`. The action executes asynchronously — after the current
  /// call stack unwinds — rather than synchronously inline.
  ///
  /// - Parameters:
  ///   - options: Ignored; `JSScheduler` has no scheduling options.
  ///   - action: The closure to execute.
  public func schedule(options: SchedulerOptions?, _ action: @escaping () -> ()) {
    let token = nextToken()
    scheduledTimers[token] = clock.makeTimer(millisecondsDelay: 0, isRepeating: false) {
      [weak self] in
      action()
      self?.removeTimer(token)
    }
  }

  /// Schedules `action` for execution after the specified date.
  ///
  /// The delay is computed as `date.millisecondsValue − now` (against the scheduler's clock
  /// source) and passed to `setTimeout`. If the date is in the past the action fires on the
  /// next event-loop turn.
  ///
  /// - Parameters:
  ///   - date: The earliest time at which `action` should execute.
  ///   - tolerance: Ignored; JavaScript timers do not support tolerance hints.
  ///   - options: Ignored; `JSScheduler` has no scheduling options.
  ///   - action: The closure to execute.
  public func schedule(
    after date: SchedulerTimeType,
    tolerance: SchedulerTimeType.Stride,
    options: SchedulerOptions?,
    _ action: @escaping () -> ()
  ) {
    let token = nextToken()
    scheduledTimers[token] = clock.makeTimer(
      millisecondsDelay: date.millisecondsValue - clock.now,
      isRepeating: false
    ) { [weak self] in
      action()
      self?.removeTimer(token)
    }
  }

  /// Schedules `action` to execute repeatedly at the given interval, starting after `date`.
  ///
  /// The first invocation fires `interval` milliseconds after `date`; subsequent invocations
  /// fire every `interval` milliseconds thereafter. Returns a `Cancellable` that stops both
  /// the pending delay timer and the repeating interval timer — safe to call before the first
  /// fire, between fires, or multiple times (repeated cancellation is a no-op).
  ///
  /// - Parameters:
  ///   - date: The time after which the repeating schedule begins.
  ///   - interval: The period between successive firings.
  ///   - tolerance: Ignored; JavaScript timers do not support tolerance hints.
  ///   - options: Ignored; `JSScheduler` has no scheduling options.
  ///   - action: The closure to execute on each interval tick.
  /// - Returns: A `Cancellable` that stops the repeating schedule when cancelled.
  public func schedule(
    after date: SchedulerTimeType,
    interval: SchedulerTimeType.Stride,
    tolerance: SchedulerTimeType.Stride,
    options: SchedulerOptions?,
    _ action: @escaping () -> ()
  ) -> Cancellable {
    let timeoutToken = nextToken()
    let intervalToken = nextToken()
    // Shared between the timeout callback and the cancellation closure; safe without
    // synchronization because both always run on the single-threaded JS event loop.
    var isCancelled = false

    scheduledTimers[timeoutToken] = clock.makeTimer(
      millisecondsDelay: date.millisecondsValue - clock.now,
      isRepeating: false
    ) { [weak self] in
      guard let self = self else { return }
      self.removeTimer(timeoutToken)
      // Guards against a cancellation processed after this callback was already queued
      // (issue #3): the interval must never start once cancel() has run.
      guard !isCancelled else { return }
      self.scheduledTimers[intervalToken] = self.clock.makeTimer(
        millisecondsDelay: interval.magnitude,
        isRepeating: true
      ) { action() }
    }

    // Cancellation is safe at any point in the schedule's lifecycle (issue #3): before the first
    // fire it clears the pending timeout, afterwards it clears the repeating interval, and
    // repeated cancellation is a no-op (removing absent keys has no effect).
    return CancellableTimer {
      isCancelled = true
      self.removeTimer(timeoutToken)
      self.removeTimer(intervalToken)
    }
  }
}

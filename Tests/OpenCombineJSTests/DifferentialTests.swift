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

// DIFFERENTIAL TESTS (06-test-data-strategy.md §4, issue #13): drive the same input through
// the legacy Combine path and the new async/await path; observable outcomes must match
// (value, error mapping, tick cadence). WASI-only: live JS promises/timers and the
// JavaScriptEventLoop global executor (installed by JavaScriptEventLoopTestSupport) are
// required. `@testable import` is used so the suite can also verify that the async APIs
// reuse the scheduler's timer bookkeeping and leak nothing (issue #4 invariant).

#if os(WASI)
import JavaScriptEventLoop
import JavaScriptKit
@testable import OpenCombineJS
import Testing

// Dual Combine backend — see Sources/OpenCombineJS/JSPromise.swift (issue #11).
#if canImport(Combine)
import Combine
#else
import OpenCombine
#endif

// MARK: - Differential 1: JSPromise — .publisher (legacy) vs try await .value (new)

struct DifferentialPromiseTests {
  /// DT-JP-01 — a resolved promise yields the identical value on both paths.
  @Test("DIFFERENTIAL: resolved JSPromise yields identical value via .publisher and .value")
  func resolvedValueIdentical() async throws {
    let expected = JSValue.string("differential-test-value")
    let promise = JSPromise.resolve(expected)

    // Legacy path: Combine publisher.
    var publisherValue: JSValue?
    var publisherError: JSPromise.PromiseError?
    var sink: AnyCancellable?
    await confirmation("publisher path completes") { completed in
      await withCheckedContinuation { (continuation: CheckedContinuation<(), Never>) in
        sink = promise.publisher.sink(
          receiveCompletion: { completion in
            if case let .failure(error) = completion { publisherError = error }
            completed()
            continuation.resume()
          },
          receiveValue: { publisherValue = $0 }
        )
      }
    }
    withExtendedLifetime(sink) {}

    // New path: async/await (JavaScriptKit's JSPromise.value).
    let asyncValue = try await promise.value

    #expect(publisherError == nil, "publisher path must not fail for a resolved promise")
    #expect(publisherValue == expected)
    #expect(asyncValue == expected)
    #expect(publisherValue == asyncValue, "DIFFERENTIAL FAILURE: paths diverged")
  }

  /// DT-JP-02 — a rejected promise surfaces the identical raw JS rejection reason on both
  /// paths: `PromiseError.value` (publisher) and `JSException.thrownValue` (async).
  @Test("DIFFERENTIAL: rejected JSPromise maps to the identical error value on both paths")
  func rejectedErrorIdentical() async {
    let reason = JSValue.string("differential-rejection")
    let promise = JSPromise.reject(reason)

    // Legacy path.
    var publisherError: JSPromise.PromiseError?
    var sink: AnyCancellable?
    await confirmation("publisher failure received") { completed in
      await withCheckedContinuation { (continuation: CheckedContinuation<(), Never>) in
        sink = promise.publisher.sink(
          receiveCompletion: { completion in
            if case let .failure(error) = completion { publisherError = error }
            completed()
            continuation.resume()
          },
          receiveValue: { _ in }
        )
      }
    }
    withExtendedLifetime(sink) {}

    // New path. `JSPromise.value` throws typed `JSException`.
    var asyncThrownValue: JSValue?
    do {
      _ = try await promise.value
      Issue.record("async path must throw for a rejected promise")
    } catch {
      asyncThrownValue = error.thrownValue
    }

    #expect(publisherError?.value == reason)
    #expect(asyncThrownValue == reason)
    #expect(
      publisherError?.value == asyncThrownValue,
      "DIFFERENTIAL FAILURE: rejection reason diverged between paths"
    )
  }

  /// DT-JP-03 — a promise that settles *after* both paths subscribed delivers the same value.
  @Test("DIFFERENTIAL: pending-then-resolved JSPromise delivers the same value on both paths")
  func pendingThenResolvedIdentical() async throws {
    var resolveHandler: ((JSPromise.Result) -> ())?
    let promise = JSPromise { resolveHandler = $0 }
    let expected = JSValue.number(42)

    // Attach the publisher subscriber while the promise is still pending.
    var publisherValue: JSValue?
    let sink = promise.publisher.sink(
      receiveCompletion: { _ in },
      receiveValue: { publisherValue = $0 }
    )

    // Resolve on a later event-loop turn, then await the async path; the await suspends
    // until the timer fires and the promise settles, exercising the pending case.
    var timer: JSTimer?
    timer = JSTimer(millisecondsDelay: 10) {
      resolveHandler?(.success(expected))
    }
    let asyncValue = try await promise.value
    withExtendedLifetime(timer) {}
    withExtendedLifetime(sink) {}

    // Drain the microtask queue so the publisher delivery (registered first) is settled too.
    await eventLoopSleep(milliseconds: 10)

    #expect(asyncValue == expected)
    #expect(publisherValue == expected)
    #expect(publisherValue == asyncValue, "DIFFERENTIAL FAILURE: paths diverged")
  }
}

// MARK: - Differential 2: JSScheduler — Combine repeating schedule vs timer(interval:)

struct DifferentialSchedulerTests {
  /// DT-SC-01 — both paths tick at a comparable cadence for the same interval.
  /// Tolerance bands follow 06-test-data-strategy.md §4.2: per-tick band
  /// [interval − 20 ms, interval + 200 ms] (generous upper bound for wasm event-loop
  /// jitter), and ≤ 25 ms divergence between the two paths' mean cadences.
  @Test("DIFFERENTIAL: Combine schedule and timer(interval:) tick at comparable cadence")
  func tickCadenceComparable() async throws {
    let scheduler = JSScheduler()
    let intervalMs = 40.0
    let requiredTicks = 4 // 3 gaps ≥ the "≥3 ticks" requirement

    // Legacy path: Combine repeating schedule.
    var combineTimes = [Double]()
    var cancellable: (any Cancellable)?
    await withCheckedContinuation { (continuation: CheckedContinuation<(), Never>) in
      var resumed = false
      cancellable = scheduler.schedule(
        after: scheduler.now,
        interval: .milliseconds(Int(intervalMs)),
        tolerance: .milliseconds(10),
        options: nil
      ) {
        combineTimes.append(JSDate.now())
        if combineTimes.count == requiredTicks, !resumed {
          resumed = true
          continuation.resume()
        }
      }
    }
    cancellable?.cancel()

    // New path: AsyncStream ticks.
    var asyncTimes = [Double]()
    for await _ in scheduler.timer(interval: .milliseconds(Int(intervalMs))) {
      asyncTimes.append(JSDate.now())
      if asyncTimes.count >= requiredTicks { break }
    }

    #expect(combineTimes.count >= requiredTicks)
    #expect(asyncTimes.count >= requiredTicks)

    // Per-tick band on the async path (the Combine path is pinned by SC-08).
    for index in 1..<asyncTimes.count {
      let gap = asyncTimes[index] - asyncTimes[index - 1]
      #expect(gap > 0, "tick timestamps must be monotonically increasing")
      #expect(
        gap >= intervalMs - 20.0 && gap <= intervalMs + 200.0,
        "async tick cadence \(gap)ms outside tolerance band for \(intervalMs)ms interval"
      )
    }

    // Differential: mean cadences of the two paths must agree within the band.
    let combineFirst = try #require(combineTimes.first)
    let combineLast = try #require(combineTimes.last)
    let asyncFirst = try #require(asyncTimes.first)
    let asyncLast = try #require(asyncTimes.last)
    let combineMean = (combineLast - combineFirst) / Double(combineTimes.count - 1)
    let asyncMean = (asyncLast - asyncFirst) / Double(asyncTimes.count - 1)
    #expect(
      abs(combineMean - asyncMean) < 25.0,
      "DIFFERENTIAL FAILURE: Combine cadence \(combineMean)ms vs async cadence \(asyncMean)ms"
    )
  }

  /// DT-SC-02 — terminating the stream stops ticking and releases the underlying timers
  /// through the scheduler's token bookkeeping (issue #4 invariant), exactly like
  /// `Cancellable.cancel()` does on the Combine path.
  @Test("DIFFERENTIAL: breaking out of timer(interval:) cancels the underlying JS timer")
  func streamTerminationCancelsTimer() async {
    let scheduler = JSScheduler()
    var combineTicks = 0
    var asyncTicks = 0

    // Combine path: cancel after 2 ticks.
    var cancellable: (any Cancellable)?
    await withCheckedContinuation { (continuation: CheckedContinuation<(), Never>) in
      var resumed = false
      cancellable = scheduler.schedule(
        after: scheduler.now,
        interval: .milliseconds(20),
        tolerance: .milliseconds(5),
        options: nil
      ) {
        combineTicks += 1
        if combineTicks == 2, !resumed {
          resumed = true
          continuation.resume()
        }
      }
    }
    cancellable?.cancel()
    let combineTicksAtCancel = combineTicks

    // Async path: break after 2 ticks.
    for await _ in scheduler.timer(interval: .milliseconds(20)) {
      asyncTicks += 1
      if asyncTicks >= 2 { break }
    }
    let asyncTicksAtBreak = asyncTicks

    // Drain window: several would-be intervals; neither path may keep ticking, and the
    // scheduler's storage must be empty (stream termination released its timers).
    await eventLoopSleep(milliseconds: 120)

    #expect(combineTicks == combineTicksAtCancel, "Combine path kept firing after cancel()")
    #expect(asyncTicks == asyncTicksAtBreak, "async path kept firing after break")
    #expect(
      scheduler.scheduledTimers.isEmpty,
      "stream termination must release the underlying timers (issue #4 invariant)"
    )
  }

  /// DT-SC-03 — `sleep(for:)` must not return early, and must clean up its timer entry.
  @Test("DIFFERENTIAL: sleep(for:) does not return early")
  func sleepDoesNotReturnEarly() async {
    let scheduler = JSScheduler()
    let intervalMs = 60.0
    let start = JSDate.now()
    await scheduler.sleep(for: .milliseconds(Int(intervalMs)))
    let elapsed = JSDate.now() - start
    // JS timers fire no earlier than the requested delay; the JSDate.now() reference is
    // taken BEFORE sleep computes its target date, so strict >= must hold.
    #expect(elapsed >= intervalMs, "sleep returned after \(elapsed)ms — early for \(intervalMs)ms")
    #expect(scheduler.scheduledTimers.isEmpty, "sleep must not leak its one-shot timer entry")
  }
}
#endif

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

// Tests for JSScheduler runtime behavior. WASI-only: every test requires the JS event loop
// (JSTimer, JSDate) provided by a JavaScript host (Node.js via the PackageToJS test runner).
// `@testable import` is used deliberately so the suite can verify `scheduledTimers` cleanup
// (regression #4).

#if os(WASI)
import JavaScriptKit
@testable import OpenCombineJS
import Testing

// Dual Combine backend — see Sources/OpenCombineJS/JSPromise.swift (issue #11).
#if canImport(Combine)
import Combine
#else
import OpenCombine
#endif

// MARK: - now and minimumTolerance

struct JSSchedulerPropertiesTests {
  /// SC-01 — now reflects JS epoch milliseconds
  @Test("now returns a positive epoch-milliseconds value")
  func nowReturnsPositiveEpochMs() {
    #expect(JSScheduler().now.millisecondsValue > 0)
  }

  /// SC-01 / CT-SC-01 — monotonicity law
  @Test("now is non-decreasing across sequential reads")
  func nowIsNonDecreasing() {
    let scheduler = JSScheduler()
    var previous = scheduler.now
    for _ in 0..<100 {
      let current = scheduler.now
      #expect(current.millisecondsValue >= previous.millisecondsValue)
      previous = current
    }
  }

  /// SC-02 — minimumTolerance characterization
  @Test("minimumTolerance is Double.leastNonzeroMagnitude milliseconds")
  func minimumToleranceIsLeastNonzero() {
    #expect(JSScheduler().minimumTolerance.magnitude == Double.leastNonzeroMagnitude)
  }
}

// MARK: - schedule(options:_:) — immediate (macrotask) scheduling

struct JSSchedulerImmediateScheduleTests {
  /// SC-03 / CT-SC-02 — the action must not run synchronously, but must run soon after
  @Test("schedule(options:_:) defers the action to a later macrotask")
  func immediateScheduleIsAsynchronous() async {
    let scheduler = JSScheduler()
    var didRun = false
    await confirmation("action fires") { fired in
      await withCheckedContinuation { (continuation: CheckedContinuation<(), Never>) in
        scheduler.schedule(options: nil) {
          didRun = true
          fired()
          continuation.resume()
        }
        // Still on the original call stack: the action must not have executed yet.
        #expect(!didRun, "schedule(options:_:) must not execute the action synchronously")
      }
    }
    #expect(didRun)
  }

  /// SC-04 — regression #4: the fired one-shot timer must be removed from internal storage
  @Test("schedule(options:_:) removes the timer from scheduledTimers after firing")
  func immediateScheduleCleansUpTimer() async {
    let scheduler = JSScheduler()
    #expect(scheduler.scheduledTimers.isEmpty)
    await withCheckedContinuation { (continuation: CheckedContinuation<(), Never>) in
      scheduler.schedule(options: nil) {
        continuation.resume()
      }
      #expect(scheduler.scheduledTimers.count == 1)
    }
    // The cleanup statement runs right after the action inside the same callback.
    #expect(scheduler.scheduledTimers.isEmpty, "fired one-shot timers must not leak (issue #4)")
  }

  /// SC-13 — multiple concurrent schedules are independent
  @Test("multiple schedule(options:_:) calls all fire independently")
  func multipleConcurrentSchedules() async {
    let scheduler = JSScheduler()
    await confirmation("all three fire", expectedCount: 3) { fired in
      await withCheckedContinuation { (continuation: CheckedContinuation<(), Never>) in
        var remaining = 3
        for _ in 0..<3 {
          scheduler.schedule(options: nil) {
            fired()
            remaining -= 1
            if remaining == 0 { continuation.resume() }
          }
        }
      }
    }
    #expect(scheduler.scheduledTimers.isEmpty)
  }
}

// MARK: - schedule(after:tolerance:options:_:) — one-shot

struct JSSchedulerOneShotScheduleTests {
  /// SC-05 — fires once after the requested date, then cleans up (regression #4)
  @Test("schedule(after:) fires exactly once and cleans up its timer")
  func oneShotAfterDateFiresOnceAndCleansUp() async {
    let scheduler = JSScheduler()
    var fireCount = 0
    await confirmation("fires exactly once", expectedCount: 1) { fired in
      await withCheckedContinuation { (continuation: CheckedContinuation<(), Never>) in
        scheduler.schedule(
          after: scheduler.now.advanced(by: .milliseconds(20)),
          tolerance: .milliseconds(5),
          options: nil
        ) {
          fireCount += 1
          fired()
          continuation.resume()
        }
        #expect(scheduler.scheduledTimers.count == 1)
      }
    }
    // Drain window: an erroneously repeating timer would fire again within this period.
    await eventLoopSleep(milliseconds: 80)
    #expect(fireCount == 1)
    #expect(scheduler.scheduledTimers.isEmpty, "fired one-shot timers must not leak (issue #4)")
  }

  /// SC-07 — past date fires immediately (negative delay clamps to 0 per JS timer spec)
  @Test("schedule(after:) with a past date still fires")
  func oneShotPastDateFires() async {
    let scheduler = JSScheduler()
    await confirmation("fires despite past date") { fired in
      await withCheckedContinuation { (continuation: CheckedContinuation<(), Never>) in
        scheduler.schedule(
          after: JSScheduler.SchedulerTimeType(millisecondsValue: 0),
          tolerance: .milliseconds(0),
          options: nil
        ) {
          fired()
          continuation.resume()
        }
      }
    }
  }
}

// MARK: - schedule(after:interval:tolerance:options:_:) — repeating

struct JSSchedulerRepeatingScheduleTests {
  /// SC-08 — regression #5: the interval timer must repeat (it was created one-shot and
  /// fired only once). Cadence bands follow 06-test-data-strategy.md: lower bound
  /// interval − tolerance, generous upper bound for event-loop jitter under wasm runtimes.
  @Test("repeating schedule fires at least 3 times at the requested cadence")
  func repeatingScheduleFiresRepeatedly() async {
    let scheduler = JSScheduler()
    let intervalMs = 40.0
    var fireTimes = [Double]()
    var cancellable: (any Cancellable)?
    await confirmation("fires three times", expectedCount: 3) { fired in
      await withCheckedContinuation { (continuation: CheckedContinuation<(), Never>) in
        var resumed = false
        cancellable = scheduler.schedule(
          after: scheduler.now,
          interval: .milliseconds(Int(intervalMs)),
          tolerance: .milliseconds(10),
          options: nil
        ) {
          fireTimes.append(JSDate.now())
          if fireTimes.count <= 3 { fired() }
          if fireTimes.count == 3, !resumed {
            resumed = true
            continuation.resume()
          }
        }
      }
    }
    cancellable?.cancel()
    #expect(fireTimes.count >= 3, "repeating schedule must keep firing (issue #5)")
    // CT-SC-04 — monotonically increasing timestamps, cadence within tolerance band.
    for index in 1..<min(fireTimes.count, 3) {
      let gap = fireTimes[index] - fireTimes[index - 1]
      #expect(gap > 0, "fire timestamps must be monotonically increasing")
      #expect(
        gap >= intervalMs - 20.0 && gap <= intervalMs + 200.0,
        "cadence \(gap)ms outside tolerance band for \(intervalMs)ms interval"
      )
    }
  }

  /// SC-11 — regression #3: cancelling before the first fire used to force-unwrap the
  /// still-nil interval timer (crash) and left the pending timeout running.
  @Test("cancel() before the first fire is safe and prevents any fire")
  func cancelBeforeFirstFireIsSafe() async {
    let scheduler = JSScheduler()
    var fireCount = 0
    let cancellable = scheduler.schedule(
      after: scheduler.now.advanced(by: .milliseconds(40)),
      interval: .milliseconds(20),
      tolerance: .milliseconds(5),
      options: nil
    ) {
      fireCount += 1
    }
    // Must not crash (issue #3) and must clear the pending timeout timer immediately.
    cancellable.cancel()
    #expect(scheduler.scheduledTimers.isEmpty, "cancel() must clear the pending timeout timer")
    // Drain window long enough for the original timeout AND several intervals.
    await eventLoopSleep(milliseconds: 150)
    #expect(fireCount == 0, "no action may fire after cancel() (issue #3)")
  }

  /// SC-09 / CT-SC-05 — cancelling between repeats stops delivery and cleans up (issue #4)
  @Test("cancel() between repeats stops delivery and cleans up the interval timer")
  func cancelBetweenRepeatsStopsDelivery() async {
    let scheduler = JSScheduler()
    var fireCount = 0
    var cancellable: (any Cancellable)?
    await withCheckedContinuation { (continuation: CheckedContinuation<(), Never>) in
      var resumed = false
      cancellable = scheduler.schedule(
        after: scheduler.now,
        interval: .milliseconds(20),
        tolerance: .milliseconds(5),
        options: nil
      ) {
        fireCount += 1
        if fireCount == 2, !resumed {
          resumed = true
          continuation.resume()
        }
      }
    }
    cancellable?.cancel()
    let countAtCancel = fireCount
    #expect(scheduler.scheduledTimers.isEmpty, "cancel() must remove the interval timer (issue #4)")
    await eventLoopSleep(milliseconds: 120)
    #expect(fireCount == countAtCancel, "interval must stop delivering after cancel()")
  }

  /// SC-12 — double-cancel must be a no-op
  @Test("calling cancel() twice is a harmless no-op")
  func doubleCancelIsNoOp() async {
    let scheduler = JSScheduler()
    var fireCount = 0
    let cancellable = scheduler.schedule(
      after: scheduler.now.advanced(by: .milliseconds(30)),
      interval: .milliseconds(20),
      tolerance: .milliseconds(5),
      options: nil
    ) {
      fireCount += 1
    }
    cancellable.cancel()
    cancellable.cancel()
    await eventLoopSleep(milliseconds: 100)
    #expect(fireCount == 0)
    #expect(scheduler.scheduledTimers.isEmpty)
  }

  /// SC-10 — the scheduler remains usable after a cancellation
  @Test("scheduler continues to function after cancel()")
  func schedulerHealthyAfterCancel() async {
    let scheduler = JSScheduler()
    let cancellable = scheduler.schedule(
      after: scheduler.now,
      interval: .milliseconds(50),
      tolerance: .milliseconds(10),
      options: nil
    ) {}
    cancellable.cancel()
    await confirmation("scheduler still works after cancel") { works in
      await withCheckedContinuation { (continuation: CheckedContinuation<(), Never>) in
        scheduler.schedule(options: nil) {
          works()
          continuation.resume()
        }
      }
    }
  }
}
#endif

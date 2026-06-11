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

// Deterministic JSScheduler tests driven by VirtualClock (issue #14). These are exact-value
// variants of the timing-sensitive wasm suites in JSSchedulerTests.swift, which remain as
// real-timer integration coverage. No JavaScript runtime is involved, so every test in this
// file runs on the host (`swift test`) as well as on wasm — only the async-bridge suite at
// the bottom is wasm-gated, because awaiting requires the JS event-loop executor.

@testable import OpenCombineJS
import Testing

// Dual Combine backend — see Sources/OpenCombineJS/JSPromise.swift (issue #11).
#if canImport(Combine)
import Combine
#else
import OpenCombine
#endif

// MARK: - Clock injection and immediate scheduling

struct JSSchedulerVirtualClockTests {
  /// VC-01 — `now` is read through the injected clock source
  @Test("now reflects the injected clock and follows advance(by:)")
  func nowReflectsInjectedClock() {
    let clock = VirtualClock()
    let scheduler = JSScheduler(clock: clock)
    #expect(scheduler.now.millisecondsValue == 0)
    clock.advance(by: 1234)
    #expect(scheduler.now.millisecondsValue == 1234)
  }

  /// VC-02 — deterministic variant of SC-03/SC-04: asynchronous dispatch + cleanup (issue #4)
  @Test("schedule(options:_:) defers the action until the clock advances, then cleans up")
  func immediateScheduleDefersUntilAdvance() {
    let clock = VirtualClock()
    let scheduler = JSScheduler(clock: clock)
    var didRun = false
    scheduler.schedule(options: nil) { didRun = true }
    #expect(!didRun, "schedule(options:_:) must not execute the action synchronously")
    #expect(scheduler.scheduledTimers.count == 1)
    clock.advance(by: 0) // the next event-loop turn, virtualized
    #expect(didRun)
    #expect(scheduler.scheduledTimers.isEmpty, "fired one-shot timers must not leak (issue #4)")
    #expect(clock.pendingTimerCount == 0)
  }

  /// VC-03 — deterministic variant of SC-13: independent schedules, FIFO for equal due times
  @Test("multiple schedule(options:_:) calls fire independently in submission order")
  func immediateSchedulesFireInSubmissionOrder() {
    let clock = VirtualClock()
    let scheduler = JSScheduler(clock: clock)
    var order = [Int]()
    for index in 1...3 {
      scheduler.schedule(options: nil) { order.append(index) }
    }
    clock.advance(by: 0)
    #expect(order == [1, 2, 3])
    #expect(scheduler.scheduledTimers.isEmpty)
  }
}

// MARK: - One-shot scheduling

struct JSSchedulerVirtualClockOneShotTests {
  /// VC-04 — deterministic variant of SC-05: exact due time, exactly once, cleanup (issue #4)
  @Test("schedule(after:) fires exactly at the due time, exactly once, and cleans up")
  func oneShotFiresExactlyAtDueTime() {
    let clock = VirtualClock()
    let scheduler = JSScheduler(clock: clock)
    var fireCount = 0
    scheduler.schedule(
      after: scheduler.now.advanced(by: .milliseconds(50)),
      tolerance: .milliseconds(5),
      options: nil
    ) {
      fireCount += 1
    }
    clock.advance(by: 49)
    #expect(fireCount == 0, "timer must not fire before its due time")
    clock.advance(by: 1)
    #expect(fireCount == 1)
    clock.advance(by: 500) // an erroneously repeating timer would fire again here
    #expect(fireCount == 1, "one-shot timer must fire exactly once")
    #expect(scheduler.scheduledTimers.isEmpty, "fired one-shot timers must not leak (issue #4)")
    #expect(clock.pendingTimerCount == 0)
  }

  /// VC-05 — deterministic variant of SC-07: past dates clamp to zero delay
  @Test("schedule(after:) with a past date fires on the next clock advance")
  func oneShotPastDateFiresImmediately() {
    let clock = VirtualClock()
    clock.advance(by: 100)
    let scheduler = JSScheduler(clock: clock)
    var didFire = false
    scheduler.schedule(
      after: JSScheduler.SchedulerTimeType(millisecondsValue: 0), // 100 ms in the past
      tolerance: .milliseconds(0),
      options: nil
    ) {
      didFire = true
    }
    #expect(!didFire)
    clock.advance(by: 0)
    #expect(didFire, "negative delays must clamp to 0 (JS timer semantics)")
  }

  /// VC-06 — due-time ordering is independent of submission order
  @Test("one-shot timers fire in due-time order regardless of scheduling order")
  func oneShotsFireInDueTimeOrder() {
    let clock = VirtualClock()
    let scheduler = JSScheduler(clock: clock)
    var order = [String]()
    scheduler.schedule(
      after: scheduler.now.advanced(by: .milliseconds(30)),
      tolerance: .milliseconds(0),
      options: nil
    ) {
      order.append("later")
    }
    scheduler.schedule(
      after: scheduler.now.advanced(by: .milliseconds(10)),
      tolerance: .milliseconds(0),
      options: nil
    ) {
      order.append("sooner")
    }
    clock.advance(by: 30)
    #expect(order == ["sooner", "later"])
  }
}

// MARK: - Repeating scheduling

struct JSSchedulerVirtualClockRepeatingTests {
  /// VC-07 — deterministic variant of SC-08 (issue #5): exact first-fire time and cadence.
  /// The wasm test asserts a [interval−20 ms, interval+200 ms] jitter band; the virtual clock
  /// pins both the first fire (date + interval) and every subsequent tick to exact values.
  @Test("repeating schedule first fires at date + interval, then exactly once per interval")
  func repeatingScheduleHasExactCadence() {
    let clock = VirtualClock()
    let scheduler = JSScheduler(clock: clock)
    var fireTimes = [Double]()
    let cancellable = scheduler.schedule(
      after: scheduler.now.advanced(by: .milliseconds(40)),
      interval: .milliseconds(20),
      tolerance: .milliseconds(10),
      options: nil
    ) {
      fireTimes.append(clock.now)
    }
    clock.advance(by: 40) // reaches the start date: interval armed, no action fire yet
    #expect(fireTimes.isEmpty, "first invocation fires one interval after the start date")
    #expect(
      scheduler.scheduledTimers.count == 1,
      "timeout token must be replaced by the interval token"
    )
    clock.advance(by: 19)
    #expect(fireTimes.isEmpty)
    clock.advance(by: 1)
    #expect(fireTimes == [60])
    clock.advance(by: 60) // three full intervals
    #expect(fireTimes == [60, 80, 100, 120], "exactly one fire per interval (issue #5)")
    cancellable.cancel()
    #expect(scheduler.scheduledTimers.isEmpty)
    #expect(clock.pendingTimerCount == 0)
  }

  /// VC-08 — deterministic variant of SC-11 (issue #3): cancel before the first fire
  @Test("cancel() before the first fire clears both tokens and prevents any fire")
  func cancelBeforeFirstFirePreventsEverything() {
    let clock = VirtualClock()
    let scheduler = JSScheduler(clock: clock)
    var fireCount = 0
    let cancellable = scheduler.schedule(
      after: scheduler.now.advanced(by: .milliseconds(40)),
      interval: .milliseconds(20),
      tolerance: .milliseconds(5),
      options: nil
    ) {
      fireCount += 1
    }
    cancellable.cancel()
    #expect(scheduler.scheduledTimers.isEmpty, "cancel() must clear the pending timeout (issue #3)")
    #expect(clock.pendingTimerCount == 0, "cancellation must reach the clock source")
    clock.advance(by: 500)
    #expect(fireCount == 0, "no action may fire after cancel() (issue #3)")
  }

  /// VC-09 — deterministic variant of SC-09 (issue #4): cancel between repeats
  @Test("cancel() between repeats freezes the fire count and cleans up")
  func cancelBetweenRepeatsStopsDelivery() {
    let clock = VirtualClock()
    let scheduler = JSScheduler(clock: clock)
    var fireCount = 0
    let cancellable = scheduler.schedule(
      after: scheduler.now,
      interval: .milliseconds(20),
      tolerance: .milliseconds(5),
      options: nil
    ) {
      fireCount += 1
    }
    clock.advance(by: 40) // start (t=0) + two intervals
    #expect(fireCount == 2)
    cancellable.cancel()
    #expect(scheduler.scheduledTimers.isEmpty, "cancel() must remove the interval token (issue #4)")
    #expect(clock.pendingTimerCount == 0)
    clock.advance(by: 500)
    #expect(fireCount == 2, "interval must stop delivering after cancel()")
  }

  /// VC-10 — deterministic variant of SC-12: double cancel is a no-op
  @Test("calling cancel() twice is a harmless no-op")
  func doubleCancelIsNoOp() {
    let clock = VirtualClock()
    let scheduler = JSScheduler(clock: clock)
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
    clock.advance(by: 200)
    #expect(fireCount == 0)
    #expect(scheduler.scheduledTimers.isEmpty)
    #expect(clock.pendingTimerCount == 0)
  }

  /// VC-11 — deterministic variant of SC-10: the scheduler stays usable after cancellation
  @Test("scheduler continues to function after cancel()")
  func schedulerHealthyAfterCancel() {
    let clock = VirtualClock()
    let scheduler = JSScheduler(clock: clock)
    let cancellable = scheduler.schedule(
      after: scheduler.now,
      interval: .milliseconds(50),
      tolerance: .milliseconds(10),
      options: nil
    ) {}
    cancellable.cancel()
    var didRun = false
    scheduler.schedule(options: nil) { didRun = true }
    clock.advance(by: 0)
    #expect(didRun)
  }
}

// MARK: - Async bridge over the injected clock (wasm-only: awaiting needs the JS executor)

#if os(WASI)
import JavaScriptKit

struct JSSchedulerVirtualClockAsyncTests {
  /// VC-A1 — `sleep(for:)` registers with the injected clock and resumes when it advances.
  /// The real 0 ms `JSTimer` only drives the event loop; all *scheduling* time is virtual:
  /// its callback cannot run before `sleep` suspends, because the JS event loop only regains
  /// control at the suspension point.
  @Test("sleep(for:) suspends until the injected clock advances past the deadline")
  func sleepIsDrivenByInjectedClock() async {
    let clock = VirtualClock()
    let scheduler = JSScheduler(clock: clock)
    var didAdvance = false
    let driver = JSTimer(millisecondsDelay: 0) {
      #expect(clock.pendingTimerCount == 1, "sleep must register its one-shot with the clock")
      clock.advance(by: 50)
      didAdvance = true
    }
    await scheduler.sleep(for: .milliseconds(50))
    withExtendedLifetime(driver) {}
    #expect(didAdvance, "the continuation must be resumed by the virtual timer")
    #expect(clock.now == 50)
    #expect(scheduler.scheduledTimers.isEmpty, "sleep must not leak its one-shot entry")
    #expect(clock.pendingTimerCount == 0)
  }

  /// VC-A2 — `timer(interval:)` ticks are produced by the injected clock; breaking out of the
  /// loop cancels all the way down to the clock source. Each real event-loop turn advances
  /// virtual time by exactly one interval, producing exactly one tick per turn.
  @Test("timer(interval:) ticks follow the injected clock and break cancels the virtual timer")
  func asyncTimerIsDrivenByInjectedClock() async {
    let clock = VirtualClock()
    let scheduler = JSScheduler(clock: clock)
    let driver = JSTimer(millisecondsDelay: 1, isRepeating: true) {
      clock.advance(by: 10)
    }
    var ticks = 0
    for await _ in scheduler.timer(interval: .milliseconds(10)) {
      ticks += 1
      if ticks == 3 { break }
    }
    withExtendedLifetime(driver) {}
    #expect(ticks == 3)
    #expect(clock.now == 30, "three ticks must consume exactly three virtual intervals")
    #expect(scheduler.scheduledTimers.isEmpty, "stream termination must release both tokens")
    #expect(clock.pendingTimerCount == 0, "cancellation must reach the injected clock")
  }
}
#endif

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

// Deterministic, manually advanced JSClockSource (06-test-data-strategy.md §3.2 Option A /
// §3.6, implemented by issue #14). Pure Swift — no JavaScript runtime required, so tests
// built on it run on the host (`swift test`) as well as on wasm.

import OpenCombineJS

/// A virtual clock for deterministic scheduler tests.
///
/// Time starts at `0` ms and only moves when `advance(by:)` is called. Timers fire
/// synchronously inside `advance(by:)`, ordered by due time and — for equal due times — by
/// creation order, mirroring the JavaScript timer queue. Negative delays clamp to `0`
/// (JS `setTimeout` semantics); repeating intervals clamp to a minimum of 1 ms so a
/// zero-interval repeating timer cannot loop `advance(by:)` forever (browsers apply a
/// similar minimum clamp to nested `setInterval`).
final class VirtualClock: JSClockSource {
  private struct PendingTimer {
    let id: UInt64
    var dueTime: Double
    /// `nil` for one-shot timers; the repetition period otherwise.
    let interval: Double?
    let callback: () -> ()
  }

  /// Current virtual time in milliseconds. Starts at `0`.
  private(set) var now: Double = 0

  /// Number of timers currently registered (pending one-shots + live repeating timers).
  /// Lets tests assert that cancellation reached the clock, not just the scheduler's table.
  var pendingTimerCount: Int {
    pending.count
  }

  private var pending = [UInt64: PendingTimer]()
  private var nextID: UInt64 = 0

  func makeTimer(
    millisecondsDelay: Double,
    isRepeating: Bool,
    callback: @escaping () -> ()
  ) -> any JSClockCancellable {
    let id = nextID
    nextID += 1
    let delay = max(0, millisecondsDelay) // JS timers clamp negative delays to 0.
    pending[id] = PendingTimer(
      id: id,
      dueTime: now + delay,
      interval: isRepeating ? max(1, delay) : nil,
      callback: callback
    )
    return Token(clock: self, id: id)
  }

  /// Advances virtual time by `milliseconds`, firing every timer that becomes due — in due-time
  /// order, ties broken by creation order — including timers scheduled or cancelled by the fired
  /// callbacks themselves (a callback-scheduled timer due inside the window fires in the same
  /// `advance`). Repeating timers fire once per elapsed period. Afterwards `now` equals the old
  /// `now` plus `milliseconds`, even if no timer was due.
  func advance(by milliseconds: Double) {
    precondition(milliseconds >= 0, "VirtualClock cannot move backwards")
    let target = now + milliseconds
    while let next = pending.values
      .filter({ $0.dueTime <= target })
      .min(by: { ($0.dueTime, $0.id) < ($1.dueTime, $1.id) })
    {
      now = max(now, next.dueTime)
      // Reschedule/remove BEFORE invoking the callback so the callback observes the same
      // registration state a JS timer callback would (and may cancel its own repetition).
      if let interval = next.interval {
        pending[next.id]?.dueTime = next.dueTime + interval
      } else {
        pending[next.id] = nil
      }
      next.callback()
    }
    now = target
  }

  private func cancelTimer(id: UInt64) {
    pending[id] = nil
  }

  /// Cancellation token. Explicit `cancel()` and deinitialization both unregister the timer,
  /// mirroring `JSTimer`'s release-to-clear reference semantics.
  private final class Token: JSClockCancellable {
    private weak var clock: VirtualClock?
    private let id: UInt64

    init(clock: VirtualClock, id: UInt64) {
      self.clock = clock
      self.id = id
    }

    deinit {
      cancel()
    }

    func cancel() {
      clock?.cancelTimer(id: id)
      clock = nil
    }
  }
}

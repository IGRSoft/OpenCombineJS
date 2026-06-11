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

#if os(WASI)
import JavaScriptKit

/// Suspends the current task for the given duration by scheduling a one-shot JS timer, letting
/// the JS event loop process any pending timers in the meantime. Used as a deterministic drain
/// window (06-test-data-strategy.md §2) instead of `Task.sleep`, so the suspension mechanism is
/// independent of the code under test.
func eventLoopSleep(milliseconds: Double) async {
  var timer: JSTimer?
  await withCheckedContinuation { (continuation: CheckedContinuation<(), Never>) in
    timer = JSTimer(millisecondsDelay: milliseconds) {
      continuation.resume()
    }
  }
  // Keep the timer reference alive until it has fired; deallocating it earlier would call
  // `clearTimeout` and the continuation would never resume.
  withExtendedLifetime(timer) {}
}
#endif

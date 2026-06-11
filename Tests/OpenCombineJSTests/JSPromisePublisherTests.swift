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

// Tests for JSPromise.PromisePublisher and PromiseError. WASI-only: a live JS Promise object
// and the JS event loop (microtask queue) are required.

#if os(WASI)
import JavaScriptKit
import OpenCombine
@testable import OpenCombineJS
import Testing

// MARK: - PromiseError

struct PromiseErrorTests {
  /// JP-01 — initializer stores the JSValue
  @Test("PromiseError stores the wrapped JSValue")
  func promiseErrorStoresValue() {
    let reason = JSValue.string("rejection reason")
    #expect(JSPromise.PromiseError(reason).value == reason)
  }

  /// JP-02 — Equatable: equal values
  @Test("PromiseError instances wrapping the same JSValue are equal")
  func promiseErrorEqualityEqual() {
    let value = JSValue.number(42)
    #expect(JSPromise.PromiseError(value) == JSPromise.PromiseError(value))
  }

  /// JP-03 — Equatable: different values
  @Test("PromiseError instances wrapping different JSValues are not equal")
  func promiseErrorEqualityNotEqual() {
    #expect(JSPromise.PromiseError(.number(1)) != JSPromise.PromiseError(.number(2)))
  }
}

// MARK: - publisher computed property

struct JSPromisePublisherVarTests {
  /// JP-09 — each access returns a fresh publisher instance
  @Test(".publisher returns a new PromisePublisher on each access")
  func publisherVarReturnsDistinctInstances() {
    let promise = JSPromise.resolve(JSValue.string("value"))
    #expect(promise.publisher !== promise.publisher)
  }
}

// MARK: - Success path

struct JSPromisePublisherSuccessTests {
  /// JP-06 / CT-JP-01 — resolved promise delivers exactly one value, then .finished
  @Test("resolved Promise delivers one value then .finished")
  func resolvedPromiseDeliversValueThenFinished() async {
    let expected = JSValue.string("success-output")
    let publisher = JSPromise.resolve(expected).publisher
    var values = [JSValue]()
    var completions = [Subscribers.Completion<JSPromise.PromiseError>]()
    var sink: AnyCancellable?

    await confirmation("completion received") { completionReceived in
      await withCheckedContinuation { (continuation: CheckedContinuation<(), Never>) in
        sink = publisher.sink(
          receiveCompletion: { completion in
            completions.append(completion)
            completionReceived()
            continuation.resume()
          },
          receiveValue: { values.append($0) }
        )
      }
    }
    withExtendedLifetime(sink) {}

    #expect(values == [expected])
    #expect(completions.count == 1)
    guard case .finished = completions.first else {
      Issue.record("Expected .finished, got \(String(describing: completions.first))")
      return
    }
  }

  /// JP-04 / JP-08 / CT-JP-03 — Future caching: an already-resolved promise replays its
  /// result to subscribers attaching after resolution.
  @Test("already-resolved Promise replays the cached result to late subscribers")
  func lateSubscriberReceivesCachedResult() async {
    let expected = JSValue.string("cached-value")
    let publisher = JSPromise.resolve(expected).publisher

    var firstValue: JSValue?
    var firstSink: AnyCancellable?
    await withCheckedContinuation { (continuation: CheckedContinuation<(), Never>) in
      firstSink = publisher.sink(
        receiveCompletion: { _ in continuation.resume() },
        receiveValue: { firstValue = $0 }
      )
    }
    withExtendedLifetime(firstSink) {}

    // Second subscriber attaches after the Future already captured the result.
    var secondValue: JSValue?
    var secondSink: AnyCancellable?
    await withCheckedContinuation { (continuation: CheckedContinuation<(), Never>) in
      secondSink = publisher.sink(
        receiveCompletion: { _ in continuation.resume() },
        receiveValue: { secondValue = $0 }
      )
    }
    withExtendedLifetime(secondSink) {}

    #expect(firstValue == expected)
    #expect(secondValue == expected, "Future must replay its cached result to late subscribers")
  }

  /// JP-05 / JP-08 — multiple simultaneous subscribers all receive the value
  @Test("multiple subscribers attached before resolution all receive the value")
  func multipleSubscribersReceiveTheValue() async {
    var resolveHandler: ((JSPromise.Result) -> ())?
    let promise = JSPromise { resolveHandler = $0 }
    let publisher = promise.publisher

    var firstValue: JSValue?
    var secondValue: JSValue?
    var sinks = [AnyCancellable]()

    await confirmation("both subscribers complete", expectedCount: 2) { completed in
      await withCheckedContinuation { (continuation: CheckedContinuation<(), Never>) in
        var remaining = 2
        let finish = {
          completed()
          remaining -= 1
          if remaining == 0 { continuation.resume() }
        }
        sinks.append(publisher.sink(
          receiveCompletion: { _ in finish() },
          receiveValue: { firstValue = $0 }
        ))
        sinks.append(publisher.sink(
          receiveCompletion: { _ in finish() },
          receiveValue: { secondValue = $0 }
        ))
        resolveHandler?(.success(.string("shared")))
      }
    }
    withExtendedLifetime(sinks) {}

    #expect(firstValue == .string("shared"))
    #expect(secondValue == .string("shared"))
  }
}

// MARK: - Failure path

struct JSPromisePublisherFailureTests {
  /// JP-07 / CT-JP-02 — rejected promise delivers no values and .failure(PromiseError)
  @Test("rejected Promise delivers .failure(PromiseError) and no values")
  func rejectedPromiseDeliversTypedError() async {
    let rejectionReason = JSValue.string("rejection-reason")
    let publisher = JSPromise.reject(rejectionReason).publisher
    var values = [JSValue]()
    var receivedError: JSPromise.PromiseError?
    var sink: AnyCancellable?

    await confirmation("failure completion received") { completionReceived in
      await withCheckedContinuation { (continuation: CheckedContinuation<(), Never>) in
        sink = publisher.sink(
          receiveCompletion: { completion in
            if case let .failure(error) = completion {
              receivedError = error
            }
            completionReceived()
            continuation.resume()
          },
          receiveValue: { values.append($0) }
        )
      }
    }
    withExtendedLifetime(sink) {}

    #expect(values.isEmpty, "a rejected Promise must produce no output values")
    #expect(receivedError?.value == rejectionReason)
  }
}

// MARK: - Subscription cancellation

struct JSPromisePublisherCancellationTests {
  /// CT-JP-04 — documented behavior: a subscription cancelled before the promise settles
  /// receives neither values nor completion (OpenCombine Future honors cancellation).
  @Test("subscription cancelled before resolution receives no value or completion")
  func cancelledSubscriptionReceivesNothing() async {
    var resolveHandler: ((JSPromise.Result) -> ())?
    let promise = JSPromise { resolveHandler = $0 }

    var receivedValues = [JSValue]()
    var receivedCompletions = 0
    var subscription: (any Subscription)?

    let subscriber = AnySubscriber<JSValue, JSPromise.PromiseError>(
      receiveSubscription: { incoming in
        subscription = incoming
        incoming.request(.unlimited)
      },
      receiveValue: { value in
        receivedValues.append(value)
        return .none
      },
      receiveCompletion: { _ in
        receivedCompletions += 1
      }
    )
    promise.publisher.receive(subscriber: subscriber)

    // Cancel before the promise settles, then resolve it.
    subscription?.cancel()
    resolveHandler?(.success(.string("should-not-arrive")))

    // Drain the microtask/macrotask queues so a (buggy) delivery would surface.
    await eventLoopSleep(milliseconds: 50)

    #expect(receivedValues.isEmpty, "no value may be delivered after cancel()")
    #expect(receivedCompletions == 0, "no completion may be delivered after cancel()")
  }
}
#endif

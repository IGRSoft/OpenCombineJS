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

// Tests for JSScheduler.SchedulerTimeType and its Stride.
// Pure Swift — no JS runtime dependency; runs on host (`swift test`) and on wasm.

@testable import OpenCombineJS
import Testing

private typealias TimeType = JSScheduler.SchedulerTimeType
private typealias Stride = JSScheduler.SchedulerTimeType.Stride

// MARK: - SchedulerTimeType Strideable conformance

struct SchedulerTimeTypeStrideableTests {
  /// ST-01 — positive stride advance
  @Test("advanced(by:) with positive stride increases milliseconds value")
  func advancedByPositiveStride() {
    let base = TimeType(millisecondsValue: 1000.0)
    let result = base.advanced(by: Stride(millisecondsValue: 500.0))
    #expect(result.millisecondsValue == 1500.0)
  }

  /// ST-02 — negative stride advance
  @Test("advanced(by:) with negative stride decreases milliseconds value")
  func advancedByNegativeStride() {
    let base = TimeType(millisecondsValue: 1000.0)
    let result = base.advanced(by: Stride(millisecondsValue: -200.0))
    #expect(result.millisecondsValue == 800.0)
  }

  /// ST-03 — distance to later time is positive
  @Test("distance(to:) with later target returns positive Stride")
  func distanceToLaterTimeIsPositive() {
    let earlier = TimeType(millisecondsValue: 1000.0)
    let later = TimeType(millisecondsValue: 2500.0)
    #expect(earlier.distance(to: later).magnitude == 1500.0)
  }

  /// ST-04 — distance to earlier time is negative
  @Test("distance(to:) with earlier target returns negative Stride")
  func distanceToEarlierTimeIsNegative() {
    let later = TimeType(millisecondsValue: 2000.0)
    let earlier = TimeType(millisecondsValue: 500.0)
    #expect(later.distance(to: earlier).magnitude == -1500.0)
  }

  /// ST-05 — distance to same time is zero
  @Test("distance(to:) with equal times returns zero Stride")
  func distanceToSameTimeIsZero() {
    let time = TimeType(millisecondsValue: 1234.0)
    #expect(time.distance(to: time).magnitude == 0.0)
  }

  /// ST-03/ST-04 — Strideable law: x.distance(to: x.advanced(by: n)) == n
  @Test(
    "Strideable law: distance(to: advanced(by:)) recovers the stride",
    arguments: [300.0, -300.0, 0.0, 0.25]
  )
  func strideableAdvanceDistanceLaw(strideMs: Double) {
    let base = TimeType(millisecondsValue: 1000.0)
    let advanced = base.advanced(by: Stride(millisecondsValue: strideMs))
    #expect(base.distance(to: advanced).magnitude == strideMs)
  }

  /// Strideable law: x.advanced(by: x.distance(to: y)) == y
  @Test("Strideable law: advanced(by: distance(to:)) reaches the target")
  func strideableDistanceAdvanceLaw() {
    let from = TimeType(millisecondsValue: 250.0)
    let to = TimeType(millisecondsValue: 4750.0)
    let reached = from.advanced(by: from.distance(to: to))
    #expect(reached.millisecondsValue == to.millisecondsValue)
  }

  /// Comparable derived from Strideable
  @Test("SchedulerTimeType ordering follows milliseconds values")
  func timeTypeComparable() {
    let earlier = TimeType(millisecondsValue: 1.0)
    let later = TimeType(millisecondsValue: 2.0)
    #expect(earlier < later)
    #expect(!(later < earlier))
    #expect(earlier == TimeType(millisecondsValue: 1.0))
  }
}

// MARK: - Stride factory methods

struct StrideFactoryTests {
  /// ST-08 — seconds(Double)
  @Test("Stride.seconds(Double) converts to milliseconds")
  func secondsDoubleFactory() {
    #expect(Stride.seconds(1.0).magnitude == 1000.0)
    #expect(Stride.seconds(0.5).magnitude == 500.0)
  }

  /// ST-09 — seconds(Int)
  @Test("Stride.seconds(Int) converts to milliseconds")
  func secondsIntFactory() {
    #expect(Stride.seconds(2).magnitude == 2000.0)
  }

  /// ST-10 — milliseconds
  @Test("Stride.milliseconds preserves the millisecond value")
  func millisecondsFactory() {
    #expect(Stride.milliseconds(250).magnitude == 250.0)
  }

  /// ST-11 — regression for issue #2: the microseconds formula was inverted
  /// (`1.0 / (us * 1000)`). Correct conversion: 1000 µs == 1 ms.
  @Test("Stride.microseconds converts correctly (regression #2)")
  func microsecondsFactory() {
    #expect(Stride.microseconds(1000) == Stride.milliseconds(1))
    #expect(Stride.microseconds(1).magnitude == 0.001)
    #expect(Stride.microseconds(2).magnitude == 0.002)
    #expect(Stride.microseconds(2_000_000) == Stride.seconds(2))
  }

  /// ST-12 — regression for issue #2: the nanoseconds formula was inverted
  /// (`1.0 / (ns * 1_000_000)`). Correct conversion: 1_000_000 ns == 1 ms.
  @Test("Stride.nanoseconds converts correctly (regression #2)")
  func nanosecondsFactory() {
    #expect(Stride.nanoseconds(1_000_000) == Stride.milliseconds(1))
    #expect(Stride.nanoseconds(1).magnitude == 0.000001)
    #expect(Stride.nanoseconds(2).magnitude == 0.000002)
    #expect(Stride.nanoseconds(2_000_000_000) == Stride.seconds(2))
  }

  /// ST-08..ST-12 — unit round-trips through the millisecond base unit
  @Test("Stride unit factories agree on equivalent durations (regression #2)")
  func unitFactoriesRoundTrip() {
    #expect(Stride.seconds(1) == Stride.milliseconds(1000))
    #expect(Stride.milliseconds(1) == Stride.microseconds(1000))
    #expect(Stride.microseconds(1) == Stride.nanoseconds(1000))
    #expect(Stride.seconds(1) == Stride.nanoseconds(1_000_000_000))
  }

  /// ST-13 — float literal initializer delegates to seconds(Double).
  /// Note: Stride declares init(floatLiteral:) but does not conform to
  /// ExpressibleByFloatLiteral, so `let s: Stride = 0.5` does not compile; the
  /// initializer is exercised directly.
  @Test("Stride float literal initializer delegates to seconds(Double)")
  func floatLiteralInit() {
    let stride = Stride(floatLiteral: 0.5)
    #expect(stride.magnitude == 500.0)
  }

  /// ST-14 — integer literal delegates to seconds(Int)
  @Test("Stride integer literal initializer delegates to seconds(Int)")
  func integerLiteralInit() {
    let stride: Stride = 3
    #expect(stride.magnitude == 3000.0)
  }

  /// ST-06 — init?(exactly:) success
  @Test("Stride.init?(exactly:) succeeds for representable BinaryInteger")
  func exactlyInitSuccess() {
    let stride = Stride(exactly: 42)
    #expect(stride?.magnitude == 42.0)
  }

  /// ST-07 — init?(exactly:) nil for values beyond Double precision
  @Test("Stride.init?(exactly:) returns nil for non-representable UInt64")
  func exactlyInitFailure() {
    // UInt64.max is not exactly representable as Double.
    #expect(Stride(exactly: UInt64.max) == nil)
  }
}

// MARK: - Stride arithmetic and comparison

struct StrideArithmeticTests {
  /// ST-15 — addition
  @Test("Stride addition adds magnitudes")
  func strideAddition() {
    let sum = Stride(millisecondsValue: 100.0) + Stride(millisecondsValue: 200.0)
    #expect(sum.magnitude == 300.0)
  }

  /// ST-16 — subtraction
  @Test("Stride subtraction subtracts magnitudes")
  func strideSubtraction() {
    let difference = Stride(millisecondsValue: 500.0) - Stride(millisecondsValue: 150.0)
    #expect(difference.magnitude == 350.0)
  }

  /// ST-17 — multiplication
  @Test("Stride multiplication multiplies magnitudes")
  func strideMultiplication() {
    let product = Stride(millisecondsValue: 100.0) * Stride(millisecondsValue: 3.0)
    #expect(product.magnitude == 300.0)
  }

  /// ST-18 — compound assignment
  @Test("Stride compound assignment operators mutate in place")
  func strideCompoundAssignment() {
    var stride = Stride(millisecondsValue: 100.0)
    stride += Stride(millisecondsValue: 50.0)
    #expect(stride.magnitude == 150.0)
    stride -= Stride(millisecondsValue: 30.0)
    #expect(stride.magnitude == 120.0)
    stride *= Stride(millisecondsValue: 2.0)
    #expect(stride.magnitude == 240.0)
  }

  /// ST-19 — comparison
  @Test("Stride comparison orders by magnitude")
  func strideComparison() {
    let small = Stride(millisecondsValue: 100.0)
    let large = Stride(millisecondsValue: 200.0)
    #expect(small < large)
    #expect(!(large < small))
    #expect(!(small < small))
  }

  /// ST-20 — SignedNumeric negation
  @Test("Stride negation flips the magnitude sign")
  func strideNegation() {
    let positive = Stride(millisecondsValue: 75.0)
    #expect((-positive).magnitude == -75.0)
    var mutable = Stride(millisecondsValue: 75.0)
    mutable.negate()
    #expect(mutable.magnitude == -75.0)
  }
}

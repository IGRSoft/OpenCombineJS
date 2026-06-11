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

// Tests for the JSValueDecoder TopLevelDecoder conformance. WASI-only: JSValueDecoder walks
// JSValue contents through the JavaScriptKit runtime, which requires a live JS host.
// Fixture IDs (F-xx) refer to 06-test-data-strategy.md §1.4.

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

// MARK: - TopLevelDecoder conformance

struct JSValueDecoderConformanceTests {
  /// JD-07 — the @retroactive conformance is accessible as a protocol existential
  @Test("JSValueDecoder is usable as any TopLevelDecoder existential")
  func topLevelDecoderConformanceIsAccessible() {
    let decoder: any TopLevelDecoder = JSValueDecoder()
    #expect(type(of: decoder) == JSValueDecoder.self)
  }

  /// JD-01 — decode(_:from:) delegates to decode(_:from:userInfo:[:])
  @Test("decode(_:from:) matches decode(_:from:userInfo:[:])")
  func delegationToUserInfoOverload() throws {
    let decoder = JSValueDecoder()
    let input = JSFixtures.stringASCII()
    let viaTopLevel = try decoder.decode(String.self, from: input)
    let viaUserInfo = try decoder.decode(String.self, from: input, userInfo: [:])
    #expect(viaTopLevel == viaUserInfo)
  }
}

// MARK: - Primitive decode paths

struct JSValueDecoderPrimitiveTests {
  /// JD-03 / F-01 — string primitive
  @Test("decodes a JSValue.string to String")
  func decodeString() throws {
    let result = try JSValueDecoder().decode(String.self, from: JSFixtures.stringASCII())
    #expect(result == "hello")
  }

  /// JD-03 / F-03 — Unicode string
  @Test("decodes a Unicode JSValue.string to String")
  func decodeUnicodeString() throws {
    let result = try JSValueDecoder().decode(String.self, from: JSFixtures.stringUnicode())
    #expect(result == "こんにちは")
  }

  /// JD-04 / F-09 — number as Double
  @Test("decodes a JSValue.number to Double")
  func decodeDouble() throws {
    let result = try JSValueDecoder().decode(Double.self, from: JSFixtures.numberFinite())
    #expect(result == 3.14)
  }

  /// JD-04 — number as Int
  @Test("decodes a JSValue.number to Int")
  func decodeInt() throws {
    let result = try JSValueDecoder().decode(Int.self, from: .number(42))
    #expect(result == 42)
  }

  /// JD-05 / F-21, F-22 — booleans
  @Test("decodes JSValue.boolean to Bool")
  func decodeBool() throws {
    let decoder = JSValueDecoder()
    #expect(try decoder.decode(Bool.self, from: JSFixtures.boolTrue()) == true)
    #expect(try decoder.decode(Bool.self, from: JSFixtures.boolFalse()) == false)
  }

  /// JD-06 / F-08 — type mismatch throws
  @Test("throws when the JSValue type mismatches the requested Swift type")
  func decodeMismatchedTypeThrows() {
    #expect(throws: (any Error).self) {
      try JSValueDecoder().decode(Int.self, from: JSFixtures.stringASCII())
    }
  }
}

// MARK: - Object decode paths

struct JSValueDecoderObjectTests {
  /// JD-02 / F-28 — flat object decodes into a struct
  @Test("decodes a flat JS object into a Decodable struct")
  func decodeFlatObject() throws {
    let person = try JSValueDecoder().decode(Person.self, from: JSFixtures.objectFlat())
    #expect(person == Person(name: "Alice", age: 30))
  }

  /// F-29 — missing key produces a DecodingError
  @Test("throws when a required key is missing from the JS object")
  func decodeMissingKeyThrows() {
    #expect(throws: (any Error).self) {
      try JSValueDecoder().decode(Person.self, from: JSFixtures.objectMissingKey())
    }
  }

  /// F-30 — nested object decodes recursively
  @Test("decodes a nested JS object")
  func decodeNestedObject() throws {
    let wrapper = try JSValueDecoder().decode(UserWrapper.self, from: JSFixtures.objectNested())
    #expect(wrapper == UserWrapper(user: .init(id: 1, label: "admin")))
  }

  /// F-37 — optional field present
  @Test("decodes an optional field when present")
  func decodeOptionalPresent() throws {
    let result = try JSValueDecoder()
      .decode(WithOptional.self, from: JSFixtures.objectOptionalPresent())
    #expect(result == WithOptional(name: "Carol", nickname: "C"))
  }

  /// F-38 — optional field absent decodes to nil
  @Test("decodes an absent optional field to nil")
  func decodeOptionalAbsent() throws {
    let result = try JSValueDecoder()
      .decode(WithOptional.self, from: JSFixtures.objectOptionalAbsent())
    #expect(result == WithOptional(name: "Dave", nickname: nil))
  }
}

// MARK: - Array decode paths

struct JSValueDecoderArrayTests {
  /// F-32 — homogeneous array
  @Test("decodes a homogeneous JS array to [Int]")
  func decodeHomogeneousArray() throws {
    let result = try JSValueDecoder().decode([Int].self, from: JSFixtures.arrayHomogeneous())
    #expect(result == [1, 2, 3, 4, 5])
  }

  /// F-35 — empty array
  @Test("decodes an empty JS array to []")
  func decodeEmptyArray() throws {
    let result = try JSValueDecoder().decode([Int].self, from: JSFixtures.arrayEmpty())
    #expect(result.isEmpty)
  }

  /// F-36 — array of objects
  @Test("decodes a JS array of objects to an array of structs")
  func decodeArrayOfObjects() throws {
    let result = try JSValueDecoder().decode([Point].self, from: JSFixtures.arrayOfObjects())
    #expect(result == [Point(x: 1), Point(x: 2)])
  }
}
#endif

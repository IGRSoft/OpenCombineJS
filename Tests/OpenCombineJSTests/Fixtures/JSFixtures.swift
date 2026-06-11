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

// Central in-code factory for JSValue test fixtures (06-test-data-strategy.md §1).
// Fixtures are constructed programmatically — no file I/O — so they bundle into the
// single-module wasm test binary without a data-loading layer.

#if os(WASI)
import JavaScriptKit

enum JSFixtures {
  // ── Primitives ───────────────────────────────────────────────────────────

  /// F-01 — plain ASCII string.
  static func stringASCII() -> JSValue {
    .string("hello")
  }

  /// F-03 — Unicode multibyte string.
  static func stringUnicode() -> JSValue {
    .string("こんにちは")
  }

  /// F-09 — finite positive double.
  static func numberFinite() -> JSValue {
    .number(3.14)
  }

  /// F-21 / F-22 — booleans.
  static func boolTrue() -> JSValue {
    .boolean(true)
  }

  static func boolFalse() -> JSValue {
    .boolean(false)
  }

  // ── Objects (require a live JS heap) ─────────────────────────────────────

  /// F-28 — flat object: `{ "name": "Alice", "age": 30 }`.
  static func objectFlat() -> JSValue {
    let object = JSObject.global.Object.function!.new()
    object.name = .string("Alice")
    object.age = .number(30)
    return .object(object)
  }

  /// F-29 — object with a missing key (no `age`): `{ "name": "Bob" }`.
  static func objectMissingKey() -> JSValue {
    let object = JSObject.global.Object.function!.new()
    object.name = .string("Bob")
    return .object(object)
  }

  /// F-30 — nested object: `{ "user": { "id": 1, "label": "admin" } }`.
  static func objectNested() -> JSValue {
    JSObject.global.JSON.parse(#"{"user":{"id":1,"label":"admin"}}"#)
  }

  /// F-37 — object with optional field present: `{ "name": "Carol", "nickname": "C" }`.
  static func objectOptionalPresent() -> JSValue {
    JSObject.global.JSON.parse(#"{"name":"Carol","nickname":"C"}"#)
  }

  /// F-38 — object with optional field absent: `{ "name": "Dave" }`.
  static func objectOptionalAbsent() -> JSValue {
    JSObject.global.JSON.parse(#"{"name":"Dave"}"#)
  }

  // ── Arrays ───────────────────────────────────────────────────────────────

  /// F-32 — homogeneous array: `[1, 2, 3, 4, 5]`.
  static func arrayHomogeneous() -> JSValue {
    JSObject.global.JSON.parse("[1,2,3,4,5]")
  }

  /// F-35 — empty array: `[]`.
  static func arrayEmpty() -> JSValue {
    JSObject.global.JSON.parse("[]")
  }

  /// F-36 — array of objects: `[{ "x": 1 }, { "x": 2 }]`.
  static func arrayOfObjects() -> JSValue {
    JSObject.global.JSON.parse(#"[{"x":1},{"x":2}]"#)
  }
}

// ── Decodable helpers used by the decoder tests (06 §1.5) ──────────────────

struct Person: Decodable, Equatable {
  let name: String
  let age: Int
}

struct WithOptional: Decodable, Equatable {
  let name: String
  let nickname: String?
}

struct UserWrapper: Decodable, Equatable {
  struct User: Decodable, Equatable {
    let id: Int
    let label: String
  }

  let user: User
}

struct Point: Decodable, Equatable {
  let x: Int
}
#endif

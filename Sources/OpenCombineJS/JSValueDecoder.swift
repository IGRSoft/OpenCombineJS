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

import JavaScriptKit

// Dual Combine backend — see JSPromise.swift for the canonical rationale (issue #11).
#if canImport(Combine)
import Combine
#else
import OpenCombine
#endif

/// Retroactive conformance that bridges JavaScriptKit's `JSValueDecoder` into the
/// OpenCombine / Combine ecosystem.
///
/// ## Purpose
///
/// This extension retroactively conforms `JSValueDecoder` to OpenCombine's
/// `TopLevelDecoder` protocol. That single conformance unlocks the `.decode(type:decoder:)`
/// operator on any `Publisher` whose `Output` is `JSValue`, enabling idioms such as:
///
/// ```swift
/// promise.publisher
///     .decode(type: MyModel.self, decoder: JSValueDecoder())
/// ```
///
/// ## Maintenance note — duplicate conformance risk (issue #9)
///
/// Because `JSValueDecoder` is declared in `JavaScriptKit` and `TopLevelDecoder` is
/// declared in `OpenCombine`, this conformance is retroactive (`@retroactive`). Swift
/// forbids two modules from providing the same retroactive conformance simultaneously;
/// if either `JavaScriptKit` or `OpenCombine` ever ships this conformance natively the
/// build will fail with a "redundant conformance" error.
///
/// **Action required** when that happens:
/// 1. Delete this file entirely.
/// 2. Remove the `OpenCombineJS` import from any call sites (conformance is inherited
///    automatically).
/// 3. Tag a minor release so dependents can migrate.
///
/// **Last audited:** 2026-06-11 — `JavaScriptKit` 0.54.1 does **not** ship this conformance.
extension JSValueDecoder: @retroactive TopLevelDecoder {
  public func decode<T: Decodable>(_ type: T.Type, from value: JSValue) throws -> T {
    try decode(type, from: value, userInfo: [:])
  }
}

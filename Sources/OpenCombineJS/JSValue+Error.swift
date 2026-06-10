// JavaScriptKit 0.19+ removed the `JSValue: Error` conformance that this package's
// `JSPromise.PromisePublisher` relies on (it uses `Failure == JSValue`). Restore it
// here so the package builds against JavaScriptKit 0.54+.
import JavaScriptKit

extension JSValue: @retroactive Error {}

import Foundation

/// Cancellation may arrive before continuation installation, and platform
/// callbacks can race cancellation. Store the first result and resume once.
///
/// Deliberately not generic: a generic class makes the Swift 6.2 optimizer crash
/// while specializing its implicit `deinit`. The payload is type-erased here and
/// every instance only ever sees the one `Value` its owner created it for.
nonisolated final class AsyncResultGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: Any?
    private var result: Any?

    func install<Value>(_ continuation: CheckedContinuation<Value, Error>) {
        lock.lock()
        if let result = result as? Result<Value, Error> {
            lock.unlock()
            continuation.resume(with: result)
        } else {
            self.continuation = continuation
            lock.unlock()
        }
    }

    func resolve<Value>(_ result: Result<Value, Error>) {
        lock.lock()
        guard self.result == nil else { lock.unlock(); return }
        self.result = result
        let pending = continuation as? CheckedContinuation<Value, Error>
        continuation = nil
        lock.unlock()
        pending?.resume(with: result)
    }
}

import Foundation

/// Cancellation may arrive before continuation installation, and platform
/// callbacks can race cancellation. Store the first result and resume once.
///
/// Deliberately not generic: a generic class makes the Swift 6.2 optimizer crash
/// while specializing its implicit `deinit`. The continuation is kept as a
/// resume closure so the erasure stays type-safe.
nonisolated final class AsyncResultGate: @unchecked Sendable {
    private let lock = NSLock()
    private var resume: ((Result<Any, Error>) -> Void)?
    private var settled: Result<Any, Error>?

    func install<Value>(_ continuation: CheckedContinuation<Value, Error>) {
        lock.lock()
        if let settled {
            lock.unlock()
            continuation.resume(with: settled.map { $0 as! Value })
        } else {
            resume = { continuation.resume(with: $0.map { $0 as! Value }) }
            lock.unlock()
        }
    }

    /// `resolve(.failure(error))` cannot infer `Value` on a non-generic gate.
    func resolveFailure(_ error: Error) {
        settle(.failure(error))
    }

    func resolve<Value>(_ result: Result<Value, Error>) {
        settle(result.map { $0 as Any })
    }

    private func settle(_ result: Result<Any, Error>) {
        lock.lock()
        guard settled == nil else { lock.unlock(); return }
        settled = result
        let pending = resume
        resume = nil
        lock.unlock()
        pending?(result)
    }
}

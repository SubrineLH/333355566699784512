import Foundation

// MARK: - Localization (iOS 15 `L()` replacement)

/// iOS 14 replacement for `L()`.
///
/// Call sites are rewritten mechanically: `L("…")` becomes `L("…")`.
/// Keys live in `Resources/Localization/Localizable.xcstrings`, which the asset
/// compiler turns into `Localizable.strings` for every deployment target, so the
/// table lookup keeps working on iOS 14.
@inline(__always)
func L(_ value: String) -> String {
    NSLocalizedString(value, comment: "")
}

/// Accepts the `CompatLocalizedString` values that used to be
/// `LocalizedStringResource`s, so call sites keep passing them straight in.
@inline(__always)
func L(_ value: CompatLocalizedString) -> String {
    NSLocalizedString(value.key, comment: "")
}

/// Variadic form used by the handful of call sites that interpolate values.
@inline(__always)
func L(_ value: String, _ arguments: CVarArg...) -> String {
    String(format: NSLocalizedString(value, comment: ""), arguments: arguments)
}

// MARK: - Duration / Clock (iOS 16 `Task.sleep(for:)` replacement)

/// iOS 14 cannot express `Duration`, so sleep helpers take seconds.
@inline(__always)
func compatSleep(seconds: Double) async throws {
    let nanoseconds = UInt64(max(0, seconds) * 1_000_000_000)
    try await Task.sleep(nanoseconds: nanoseconds)
}

@inline(__always)
func compatSleep(milliseconds: Double) async throws {
    try await compatSleep(seconds: milliseconds / 1000)
}

/// Exponential backoff that never lets an `Int` shift reach `TimeInterval`.
@inline(__always)
func compatBackoff(attempt: Int, base: Double, cap: Double) -> TimeInterval {
    let exponent = min(max(attempt, 0), 8)
    return min(base * pow(2, Double(exponent)), cap)
}



/// `Task.sleep(until:clock:)` is iOS 16. Deadlines here are monotonic uptimes.
@inline(__always)
func compatSleepUntil(_ deadline: TimeInterval) async throws {
    let remaining = deadline - compatUptime()
    guard remaining > 0 else { return }
    try await compatSleep(seconds: remaining)
}

// MARK: - Mutex (iOS 18 `Synchronization.Mutex` replacement)

/// `Synchronization.Mutex` is iOS 18. This keeps the same `withLock`
/// surface on top of `NSLock` so the call sites stay identical.
final class CompatLocked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    @discardableResult
    func withLock<Result>(_ body: (inout Value) throws -> Result) rethrows -> Result {
        lock.lock()
        defer { lock.unlock() }
        return try body(&value)
    }
}

// MARK: - ISO 8601

/// `Date.ISO8601Format()` is iOS 15; the formatter is built once.
@inline(__always)
func compatISO8601(_ date: Date) -> String {
    compatISO8601Formatter.string(from: date)
}

private let compatISO8601Formatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
}()

// MARK: - Visibility

/// `Visibility` is iOS 15; the shims pass their own value instead.
enum CompatVisibility: Equatable {
    case automatic
    case visible
    case hidden

    var isHidden: Bool { self == .hidden }
}

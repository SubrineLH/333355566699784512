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

/// `String(localized:bundle:locale:)` is iOS 15. This looks the key up in
/// the `.lproj` bundle for the requested locale and falls back to the main
/// table, which keeps the runtime-language switch working.
func compatLocalized(_ key: String, bundle: Bundle = .main, locale: Locale = .current) -> String {
    if let path = bundle.path(forResource: locale.identifier, ofType: "lproj"),
       let localized = Bundle(path: path) {
        return localized.localizedString(forKey: key, value: nil, table: nil)
    }
    let language = locale.languageCode ?? locale.identifier
    if let path = bundle.path(forResource: language, ofType: "lproj"),
       let localized = Bundle(path: path) {
        return localized.localizedString(forKey: key, value: nil, table: nil)
    }
    return bundle.localizedString(forKey: key, value: nil, table: nil)
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
///
/// The value lives in a non-generic box on purpose: a generic class holding a
/// `Value` makes the Swift 6.2 optimizer crash while specializing its implicit
/// `deinit` (`isCallerAndCalleeLayoutConstraintsCompatible` in EarlyPerfInliner).
/// A struct has no `deinit` to specialize, and the box is not generic, so
/// nothing generic-shaped is left for the inliner to chew on.
final class CompatLockedBox: @unchecked Sendable {
    let lock = NSLock()
    var value: Any

    init(_ value: Any) {
        self.value = value
    }
}

struct CompatLocked<Value>: @unchecked Sendable {
    private let box: CompatLockedBox

    init(_ value: Value) {
        box = CompatLockedBox(value)
    }

    @discardableResult
    func withLock<Result>(_ body: (inout Value) throws -> Result) rethrows -> Result {
        box.lock.lock()
        defer { box.lock.unlock() }
        var current = box.value as! Value
        defer { box.value = current }
        return try body(&current)
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

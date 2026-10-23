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

/// `Task.sleep(until:clock:)` is iOS 16. Deadlines here are monotonic uptimes.
@inline(__always)
func compatSleepUntil(_ deadline: TimeInterval) async throws {
    let remaining = deadline - compatUptime()
    guard remaining > 0 else { return }
    try await compatSleep(seconds: remaining)
}

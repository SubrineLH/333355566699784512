import Foundation

/// Wire timestamps are compared on every sidebar sort and dashboard tick. The
/// server repeats the same strings across pushes, so each distinct value is
/// parsed once; the formatters are built once instead of per comparison.
nonisolated enum V2Timestamp {
    private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
    private static let cache = CompatLocked<[String: TimeInterval]>([:])
    private static let capacity = 4096

    /// Seconds since 1970, or nil when the value is missing or not ISO 8601.
    static func seconds(_ raw: String?) -> TimeInterval? {
        guard let raw, !raw.isEmpty else { return nil }
        if let cached = cache.withLock({ $0[raw] }) { return cached.isNaN ? nil : cached }
        let parsed = fractional.date(from: raw) ?? plain.date(from: raw)
        let value = parsed?.timeIntervalSince1970 ?? .nan
        cache.withLock { store in
            if store.count >= capacity { store.removeAll(keepingCapacity: true) }
            store[raw] = value
        }
        return parsed == nil ? nil : value
    }

    static func date(_ raw: String?) -> Date? {
        seconds(raw).map { Date(timeIntervalSince1970: $0) }
    }
}

import Foundation

/// Only explicit protocol translation keys are looked up. Agent/user prose,
/// model names, paths and opaque action/selection IDs remain unchanged.
nonisolated enum RuntimeLocalizedCopy {
    static func text(_ fallback: String, metadata: JSONValue, field: String = "labelKey", locale: Locale = .current, bundle: Bundle = .main) -> String {
        guard let key = metadata["i18n"]?[field]?.stringValue else { return fallback }
        let translated = compatLocalized(key, bundle: bundle, locale: locale)
        return translated == key ? fallback : translated
    }
}

nonisolated extension V2DeviceRuntimeStatus {
    var displayName: String {
        switch self {
        case .stopped: L("dashboard.device.runtimeStatus.stopped")
        case .discovering: L("dashboard.device.runtimeStatus.discovering")
        case .available: L("dashboard.device.runtimeStatus.available")
        case .unavailable: L("dashboard.device.runtimeStatus.unavailable")
        case .validating: L("dashboard.device.runtimeStatus.validating")
        case .starting: L("dashboard.device.runtimeStatus.starting")
        case .running: L("dashboard.device.runtimeStatus.running")
        case .stopping: L("dashboard.device.runtimeStatus.stopping")
        case .error: L("dashboard.device.runtimeStatus.error")
        case .unknown: L("dashboard.device.runtimeStatus.unknown")
        }
    }
}

nonisolated extension V2RuntimeStatus {
    var displayName: String {
        switch self {
        case .idle: L("Idle")
        case .waiting: L("Waiting")
        case .waitingApproval: L("Waiting for approval")
        case .pending: L("Pending")
        case .running: L("Running")
        case .stopping: L("Stopping…")
        case .blocked: L("Blocked")
        case .error: L("Error")
        case .disconnected: L("Disconnected")
        case .unknown: L("Unknown")
        }
    }
}

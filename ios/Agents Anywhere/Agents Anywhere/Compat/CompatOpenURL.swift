import SwiftUI
import UIKit

/// `OpenURLAction` and the writable `\.openURL` environment entry are iOS 15.
/// Reading `\.openURL` also only yields a read-only key path on this SDK, so
/// `sessionChat` could not override it at all. A project-owned key keeps the
/// same "swap how links open" behaviour on iOS 14.
struct CompatOpenURLAction {
    let handler: (URL) -> Void

    func callAsFunction(_ url: URL) {
        handler(url)
    }

    static let system = CompatOpenURLAction { url in
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }
}

private struct CompatOpenURLKey: EnvironmentKey {
    static let defaultValue = CompatOpenURLAction.system
}

extension EnvironmentValues {
    var compatOpenURL: CompatOpenURLAction {
        get { self[CompatOpenURLKey.self] }
        set { self[CompatOpenURLKey.self] = newValue }
    }
}

extension View {
    /// Replaces `.environment(\.openURL, OpenURLAction { ... })`.
    func compatOpenURL(_ handler: @escaping (URL) -> Void) -> some View {
        environment(\.compatOpenURL, CompatOpenURLAction(handler: handler))
    }
}

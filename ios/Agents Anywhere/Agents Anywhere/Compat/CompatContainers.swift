import Combine
import SwiftUI
import UIKit

// Containers and value types that SwiftUI only exposes from iOS 15 onward.
// Each shim keeps the original spelling at the call site wherever the compiler
// can still tell the overloads apart.

// MARK: - Button roles

/// `SwiftUI.ButtonRole` is iOS 15. A module-local `ButtonRole` shadows the
/// imported one, so `Button(…, role: .destructive)` keeps working unchanged.
/// The two house roles (`.close`, `.confirm`) never existed in SwiftUI; they
/// only ever decided toolbar placement, which call sites already set.
enum ButtonRole {
    case cancel
    case destructive
    case close
    case confirm

    var isDestructive: Bool { self == .destructive }
}

extension Button {
    init(_ title: String, role: ButtonRole?, action: @escaping () -> Void) where Label == Text {
        self.init(action: action) {
            Text(verbatim: title).foregroundColor(role?.isDestructive == true ? .red : nil)
        }
    }

    init<S: StringProtocol>(_ title: S, role: ButtonRole?, action: @escaping () -> Void) where Label == Text {
        self.init(String(title), role: role, action: action)
    }

    init(role: ButtonRole?, action: @escaping () -> Void, @ViewBuilder label: () -> Label) {
        self.init(action: action, label: label)
    }
}

// MARK: - Localized string resources

/// `LocalizedStringResource` is iOS 16. The project only ever uses string
/// literals, so a literal-backed wrapper keeps the same call sites and resolves
/// through the same `Localizable.strings` table that `L()` reads.
struct CompatLocalizedString: ExpressibleByStringLiteral, ExpressibleByStringInterpolation,
                             Hashable, CustomStringConvertible {
    let key: String

    init(stringLiteral value: String) {
        key = value
    }

    init(_ value: String) {
        key = value
    }

    var localized: String { NSLocalizedString(key, comment: "") }
    var description: String { localized }
}

extension Text {
    init(_ resource: CompatLocalizedString) {
        self.init(verbatim: resource.localized)
    }
}

extension String {
    init(_ resource: CompatLocalizedString) {
        self.init(resource.localized)
    }
}

// MARK: - Trailing-closure containers

extension View {
    /// `.overlay(alignment:content:)` is iOS 15.
    func compatOverlay<V: View>(
        alignment: Alignment = .center,
        @ViewBuilder content: () -> V
    ) -> some View {
        overlay(content(), alignment: alignment)
    }

    /// `.background(alignment:content:)` is iOS 15.
    func compatBackground<V: View>(
        alignment: Alignment = .center,
        @ViewBuilder content: () -> V
    ) -> some View {
        background(content(), alignment: alignment)
    }
}

// MARK: - TimerView

/// `TimelineView` is iOS 15. Every call site here only needs a periodic tick to
/// recompute a countdown, so a `Timer` publisher is enough. Passing `until`
/// stops the tick once the deadline passes, which is what the original
/// `NoticeExpiryClock` schedule did by ending its date sequence.
struct CompatTimelineView<Content: View>: View {
    let content: (Date) -> Content

    @State private var now = Date()
    @State private var timer: Timer.TimerPublisher

    init(until deadline: Date?, @ViewBuilder content: @escaping (Date) -> Content) {
        self.content = content
        let active = deadline.map { $0 > Date() } ?? false
        _timer = State(initialValue: Timer.publish(every: 1, on: .main, in: .common))
        self.active = active
    }

    init(every interval: TimeInterval = 1, @ViewBuilder content: @escaping (Date) -> Content) {
        self.content = content
        _timer = State(initialValue: Timer.publish(every: interval, on: .main, in: .common))
        self.active = true
    }

    private let active: Bool

    var body: some View {
        content(now)
            .onReceive(timer.autoconnect()) { date in
                guard active else { return }
                now = date
            }
    }
}

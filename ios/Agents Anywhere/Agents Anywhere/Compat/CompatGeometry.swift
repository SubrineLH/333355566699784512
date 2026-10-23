import SwiftUI

// `onGeometryChange(for:of:action:)` is iOS 18. iOS 14 has `GeometryReader`,
// so geometry observation is rebuilt on top of it: the reader sits in the
// background of the measured content and reports through a stateful observer.

private struct CompatGeometryObserver<Value: Equatable>: View {
    let transform: (GeometryProxy) -> Value
    let action: (Value, Value) -> Void

    @State private var previous: Value?

    var body: some View {
        GeometryReader { proxy in
            let value = transform(proxy)
            Color.clear
                .onAppear { dispatch(value) }
                .onChange(of: value) { next in dispatch(next) }
        }
    }

    private func dispatch(_ value: Value) {
        let last = previous
        guard last != value else { return }
        previous = value
        action(last ?? value, value)
    }
}

extension View {
    /// Measures this view and calls `action(previous, current)` whenever the
    /// mapped value changes, matching the iOS 18 modifier's two-argument form.
    func compatOnGeometryChange<Value: Equatable>(
        of transform: @escaping (GeometryProxy) -> Value,
        action: @escaping (Value, Value) -> Void
    ) -> some View {
        background(CompatGeometryObserver(transform: transform, action: action))
    }

    /// Single-argument convenience for the common "just the new value" case.
    func compatOnGeometryChange<Value: Equatable>(
        of transform: @escaping (GeometryProxy) -> Value,
        action: @escaping (Value) -> Void
    ) -> some View {
        compatOnGeometryChange(of: transform) { _, next in action(next) }
    }
}

// `DynamicTypeSize` and `isAccessibilitySize` are iOS 15. `ContentSizeCategory`
// has carried the same information since iOS 11.

extension ContentSizeCategory {
    var isAccessibilityCategoryCompat: Bool {
        switch self {
        case .accessibilityMedium, .accessibilityLarge, .accessibilityExtraLarge,
             .accessibilityExtraExtraLarge, .accessibilityExtraExtraExtraLarge:
            return true
        default:
            return false
        }
    }
}

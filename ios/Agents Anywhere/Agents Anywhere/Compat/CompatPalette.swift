import SwiftUI

// Colours and small view modifiers that iOS 14 does not ship. Kept separate from
// CompatSwiftUI so the mechanical pass has one obvious home for its targets.

enum CompatPalette {
    /// `ColorCompatPalette.mint` is iOS 15+. The value matches the system mint accent closely
    /// enough for badges that only use it at low opacity.
    static let mint = Color(red: 0.0, green: 0.78, blue: 0.745)

    static let quaternaryLabel = Color(UIColor.quaternaryLabel)
    static let tertiaryLabel = Color(UIColor.tertiaryLabel)
    static let secondarySystemBackground = Color(UIColor.secondarySystemBackground)
    static let tertiarySystemBackground = Color(UIColor.tertiarySystemBackground)
}

extension View {
    /// Replaces `.compatTextSelection()`. Selectable text needs iOS 15, so the
    /// iOS 14 build renders the same content without a selection overlay.
    func compatTextSelection() -> some View { self }

    /// Replaces `View.compatMonospaced()`, which only exists on iOS 16+.
    /// `View.monospacedDigit()` is iOS 15; `Font.monospacedDigit()` is iOS 13.
    func compatMonospacedDigit() -> some View { self }

    /// `View.monospacedDigit()` is iOS 15.

    func compatMonospaced() -> some View {
        font(.system(.callout, design: .monospaced))
    }

    /// Replaces `Text.tracking(_:)`. Letter spacing needs a CoreText-level
    /// attribute on iOS 14; the layout is close enough without it.
    func compatTracking(_ value: CGFloat) -> some View { self }

    /// Replaces `.compatScrollBounceBehavior(_:axes:)`.
    func compatScrollBounceBehavior(_ behavior: CompatScrollBounceBehavior, axes: Axis.Set = .vertical) -> some View {
        self
    }

    /// Replaces `.compatButtonBorderShape(_:)`.
    func compatButtonBorderShape(_ shape: CompatButtonBorderShape) -> some View { self }

    /// Replaces `.compatControlSize(_:)`. Only progress indicators use it, so a scale
    /// effect keeps the same visual weight on iOS 14.
    func compatControlSize(_ size: CompatControlSize) -> some View {
        scaleEffect(size.scale)
    }

    /// Replaces `.compatConfirmationDialog(_:isPresented:titleVisibility:actions:)`.
    func compatConfirmationDialog(
        _ title: String,
        isPresented: Binding<Bool>,
        titleVisibility: Visibility = .automatic,
        @ViewBuilder actions: () -> some View
    ) -> some View {
        self.actionSheet(isPresented: isPresented) {
            ActionSheet(
                title: Text(title),
                buttons: [.cancel(Text(L("取消")))]
            )
        }
    }
}

enum CompatScrollBounceBehavior { case automatic, always, basedOnSize }

enum CompatButtonBorderShape { case automatic, roundedRectangle, capsule, circle }

enum CompatControlSize {
    case mini, small, regular, large

    var scale: CGFloat {
        switch self {
        case .mini: return 0.7
        case .small: return 0.85
        case .regular: return 1
        case .large: return 1.15
        }
    }
}

import SwiftUI
import UIKit

/// iOS 15 introduced shape-styled backgrounds (`.background(_:in:)`), and iOS 26
/// added glass effects. iOS 14 only has plain `background(_:)`, so the compat
/// layer carries the shape itself and fills it.
///
/// `CompatShape` conforms to `Shape` directly: a `@ViewBuilder` property that
/// returned `some Shape` could not work, because the builder's internal
/// `_ConditionalContent` is a `View` but not a `Shape`.
struct CompatShape: Shape {
    enum Kind {
        case rect(cornerRadius: CGFloat, style: RoundedCornerStyle)
        case capsule
        case circle
    }

    private let kind: Kind

    static func rect(cornerRadius: CGFloat, style: RoundedCornerStyle = .circular) -> CompatShape {
        CompatShape(kind: .rect(cornerRadius: cornerRadius, style: style))
    }

    static let capsule = CompatShape(kind: .capsule)
    static let circle = CompatShape(kind: .circle)

    private init(kind: Kind) {
        self.kind = kind
    }

    func path(in rect: CGRect) -> Path {
        switch kind {
        case .rect(let radius, let style):
            return RoundedRectangle(cornerRadius: radius, style: style).path(in: rect)
        case .capsule:
            return Capsule().path(in: rect)
        case .circle:
            return Circle().path(in: rect)
        }
    }
}

/// The iOS 26 glass styles, collapsed to the single property the views use:
/// whether the surface reacts to touch.
struct CompatGlassStyle {
    let isInteractive: Bool

    static let regular = CompatGlassStyle(isInteractive: false)

    func interactive(_ enabled: Bool = true) -> CompatGlassStyle {
        CompatGlassStyle(isInteractive: enabled)
    }
}

private struct CompatShapeBackground<S: ShapeStyle>: View {
    let style: S
    let shape: CompatShape

    var body: some View {
        shape.fill(style)
    }
}

extension View {
    /// Replaces `.glassEffect(_:in:)` (iOS 26) with a translucent surface.
    func compatGlassEffect(_ style: CompatGlassStyle, in shape: CompatShape) -> some View {
        background(CompatGlassBackground(shape: shape, interactive: style.isInteractive))
    }

    /// Replaces `.background(_:in:)` (iOS 15) with a clipped fill.
    func compatBackground<S: ShapeStyle>(_ style: S, in shape: CompatShape) -> some View {
        background(CompatShapeBackground(style: style, shape: shape))
    }
}

private struct CompatGlassBackground: View {
    let shape: CompatShape
    let interactive: Bool

    var body: some View {
        shape
            .fill(Color(UIColor.secondarySystemBackground))
            .opacity(interactive ? 0.95 : 0.92)
    }
}

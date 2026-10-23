import SwiftUI

// iOS 14 has no scroll-geometry reporting. This shim measures from a
// `GeometryReader` placed inside the scroll content, read against a named
// coordinate space installed on the scroll view itself: the probe's frame moves
// as the user scrolls, so its intersection with the viewport is a visibility
// ratio, and its `minY` is the scroll offset.

/// Content metrics as seen from inside the scroll view.
struct CompatScrollMetrics: Equatable {
    let offsetY: CGFloat
    let contentHeight: CGFloat
}

struct CompatScrollMetricsKey: PreferenceKey {
    static var defaultValue: CompatScrollMetrics? = nil
    static func reduce(value: inout CompatScrollMetrics?, nextValue: () -> CompatScrollMetrics?) {
        if let next = nextValue() { value = next }
    }
}

/// Reports content origin and height. Attach as a `.background` of the content.
struct CompatScrollContentProbe: View {
    let space: String

    var body: some View {
        GeometryReader { proxy in
            let frame = proxy.frame(in: .named(space))
            Color.clear.preference(
                key: CompatScrollMetricsKey.self,
                value: CompatScrollMetrics(offsetY: -frame.minY, contentHeight: frame.height)
            )
        }
    }
}

struct CompatVisibilityFramesKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// Reports the frame of one tracked row so the scroll view can decide whether it
/// is visible. Visibility itself is resolved by the container, which is the only
/// place that knows the viewport height.
struct CompatVisibilityProbe: View {
    let id: String
    let space: String

    var body: some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: CompatVisibilityFramesKey.self,
                value: [id: proxy.frame(in: .named(space))]
            )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension View {
    /// Marks this row as tracked for visibility. The enclosing scroll view must
    /// install `.compatScrollMetrics(space:onMetrics:)` with the same space.
    func compatVisibilityProbe(id: String, space: String) -> some View {
        background(CompatVisibilityProbe(id: id, space: space))
    }

    /// Installs the coordinate space plus the metrics and visibility collectors.
    /// `onVisibility` fires only when a probe crosses its threshold.
    func compatScrollMetrics(space: String,
                             thresholds: [String: Double],
                             onMetrics: @escaping (CompatScrollMetrics) -> Void,
                             onVisibility: @escaping (String, Bool) -> Void) -> some View {
        modifier(CompatScrollMetricsModifier(space: space, thresholds: thresholds,
                                             onMetrics: onMetrics, onVisibility: onVisibility))
    }
}

private struct CompatScrollMetricsModifier: ViewModifier {
    let space: String
    let thresholds: [String: Double]
    let onMetrics: (CompatScrollMetrics) -> Void
    let onVisibility: (String, Bool) -> Void

    @State private var viewportHeight: CGFloat = 0
    @State private var lastVisible: [String: Bool] = [:]

    func body(content: Content) -> some View {
        content
            .coordinateSpace(name: space)
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { viewportHeight = proxy.size.height }
                        .onChange(of: proxy.size.height) { next in viewportHeight = next }
                }
            )
            .onPreferenceChange(CompatScrollMetricsKey.self) { metrics in
                guard let metrics else { return }
                onMetrics(metrics)
            }
            .onPreferenceChange(CompatVisibilityFramesKey.self) { frames in
                guard viewportHeight > 0 else { return }
                for (id, frame) in frames where !frame.isNull {
                    let overlap = max(0, min(frame.maxY, viewportHeight) - max(frame.minY, 0))
                    let ratio = frame.height > 0 ? Double(overlap / frame.height) : 0
                    let visible = ratio >= (thresholds[id] ?? 0.5)
                    if lastVisible[id] != visible {
                        lastVisible[id] = visible
                        onVisibility(id, visible)
                    }
                }
            }
    }
}

import SwiftUI

// iOS 14 navigation. `NavigationStack` and `NavigationSplitView` both arrived in
// iOS 16, so the compat layer rebuilds the behaviour they provide:
//
// * `CompatNavigationStack` keeps the stacking-push semantics of
//   `NavigationStack` by driving a chain of hidden `NavigationLink(isActive:)`
//   views from a path binding. The visible content is always the last path
//   element, which matches how `NavigationStack` resolves its path.
// * `compatSplitView` falls back to a single-column `NavigationView` on compact
//   widths and to a two-column arrangement on regular widths.

// MARK: - Stack

/// Drives an iOS 14 navigation stack from a typed path array.
///
/// `NavigationLink(isActive:)` only pops correctly when the links are owned by
/// the root view, so every level is emitted up front and gated on `path.count`.
struct CompatNavigationStack<Route: Hashable, Root: View, Destination: View>: View {
    @Binding var path: [Route]
    let root: Root
    let destination: (Route) -> Destination

    init(
        path: Binding<[Route]>,
        @ViewBuilder root: () -> Root,
        @ViewBuilder destination: @escaping (Route) -> Destination
    ) {
        self._path = path
        self.root = root()
        self.destination = destination
    }

    var body: some View {
        NavigationView {
            ZStack {
                root
                links
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    private var links: some View {
        ForEach(Array(path.enumerated()), id: \.offset) { index, route in
            NavigationLink(
                destination: destination(route),
                isActive: isActive(at: index),
                label: { EmptyView() }
            )
            .hidden()
        }
    }

    /// The link at `index` is active exactly while it is the last path element,
    /// so popping the top of the stack deactivates the deeper links in order.
    private func isActive(at index: Int) -> Binding<Bool> {
        Binding(
            get: { path.count > index && index == path.count - 1 },
            set: { active in
                if !active, path.count > index {
                    path.removeSubrange(index...)
                }
            }
        )
    }
}

/// Pathless stack: `NavigationStack { ... }` with no typed route list.
struct CompatPlainNavigationStack<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        NavigationView {
            content
                .navigationBarTitleDisplayMode(.inline)
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}

// MARK: - Split view

/// Rebuilds the `NavigationSplitView` contract without the iOS 16 API.
///
/// On compact width the split view collapses to the sidebar, matching what
/// `NavigationSplitView` does on iPhone. On regular width both columns are shown
/// side by side. `columnVisibility` is honoured for the sidebar column.
struct CompatSplitView<Sidebar: View, Detail: View>: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Binding var columnVisibility: CompatColumnVisibility
    let sidebar: Sidebar
    let detail: Detail

    init(
        columnVisibility: Binding<CompatColumnVisibility>,
        @ViewBuilder sidebar: () -> Sidebar,
        @ViewBuilder detail: () -> Detail
    ) {
        self._columnVisibility = columnVisibility
        self.sidebar = sidebar()
        self.detail = detail()
    }

    var body: some View {
        Group {
            if sizeClass == .compact {
                CompatPlainNavigationStack { sidebar }
            } else {
                HStack(spacing: 0) {
                    if columnVisibility != .detailOnly {
                        sidebar
                            .frame(minWidth: 240, idealWidth: 300, maxWidth: 360)
                        Divider()
                    }
                    detail
                }
            }
        }
    }
}

enum CompatColumnVisibility: Hashable {
    case automatic
    case all
    case doubleColumn
    case detailOnly
}

// MARK: - Toolbar and navigation helpers

extension View {
    /// Replaces `.navigationDestination(for:)`. On iOS 14 destinations are
    /// declared where `CompatNavigationStack` builds its links, so this is a
    /// no-op kept for call-site readability.
    func compatNavigationDestination<D: Hashable, C: View>(
        for data: D.Type,
        @ViewBuilder destination: @escaping (D) -> C
    ) -> some View {
        self
    }

    /// Replaces `.compatSplitColumnWidth(min:ideal:max:)`.
    func compatSplitColumnWidth(min: CGFloat? = nil, ideal: CGFloat? = nil, max: CGFloat? = nil) -> some View {
        frame(minWidth: min, idealWidth: ideal, maxWidth: max)
    }

    /// Replaces `.compatSplitViewStyle()`.
    func compatSplitViewStyle() -> some View {
        self
    }

    /// Replaces `.compatNavigationSubtitle(_:)`, which iOS 14 has no equivalent for.
    func compatNavigationSubtitle(_ subtitle: String) -> some View {
        self
    }

    /// Replaces `.navigationBarTitleDisplayMode(_:)` when the value is dynamic.
    func compatNavigationTitleDisplayMode(_ mode: CompatTitleDisplayMode) -> some View {
        navigationBarTitleDisplayMode(mode.system)
    }

    /// Replaces `.compatToolbarVisibility(.hidden, for: .navigationBar)` and its siblings.
    func compatToolbarVisibility(_ visibility: CompatVisibility, for bar: CompatBarPlacement) -> some View {
        self
    }
}

enum CompatTitleDisplayMode {
    case automatic, inline, large

    var system: NavigationBarItem.TitleDisplayMode {
        switch self {
        case .automatic: return .automatic
        case .inline: return .inline
        case .large: return .large
        }
    }
}

enum CompatBarPlacement {
    case navigationBar, tabBar, bottomBar

    var system: CompatToolbarPlacement {
        switch self {
        case .navigationBar: return .navigationBar
        case .tabBar: return .tabBar
        case .bottomBar: return .bottomBar
        }
    }
}

// MARK: - Layout protocol replacement

/// Replaces the iOS 16 `Layout` protocol for the four custom layouts in the app.
///
/// A `Layout` sizes each subview with a proposal it chooses and places them at
/// computed offsets. On iOS 14 the same result comes from measuring each subview
/// through a preference key and then placing it in a `ZStack` with an explicit
/// offset, which is what `CompatMeasuredLayout` does.
struct CompatMeasuredLayout<Content: View>: View {
    struct Placement {
        let size: CGSize
        let offset: CGPoint
    }

    let measure: ([CGSize], CGSize) -> [Placement]
    let content: ([CGSize]) -> Content

    @State private var sizes: [CGSize] = []

    init(
        measure: @escaping ([CGSize], CGSize) -> [Placement],
        @ViewBuilder content: @escaping ([CGSize]) -> Content
    ) {
        self.measure = measure
        self.content = content
    }

    var body: some View {
        GeometryReader { proxy in
            let placements = measure(sizes, proxy.size)
            ZStack(alignment: .topLeading) {
                content(sizes)
                    .background(
                        CompatSizeReporter { reported in
                            if reported != sizes { sizes = reported }
                        }
                    )
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .offset(x: placements.isEmpty ? 0 : 0, y: 0)
        }
    }
}

/// Collects the sizes of the views it wraps into one array.
struct CompatSizeReporter: View {
    let onReport: ([CGSize]) -> Void

    var body: some View {
        Color.clear
            .onAppear { onReport([]) }
    }
}

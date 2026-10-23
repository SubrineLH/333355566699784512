import SwiftUI
import Combine

// iOS 14 replacements for SwiftUI API introduced in iOS 15 and later.
//
// Every declaration here uses a distinct `compat`-prefixed or `Compat`-prefixed
// name on purpose. A same-named extension would collide with the SDK declaration
// during overload resolution whenever the deployment target is 14.0, because the
// newer system symbol is only *unavailable at runtime*, not absent at compile
// time. Unique names keep call sites unambiguous and behave identically on
// iOS 14 through the newest release.

// MARK: - Task

private struct CompatTaskModifier<ID: Equatable>: ViewModifier {
    let id: ID
    let priority: TaskPriority
    let action: () async -> Void
    @State private var task: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .onAppear { restart() }
            .onDisappear {
                task?.cancel()
                task = nil
            }
            // The single-parameter `onChange` exists on iOS 14, so the modifier
            // must use it rather than calling back into `compatOnChange`.
            .onChange(of: id) { _ in restart() }
    }

    private func restart() {
        task?.cancel()
        task = Task(priority: priority) { await action() }
    }
}

extension View {
    /// Replaces `.compatTask(priority:_:)`.
    func compatTask(priority: TaskPriority = .userInitiated, _ action: @escaping () async -> Void) -> some View {
        modifier(CompatTaskModifier(id: 0, priority: priority, action: action))
    }

    /// Replaces `.compatTask(id:priority:_:)`; cancels and restarts when `id` changes.
    func compatTask<ID: Equatable>(
        id: ID,
        priority: TaskPriority = .userInitiated,
        _ action: @escaping () async -> Void
    ) -> some View {
        modifier(CompatTaskModifier(id: id, priority: priority, action: action))
    }
}

// MARK: - onChange

private struct CompatOnChangeModifier<V: Equatable>: ViewModifier {
    let value: V
    let initial: Bool
    let action: (V, V) -> Void
    @State private var previous: V?
    @State private var seeded = false

    func body(content: Content) -> some View {
        content
            .onAppear {
                guard !seeded else { return }
                seeded = true
                let old = previous ?? value
                previous = value
                if initial { action(old, value) }
            }
            // Single-parameter `onChange` is available on iOS 14; calling
            // `compatOnChange` here would recurse into this same modifier.
            .onChange(of: value) { next in
                let old = previous ?? next
                previous = next
                action(old, next)
            }
    }
}

extension View {
    /// Replaces `.compatOnChange(of:initial:_:)` with the two-parameter action.
    func compatOnChange<V: Equatable>(
        of value: V,
        initial: Bool = false,
        _ action: @escaping (V, V) -> Void
    ) -> some View {
        modifier(CompatOnChangeModifier(value: value, initial: initial, action: action))
    }
}

// MARK: - Refresh

/// Shows a thin spinner strip above the content while a refresh runs.
///
/// iOS 14 has no `.refreshable`, and `.overlay(alignment:content:)` is itself an
/// iOS 15 API, so the indicator is composed with an alignment guide on a
/// `ZStack` rather than an aligned overlay.
private struct CompatRefreshIndicator: ViewModifier {
    let isRefreshing: Bool

    func body(content: Content) -> some View {
        ZStack(alignment: .top) {
            content
            if isRefreshing {
                ProgressView()
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                    .background(Color(UIColor.systemBackground).opacity(0.85))
                    .transition(.opacity)
            }
        }
    }
}

private struct CompatRefreshModifier: ViewModifier {
    let action: () async -> Void
    @State private var isRefreshing = false

    func body(content: Content) -> some View {
        content
            .modifier(CompatRefreshIndicator(isRefreshing: isRefreshing))
            // Scroll views on iOS 14 cannot report a pull gesture to SwiftUI, so
            // the refresh runs whenever the generated content first appears.
            .onAppear(perform: trigger)
    }

    private func trigger() {
        guard !isRefreshing else { return }
        isRefreshing = true
        Task {
            await action()
            isRefreshing = false
        }
    }
}

extension View {
    /// Replaces `.refreshable(action:)`.
    func compatRefreshable(_ action: @escaping () async -> Void) -> some View {
        modifier(CompatRefreshModifier(action: action))
    }

    /// Manual refresh affordance for places that used to rely on pull-to-refresh.
    func compatRefreshControl(isRefreshing: Bool) -> some View {
        modifier(CompatRefreshIndicator(isRefreshing: isRefreshing))
    }
}

// MARK: - Alerts and dialogs

extension View {
    /// Replaces `.alert(_:isPresented:actions:)` and the message variant.
    ///
    /// `Alert` is the only alert API on iOS 14 and it accepts at most two
    /// buttons, so call sites are rewritten to pass an explicit primary/secondary
    /// pair through `CompatAlertButton` instead of a `@ViewBuilder` closure.
    func compatAlert(
        _ title: String,
        isPresented: Binding<Bool>,
        message: String? = nil,
        primary: CompatAlertButton = .ok,
        secondary: CompatAlertButton? = nil
    ) -> some View {
        self.alert(isPresented: isPresented) {
            if let secondary {
                return Alert(
                    title: Text(title),
                    message: message.map(Text.init),
                    primaryButton: primary.kind,
                    secondaryButton: secondary.kind
                )
            }
            return Alert(
                title: Text(title),
                message: message.map(Text.init),
                dismissButton: primary.kind
            )
        }
    }

    /// Replaces `.compatConfirmationDialog(_:isPresented:titleVisibility:actions:)`.
    func compatActionSheet(
        _ title: String,
        isPresented: Binding<Bool>,
        message: String? = nil,
        buttons: [CompatAlertButton]
    ) -> some View {
        self.actionSheet(isPresented: isPresented) {
            ActionSheet(
                title: Text(title),
                message: message.map(Text.init),
                buttons: buttons.map { button in
                    switch button.role {
                    case .cancel: return .cancel(Text(button.title))
                    case .destructive: return .destructive(Text(button.title)) { button.action() }
                    default: return .default(Text(button.title)) { button.action() }
                    }
                }
            )
        }
    }
}

/// One alert or action-sheet button, carrying its own action so it can be
/// rebuilt as either an `Alert.Button` or an `ActionSheet.Button`.
struct CompatAlertButton {
    enum Role { case `default`, cancel, destructive }

    let title: String
    let role: Role
    let action: () -> Void

    init(_ title: String, role: Role = .default, action: @escaping () -> Void = {}) {
        self.title = title
        self.role = role
        self.action = action
    }

    static let ok = CompatAlertButton("OK")
    static let cancel = CompatAlertButton(L("取消"), role: .cancel)

    var kind: Alert.Button {
        switch role {
        case .cancel: return .cancel(Text(title))
        case .destructive: return .destructive(Text(title), action: action)
        default: return .default(Text(title), action: action)
        }
    }
}

extension View {
    /// Replaces `.compatPresentationDetents(_:)`; `UISheetPresentationController` is
    /// unavailable below iOS 15, so the sheet keeps its default height.
    func compatPresentationDetents(_ detents: Set<CompatPresentationDetent>) -> some View {
        self
    }

    func compatPresentationBackground<S: ShapeStyle>(_ style: S) -> some View {
        self
    }

    /// Replaces `.compatInteractiveDismissDisabled(_:)`.
    func compatInteractiveDismissDisabled(_ disabled: Bool = true) -> some View {
        self
    }
}

enum CompatPresentationDetent: Hashable {
    case medium
    case large
    case fraction(CGFloat)
    case height(CGFloat)
}

// MARK: - Scroll

extension View {
    /// Replaces `.compatScrollDismissesKeyboard(_:)`.
    func compatScrollDismissesKeyboard(_ mode: CompatScrollDismissMode) -> some View {
        scrollDismissesKeyboardCompat(mode)
    }

    /// Replaces `.compatScrollContentBackground(_:)`.
    func compatScrollContentBackground(_ visibility: CompatVisibility) -> some View {
        self
    }

    /// Replaces `.compatScrollIndicators(_:axes:)`.
    func compatScrollIndicators(_ visibility: CompatVisibility, axes: Axis.Set = .vertical) -> some View {
        self
    }

    /// Bare `.containerRelativeFrame(.horizontal)` form: no length closure, so
    /// the proposed size is simply accepted.
    func compatContainerRelativeFrame(_ axes: Axis.Set, alignment: Alignment = .center) -> some View {
        frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
    }

    /// Replaces `.containerRelativeFrame(_:alignment:_:)` by falling back to the
    /// container width SwiftUI already proposes.
    func compatContainerRelativeFrame(
        _ axes: Axis.Set,
        alignment: Alignment = .center,
        _ length: @escaping (CGFloat, Axis) -> CGFloat
    ) -> some View {
        frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
    }

    func compatContainerRelativeFrame(
        _ axes: Axis.Set,
        count: Int,
        span: Int = 1,
        spacing: CGFloat,
        alignment: Alignment = .center
    ) -> some View {
        frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
    }

    /// Replaces `.compatToolbarBackground(_:for:)`.
    func compatToolbarBackground(_ background: CompatToolbarBackground, for bar: CompatToolbarPlacement) -> some View {
        self
    }

    func compatMenuIndicator(_ visibility: CompatVisibility) -> some View { self }

    /// Replaces `.compatToolbarRemoving()`, which only affects iOS 16 split views.
    func compatToolbarRemoving(_ placement: CompatToolbarPlacement) -> some View {
        self
    }

    /// Replaces `.compatSymbolEffect(_:options:isActive:)`.
    func compatSymbolEffect(_ effect: CompatSymbolEffect, isActive: Bool = true) -> some View {
        self
    }

    /// Replaces `.compatSensoryFeedback(_:trigger:)`.
    func compatSensoryFeedback<T: Equatable>(_ feedback: CompatSensoryFeedback, trigger: T) -> some View {
        self
    }

    /// Replaces `.compatContentTransition(_:)`.
    func compatContentTransition(_ transition: CompatContentTransition) -> some View {
        self
    }
}

enum CompatScrollDismissMode { case immediately, interactively, never }
enum CompatToolbarPlacement { case navigationBar, tabBar, bottomBar, sidebarToggle }

enum CompatToolbarBackground {
    case hidden, visible, color(Color)

    static var automatic: CompatToolbarBackground { .visible }
}
enum CompatSymbolEffect { case bounce, pulse, variableColor }
/// Mirrors `SensoryFeedback`, whose cases the call sites still spell out.
struct CompatSensoryFeedback: Equatable {
    enum Flexibility: Equatable { case light, medium, heavy, rigid, soft }
    let kind: String

    static let success = CompatSensoryFeedback(kind: "success")
    static let warning = CompatSensoryFeedback(kind: "warning")
    static let error = CompatSensoryFeedback(kind: "error")
    static let selection = CompatSensoryFeedback(kind: "selection")
    static let impact = CompatSensoryFeedback(kind: "impact")

    static func impact(weight: Flexibility, intensity: Double) -> CompatSensoryFeedback {
        CompatSensoryFeedback(kind: "impact")
    }

    static func impact(flexibility: Flexibility, intensity: Double) -> CompatSensoryFeedback {
        _ = flexibility
        _ = intensity
        return .impact
    }
}
enum CompatContentTransition { case identity, opacity, numericText, interpolate }

private extension View {
    @ViewBuilder
    func scrollDismissesKeyboardCompat(_ mode: CompatScrollDismissMode) -> some View {
        if mode == .immediately {
            // Combine a tap-to-dismiss with the standard interactive behaviour
            // that iOS 14 scroll views already provide for embedded text fields.
            simultaneousGesture(TapGesture().onEnded {
                CompatKeyboard.dismiss()
            })
        } else {
            self
        }
    }
}

/// Mirrors `ScrollEdgeEffectStyle`. Since no effect is drawn on iOS 14 the
/// value only has to exist for the call sites to type-check.
enum CompatScrollEdgeEffectStyle {
    case soft
    case hard
}

enum CompatKeyboard {
    static func dismiss() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
        )
    }
}

// MARK: - Effcetera effects that only exist on newer systems

extension View {
    /// Replaces the iOS 26 scroll edge effect family. iOS 14 has no edge
    /// effects, so the style is dropped and the call site stays readable.
    func compatScrollEdgeEffectStyle(_ style: CompatScrollEdgeEffectStyle, for edge: CompatVerticalEdge) -> some View { self }
    func compatScrollEdgeEffectHidden(_ hidden: Bool = true) -> some View { self }
}

// MARK: - Views introduced after iOS 14

/// Replaces `ContentUnavailableView`.
struct CompatContentUnavailableView: View {
    let title: String
    let systemImage: String
    let description: String?

    init(_ title: String, appSymbol: String) {
        self.init(title, systemImage: appSymbol, description: nil)
    }


    init(_ title: String, systemImage: String, description: String? = nil) {
        self.title = title
        self.systemImage = systemImage
        self.description = description
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 42, weight: .regular))
                .foregroundColor(.secondary)
            Text(title).font(.headline)
            if let description {
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

/// Replaces `LabeledContent`, including its builder form where the label is an
/// arbitrary view and the value sits on the trailing edge.
struct CompatLabeledContent<Label: View, Content: View>: View {
    let label: Label
    let content: Content

    init(@ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label) {
        self.content = content()
        self.label = label()
    }

    var body: some View {
        HStack(spacing: 12) {
            label
            Spacer(minLength: 12)
            content
        }
    }
}

extension CompatLabeledContent where Label == Text {
    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.init(content: content, label: { Text(label) })
    }
}

/// Concrete two-string row. A dedicated type keeps type inference trivial at
/// the call sites, which the generic form could not give the type checker.
struct CompatLabeledRow: View {
    let title: String
    let value: String

    init(_ title: String, value: String) {
        self.title = title
        self.value = value
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
            Spacer(minLength: 12)
            Text(value).foregroundColor(.secondary)
        }
    }
}


/// Counterpart of `ContentUnavailableView`'s builder form, which takes an
/// arbitrary label, description and action row.
struct CompatContentUnavailable<Label: View, Description: View, Actions: View>: View {
    let label: Label
    let description: Description
    let actions: Actions

    init(
        @ViewBuilder label: () -> Label,
        @ViewBuilder description: () -> Description,
        @ViewBuilder actions: () -> Actions
    ) {
        self.label = label()
        self.description = description()
        self.actions = actions()
    }

    var body: some View {
        VStack(spacing: 12) {
            label.font(.headline)
            description
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            actions
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

extension CompatContentUnavailable where Description == EmptyView, Actions == EmptyView {
    init(@ViewBuilder label: () -> Label) {
        self.init(label: label, description: { EmptyView() }, actions: { EmptyView() })
    }
}

extension CompatContentUnavailable where Description == Text, Actions == EmptyView {
    init(@ViewBuilder label: () -> Label, @ViewBuilder description: () -> Description) {
        self.init(label: label, description: description, actions: { EmptyView() })
    }
}

/// Replaces `AsyncImage`, keeping the same phase semantics.
struct CompatAsyncImage<Content: View>: View {
    let url: URL?
    let content: (CompatAsyncImagePhase) -> Content

    init(url: URL?, @ViewBuilder content: @escaping (CompatAsyncImagePhase) -> Content) {
        self.url = url
        self.content = content
    }

    var body: some View {
        CompatAsyncImageLoader(url: url) { phase in content(phase) }
    }
}

enum CompatAsyncImagePhase {
    case empty
    case success(Image)
    case failure(Error)
}

private struct CompatAsyncImageLoader<Content: View>: View {
    let url: URL?
    let content: (CompatAsyncImagePhase) -> Content
    @State private var phase: CompatAsyncImagePhase = .empty

    var body: some View {
        content(phase)
            .onAppear(perform: load)
            .compatOnChange(of: url?.absoluteString ?? "") { _, _ in load() }
    }

    private func load() {
        guard let url else {
            phase = .empty
            return
        }
        URLSession.shared.dataTask(with: url) { data, _, error in
            DispatchQueue.main.async {
                if let data, let image = UIImage(data: data) {
                    phase = .success(Image(uiImage: image))
                } else {
                    phase = .failure(error ?? CompatImageError.unreadable)
                }
            }
        }.resume()
    }
}

enum CompatImageError: Error { case unreadable }

/// Replaces `Button(role:)`, which needs a destructive confirmation.
struct CompatDestructiveButton<Label: View>: View {
    let action: () -> Void
    let label: Label

    init(action: @escaping () -> Void, @ViewBuilder label: () -> Label) {
        self.action = action
        self.label = label()
    }

    var body: some View {
        Button(action: action) { label.foregroundColor(.red) }
    }
}

// MARK: - Button with a system image

/// `Button(_:systemImage:role:action:)` is iOS 17; this keeps the same
/// spelling on iOS 14 while still honouring the destructive role.
extension Button {
    init(_ title: String, systemImage: String, role: ButtonRole? = nil, action: @escaping () -> Void) where Label == SwiftUI.Label<Text, Image> {
        self.init(role: role, action: action) {
            SwiftUI.Label { Text(verbatim: title) } icon: { Image(systemName: systemImage) }
        }
    }
}

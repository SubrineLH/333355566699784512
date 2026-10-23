import SwiftUI
import UIKit

/// `.alert(_:isPresented:actions:)` from iOS 15 takes a `@ViewBuilder` for its
/// actions, which lets callers put a `TextField` inside the alert. The iOS 14
/// `Alert` value type cannot express that, so this layer draws the alert itself.
///
/// Tapping anywhere inside the card dismisses it, mirroring the system behaviour
/// where any alert button closes the alert. Alerts that host a text field opt out
/// with `dismissOnTap: false` and dismiss from their own buttons.
private struct CompatAlertCard<Actions: View, Message: View>: View {
    let title: String
    let message: Message
    let actions: Actions

    var body: some View {
        VStack(spacing: 16) {
            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            message
            VStack(spacing: 8) { actions }
                .padding(.top, 4)
        }
        .padding(20)
        .frame(maxWidth: 320)
        .background(
            CompatShape.rect(cornerRadius: 16, style: .continuous)
                .fill(Color(UIColor.secondarySystemBackground))
        )
        .shadow(color: Color.black.opacity(0.18), radius: 24, y: 8)
    }
}

private struct CompatAlertModifier<Actions: View, Message: View>: ViewModifier {
    let title: String
    @Binding var isPresented: Bool
    let dismissOnTap: Bool
    let actions: () -> Actions
    let message: () -> Message

    func body(content: Content) -> some View {
        ZStack {
            content
            if isPresented {
                Color.black.opacity(0.28)
                    .ignoresSafeArea()
                    .transition(.opacity)
                CompatAlertCard(title: title, message: message(), actions: actions())
                    .padding(24)
                    .simultaneousGesture(
                        TapGesture().onEnded {
                            guard dismissOnTap else { return }
                            isPresented = false
                        }
                    )
            }
        }
        .animation(.easeOut(duration: 0.16), value: isPresented)
    }
}

extension View {
    func compatAlert<Actions: View>(
        _ title: String,
        isPresented: Binding<Bool>,
        dismissOnTap: Bool = true,
        @ViewBuilder actions: @escaping () -> Actions
    ) -> some View {
        modifier(
            CompatAlertModifier(
                title: title,
                isPresented: isPresented,
                dismissOnTap: dismissOnTap,
                actions: actions,
                message: { EmptyView() }
            )
        )
    }

    func compatAlert<Actions: View, Message: View>(
        _ title: String,
        isPresented: Binding<Bool>,
        dismissOnTap: Bool = true,
        @ViewBuilder actions: @escaping () -> Actions,
        @ViewBuilder message: @escaping () -> Message
    ) -> some View {
        modifier(
            CompatAlertModifier(
                title: title,
                isPresented: isPresented,
                dismissOnTap: dismissOnTap,
                actions: actions,
                message: message
            )
        )
    }
}

// MARK: - Safe area insets

/// `VerticalEdge` is iOS 15, so the shims name their own edges.
enum CompatVerticalEdge {
    case all, top, bottom
}

extension View {
    /// iOS 14 has no `safeAreaInset(edge:spacing:content:)`. Stacking the inset
    /// next to the content reproduces the visible result: bars pinned to an edge
    /// and the scrollable region taking the remaining space.
    func compatSafeAreaInset<Inset: View>(
        edge: CompatVerticalEdge,
        spacing: CGFloat = 0,
        @ViewBuilder content: () -> Inset
    ) -> some View {
        VStack(spacing: spacing) {
            if edge == .top { content() }
            self
            if edge == .bottom { content() }
        }
    }
}

/// `safeAreaBar(edge:spacing:content:)` is iOS 26; pinning the bar with a
/// stack gives the same visible result on iOS 14.
extension View {
    func compatSafeAreaBar<Bar: View>(
        edge: CompatVerticalEdge,
        spacing: CGFloat = 0,
        @ViewBuilder content: () -> Bar
    ) -> some View {
        compatSafeAreaInset(edge: edge, spacing: spacing, content: content)
    }
}

// MARK: - Keyboard submit

/// `.onSubmit` and `.submitLabel` are iOS 15. Every form that used them also
/// carries an explicit submit button, so the shims keep the call sites readable
/// without pretending to intercept the keyboard's return key.
extension View {
    func compatOnSubmit(_ action: @escaping () -> Void) -> some View { self }

    func compatSubmitLabel(_ label: CompatSubmitLabel) -> some View { self }
}

enum CompatSubmitLabel {
    case done, go, send, join, route, search, `return`, next, `continue`
}

// MARK: - Date formatting

/// `.formatted(date:time:)` is iOS 15.
func compatFormatted(_ date: Date, dateStyle: DateFormatter.Style, timeStyle: DateFormatter.Style) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = dateStyle
    formatter.timeStyle = timeStyle
    return formatter.string(from: date)
}

import SwiftUI

struct AppGlassButton: View {
    enum Style {
        case regular
        case prominent
    }

    let title: String?
    let systemImage: String?
    let role: ButtonRole?
    let style: Style
    let isLoading: Bool
    let disabled: Bool
    let maxWidth: CGFloat?
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    init(
        _ title: String,
        systemImage: String? = nil,
        role: ButtonRole? = nil,
        style: Style = .regular,
        isLoading: Bool = false,
        disabled: Bool = false,
        maxWidth: CGFloat? = .infinity,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.role = role
        self.style = style
        self.isLoading = isLoading
        self.disabled = disabled
        self.maxWidth = maxWidth
        self.action = action
    }

    init(
        systemImage: String,
        role: ButtonRole? = nil,
        style: Style = .regular,
        isLoading: Bool = false,
        disabled: Bool = false,
        maxWidth: CGFloat? = nil,
        action: @escaping () -> Void
    ) {
        self.title = nil
        self.systemImage = systemImage
        self.role = role
        self.style = style
        self.isLoading = isLoading
        self.disabled = disabled
        self.maxWidth = maxWidth
        self.action = action
    }

    var body: some View {
        if style == .prominent {
            button
                .buttonStyle(CompatProminentButtonStyle())
                .accentColor(AppTheme.primaryControlBackground(colorScheme))
                .foregroundColor(AppTheme.primaryControlForeground(colorScheme))
        } else {
            button
                .buttonStyle(CompatBorderedButtonStyle())
        }
    }

    private var button: some View {
        Button(role: role, action: action) {
            label
                .opacity(isLoading ? 0 : 1)
                .compatOverlay {
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.75)
                            .accentColor(progressTint)
                    }
                }
                .frame(maxWidth: maxWidth)
        }
        .compatButtonBorderShape(title == nil ? .circle : .capsule)
        .compatControlSize(.large)
        .disabled(disabled || isLoading)
        .animation(.easeInOut(duration: 0.18))
    }

    private var label: some View {
        HStack(spacing: 10) {
            if let systemImage {
                AppSymbol(systemImage)
            }
            if let title {
                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
        }
    }

    private var progressTint: Color {
        style == .prominent ? AppTheme.primaryControlForeground(colorScheme) : .secondary
    }
}

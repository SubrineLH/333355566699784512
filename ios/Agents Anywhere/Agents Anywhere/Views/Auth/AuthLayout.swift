import SwiftUI

struct AuthScreen<Content: View>: View {
    let title: String
    let onCancel: () -> Void
    let subtitle: String?
    let showsCancel: Bool
    @ViewBuilder let content: Content

    @Environment(\.colorScheme) private var colorScheme

    init(
        title: String,
        subtitle: String? = nil,
        showsCancel: Bool = true,
        onCancel: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.showsCancel = showsCancel
        self.onCancel = onCancel
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if let subtitle {
                    Text(subtitle)
                        .font(.title3)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                content
            }
            .padding(.horizontal, 22)
            .padding(.top, 22)
            .padding(.bottom, 34)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if showsCancel { SheetCloseToolbar(action: onCancel) } else { EmptyView() }
            }
        }
    }
}

struct AuthWelcomeLayout<Content: View>: View {
    @ViewBuilder let content: Content

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            content
            Spacer()
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.appBackground(colorScheme))
    }
}

struct AuthBrandLockup: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 18) {
            AAWordmark(fontSize: 42)
                .foregroundColor(AppTheme.primaryText(colorScheme))

            Text(L("Connect this device to your workspace."))
                .font(.body)
                .foregroundColor(AppTheme.secondaryText(colorScheme))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct AuthPrimaryButton: View {
    let title: String
    let systemImage: String?
    let isLoading: Bool
    let disabled: Bool
    let action: () -> Void

    init(
        title: String,
        systemImage: String? = nil,
        isLoading: Bool = false,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.isLoading = isLoading
        self.disabled = disabled
        self.action = action
    }

    var body: some View {
        AppGlassButton(
            title,
            systemImage: systemImage,
            style: .prominent,
            isLoading: isLoading,
            disabled: disabled,
            action: action,
        )
    }
}

struct AuthGlassButton: View {
    let title: String?
    let systemImage: String?
    let role: ButtonRole?
    let action: () -> Void

    init(_ title: String, role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = nil
        self.role = role
        self.action = action
    }

    init(_ title: String, systemImage: String, role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.role = role
        self.action = action
    }

    init(systemImage: String, role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.title = nil
        self.systemImage = systemImage
        self.role = role
        self.action = action
    }

    var body: some View {
        if let title {
            AppGlassButton(
                title,
                systemImage: systemImage,
                role: role,
                action: action,
            )
        } else if let systemImage {
            AppGlassButton(
                systemImage: systemImage,
                role: role,
                action: action,
            )
        }
    }

}

struct LoginSummaryView: View {
    let server: String
    let userId: String

    var body: some View {
        VStack(spacing: 12) {
            summaryRow(L("Server"), server)
            Divider()
            summaryRow(L("User"), userId)
        }
        .font(.body)
        .padding(.vertical, 4)
    }

    private func summaryRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(title)
                .foregroundColor(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
    }
}

struct AuthResultView: View {
    let title: String
    let message: String
    let buttonTitle: String
    let buttonSystemImage: String
    let symbolName: String
    let symbolColor: Color
    var isLoading = false
    let action: () -> Void

    var body: some View {
        AuthWelcomeLayout {
            VStack(spacing: 26) {
                VStack(spacing: 16) {
                    AppSymbol(symbolName, size: 56)
                        .foregroundColor(symbolColor)

                    VStack(spacing: 8) {
                        Text(title)
                            .font(.system(size: 34, weight: .bold))
                            .multilineTextAlignment(.center)

                        Text(message)
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                AuthPrimaryButton(
                    title: buttonTitle,
                    systemImage: buttonSystemImage,
                    isLoading: isLoading,
                    disabled: isLoading,
                    action: action,
                )
            }
        }
    }
}

import SwiftUI

struct QRCodeLoginView: View {
    let appState: AppState
    @Environment(\.presentationMode) private var presentationMode
    @State private var path: [QRLoginRoute] = []
    @State private var isClosing = false

    var onDashboardRequested: () -> Void = {}

    var body: some View {
        CompatNavigationStack(path: $path) {
            QRScanStepView(
                appState: appState,
                onCancel: { presentationMode.wrappedValue.dismiss() },
                onPayload: { payload in
                    path.append(.confirm(payload))
                },
            )
        } destination: { route in
            switch route {
            case let .confirm(payload):
                QRConfirmStepView(
                    appState: appState,
                    payload: payload,
                    onCancel: { presentationMode.wrappedValue.dismiss() },
                    onWaiting: {
                        path.append(.waiting(payload))
                    },
                )
            case let .waiting(payload):
                QRWaitingStepView(
                    appState: appState,
                    payload: payload,
                    onCancel: { presentationMode.wrappedValue.dismiss() },
                    onSignedIn: {
                        path.append(.success)
                    },
                )
            case .success:
                AuthResultView(
                    title: L("Login Success"),
                    message: L("Your iPhone is signed in. Go to your dashboard to continue."),
                    buttonTitle: L("Go to Dashboard"),
                    buttonSystemImage: "arrow.right",
                    symbolName: "checkmark.circle.fill",
                    symbolColor: .green,
                    isLoading: isClosing,
                ) {
                    guard !isClosing else { return }
                    isClosing = true
                    onDashboardRequested()
                }
                .navigationBarBackButtonHidden(true)
            }
        }
        .appSheetPresentation(.expanded)
    }
}

private enum QRLoginRoute: Hashable {
    case confirm(MobileLoginPayload)
    case waiting(MobileLoginPayload)
    case success
}

private struct QRScanStepView: View {
    let appState: AppState
    @Environment(\.colorScheme) private var colorScheme

    let onCancel: () -> Void
    let onPayload: (MobileLoginPayload) -> Void

    @State private var parseError: String?
    @State private var didReadPayload = false

    var body: some View {
        AuthScreen(
            title: L("QR Code Login"),
            subtitle: L("Scan the login QR code from the web console."),
            onCancel: onCancel,
        ) {
            VStack(alignment: .leading, spacing: 16) {
                ZStack(alignment: .bottom) {
                    QRCodeScannerView(
                        onCode: { value in
                            guard !didReadPayload else { return }
                            parsePayload(value)
                        },
                        onError: { message in
                            parseError = message
                        },
                    )
                    .frame(height: 380)
                    .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))

                    Text(L("Point the camera at the web QR code"))
                        .font(.footnote.weight(.medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .compatBackground(AppTheme.glassScrim(colorScheme), in: Capsule())
                        .compatGlassEffect(.regular, in: .capsule)
                        .padding(.bottom, 18)
                }

                if let parseError {
                    Text(parseError)
                        .font(.footnote)
                        .foregroundColor(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let error = appState.authError {
                    Text(error)
                        .font(.footnote)
                        .foregroundColor(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func parsePayload(_ value: String) {
        parseError = nil
        do {
            let data = Data(value.utf8)
            let decoded = try JSONDecoder().decode(MobileLoginPayload.self, from: data)
            guard decoded.type == "agents-anywhere.mobile-login", decoded.version == 1 else {
                parseError = L("This is not an Agents Anywhere mobile login QR code.")
                return
            }
            didReadPayload = true
            onPayload(decoded)
        } catch {
            parseError = L("This QR code is not a valid Agents Anywhere login code.")
        }
    }
}

private struct QRConfirmStepView: View {
    let appState: AppState
    @Environment(\.colorScheme) private var colorScheme

    let payload: MobileLoginPayload
    let onCancel: () -> Void
    let onWaiting: () -> Void

    @State private var isRequesting = false
    @State private var alertMessage: String?
    @State private var requestTask: Task<Void, Never>?

    var body: some View {
        AuthScreen(
            title: L("Confirm Login"),
            subtitle: L("Do you want to sign in as \(payload.userId)?"),
            onCancel: onCancel,
        ) {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("Server"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.secondary)
                    Text(payload.webUrl)
                        .font(.title3.weight(.semibold))
                        .foregroundColor(AppTheme.primaryText(colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .compatBackground(AppTheme.groupedFill(colorScheme), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                .compatGlassEffect(.regular, in: .rect(cornerRadius: 28, style: .continuous))

                AuthPrimaryButton(
                    title: L("Log In"),
                    isLoading: isRequesting,
                ) {
                    requestTask = Task { await requestWebConfirmation() }
                }
            }
        }
        .onDisappear { requestTask?.cancel(); requestTask = nil }
        .compatAlert(L("Login Request Failed"), isPresented: Binding(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } },
        )) {
            if appState.authNeedsLocalNetworkSettings {
                Button(L("Open Settings")) {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
            }
            Button(L("OK"), role: .cancel) {}
        } message: {
            Text(alertMessage ?? L("The login request could not be started."))
        }
    }

    private func requestWebConfirmation() async {
        guard !isRequesting else { return }
        isRequesting = true
        defer { isRequesting = false }
        if await appState.requestMobileLogin(payload: payload) {
            if !Task.isCancelled { onWaiting() }
        } else if !Task.isCancelled {
            alertMessage = appState.authError ?? L("The login request could not be started.")
        }
    }
}

private struct QRWaitingStepView: View {
    let appState: AppState
    @Environment(\.colorScheme) private var colorScheme

    let payload: MobileLoginPayload
    let onCancel: () -> Void
    let onSignedIn: () -> Void

    @State private var statusText = L("Waiting for confirmation")
    @State private var isFinishing = false
    @State private var alertMessage: String?
    @State private var pollingTask: Task<Void, Never>?

    var body: some View {
        AuthScreen(
            title: L("Confirm on Web"),
            subtitle: L("Click confirm in the web console, then return here."),
            showsCancel: !isFinishing,
            onCancel: onCancel,
        ) {
            VStack(spacing: 24) {
                AppSymbol("desktopcomputer.and.arrow.down", size: 58)
                    .foregroundColor(AppTheme.primaryText(colorScheme))

                Text(statusText)
                    .font(.headline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)

                ProgressView()
                    .compatControlSize(.large)
                    .accentColor(AppTheme.primaryText(colorScheme))
                    .padding(.top, 4)
            }
            .padding(.vertical, 24)
        }
        .onAppear {
            startPolling()
        }
        .onDisappear {
            stopPolling()
        }
        .navigationBarBackButtonHidden(isFinishing)
        .compatAlert(L("Login Status"), isPresented: Binding(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } },
        )) {
            Button(L("OK"), role: .cancel) {}
        } message: {
            Text(alertMessage ?? L("Confirm the login on the web console and try again."))
        }
    }

    private func startPolling() {
        stopPolling()
        statusText = L("Waiting for confirmation")
        pollingTask = Task {
            while !Task.isCancelled {
                let shouldContinue = await pollApprovalOnce()
                if !shouldContinue {
                    return
                }
                try? await compatSleep(seconds: 1.5)
            }
        }
    }

    private func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    @MainActor
    private func pollApprovalOnce() async -> Bool {
        guard let status = await appState.mobileLoginStatus(payload: payload) else {
            alertMessage = appState.authError ?? L("Could not check the login status.")
            return false
        }

        switch status.status {
        case "approved":
            await finishLogin()
            return false
        case "pending_web_confirm":
            statusText = L("Waiting for confirmation")
            return true
        case "rejected":
            alertMessage = L("This login request was rejected.")
            return false
        case "expired":
            alertMessage = L("This login request expired. Scan a new QR code.")
            return false
        case "consumed":
            alertMessage = L("This login request has already been used.")
            return false
        default:
            alertMessage = L("Current login status: \(status.status)")
            return false
        }
    }

    private func finishLogin() async {
        guard !isFinishing else { return }
        isFinishing = true
        await appState.exchangeMobileLogin(payload: payload, showSignedInRoute: false)
        if appState.me != nil {
            onSignedIn()
        } else {
            isFinishing = false
            alertMessage = appState.authError ?? L("The login could not be completed.")
        }
    }
}

#Preview {
    QRCodeLoginView(appState: AppState())
}

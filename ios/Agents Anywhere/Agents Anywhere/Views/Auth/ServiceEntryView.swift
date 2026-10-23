import SwiftUI

struct ServiceEntryView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showsPrivacyPolicy = false
    var onManualLogin: () -> Void = {}
    var onQRCodeLogin: () -> Void = {}

    var body: some View {
        CompatPlainNavigationStack {
            AuthWelcomeLayout {
                AuthBrandLockup()

                VStack(spacing: 12) {
                    AuthPrimaryButton(title: L("QR Code Login"), systemImage: "qrcode.viewfinder") {
                        onQRCodeLogin()
                    }

                    AuthGlassButton(L("Manual Login"), systemImage: "link") {
                        onManualLogin()
                    }
                }
                .frame(maxWidth: 340)

                if let error = appState.authError {
                    Text(error)
                        .font(.footnote)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 340)
                }
            }
            .navigationTitle("")
            .compatSafeAreaInset(edge: .bottom) {
                Button(L("privacyPolicy.title")) { showsPrivacyPolicy = true }
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .frame(minHeight: 44)
                    .padding(.horizontal, 24)
                    .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $showsPrivacyPolicy) {
            PrivacyPolicySheet()
        }
    }
}

#Preview {
    ServiceEntryView()
        .environmentObject(AppState())
}

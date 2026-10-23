import SwiftUI

struct PasswordSettingsView: View {
    @EnvironmentObject private var appState: AppState

    @Binding var draft: AccountPasswordDraft
    @Environment(\.presentationMode) private var presentationMode

    var body: some View {
        Form {
            Section(L("New password")) {
                SecureField(L("New password"), text: $draft.password)
                    .textContentType(.newPassword)
            }
            Section {
                SecureField(L("Confirm password"), text: $draft.confirmation)
                    .textContentType(.newPassword)
            } header: {
                Text(L("Confirm password"))
            } footer: {
                Text(L("Use at least 8 characters. Changing the password does not sign out this device."))
            }

        }
        .textFieldStyle(.plain)
        .navigationTitle(L("Password"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            SheetSaveToolbar(isWorking: appState.isAccountWorking,
                saveDisabled: draft.password.count < 8 || draft.password != draft.confirmation,
                onSave: savePassword)
        }
        .disabled(appState.isAccountWorking)
    }

    private func savePassword() {
        Task {
            let saved = await appState.changeAccountPassword(
                newPassword: draft.password,
                confirmation: draft.confirmation
            )
            if saved {
                draft = AccountPasswordDraft()
                presentationMode.wrappedValue.dismiss()
            }
        }
    }
}

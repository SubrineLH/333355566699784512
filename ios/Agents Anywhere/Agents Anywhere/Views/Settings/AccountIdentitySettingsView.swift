import SwiftUI

struct AccountIdentitySettingsView: View {
    enum Mode { case nickname, email }
    let mode: Mode
    @Binding var draft: AccountIdentityDraft
    @EnvironmentObject private var appState: AppState
    @Environment(\.presentationMode) private var presentationMode
    @State private var config: AuthConfig?
    @State private var isLoadingConfig = false
    @State private var cooldown = 0
    @State private var codeSent = false
    @State private var error: String?

    private var normalized: String { draft.text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var title: String { mode == .nickname ? L("Nickname") : L("Email") }
    private var validEmail: Bool { normalized.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#, options: .regularExpression) != nil }
    private var verificationRequired: Bool { config?.emailVerificationRequired == true }
    private var canSave: Bool {
        mode == .nickname ? (1...64).contains(normalized.count) && draft.text != draft.initialText :
            config != nil && validEmail && (draft.text != draft.initialText || appState.me?.emailVerified != true) && (!verificationRequired || draft.code.count == 6)
    }

    var body: some View {
        Form {
            Section(title) {
                TextField(title, text: $draft.text)
                    .textContentType(mode == .nickname ? .nickname : .emailAddress)
                    .keyboardType(mode == .email ? .emailAddress : .default)
                    .compatTextInputAutocapitalization(.never).compatAutocorrectionDisabled()
                    .compatOnChange(of: draft.text) { _, _ in draft.code = ""; codeSent = false }
            }
            if mode == .email {
                if draft.text == draft.initialText && !draft.initialText.isEmpty {
                    Section {
                        CompatLabeledContent(L("Email status"),
                            value: appState.me?.emailVerified == true ? L("Verified") : L("Not verified"))
                    }
                }
                Section {
                    if isLoadingConfig {
                        ProgressView(L("Loading email settings…"))
                    } else if config == nil {
                        Button(L("Retry loading email settings")) { Task { await loadConfig() } }
                    } else if verificationRequired {
                        TextField(L("Email verification code"), text: $draft.code)
                            .textContentType(.oneTimeCode).keyboardType(.numberPad)
                            .compatOnChange(of: draft.code) { _, _ in draft.code = String(draft.code.filter(\.isNumber).prefix(6)) }
                        Button(cooldown > 0 ? L("Resend in \(cooldown) s") : L("Send verification code"), action: sendCode)
                            .disabled(!validEmail || cooldown > 0 || draft.isWorking)
                        if codeSent { Text(L("Code sent. Check your inbox.")).foregroundColor(.secondary) }
                    }
                } footer: {
                    if let config, !config.emailVerificationRequired {
                        Text(L("This service accepts email without a verification code."))
                    }
                }
            }
        }
        .textFieldStyle(.plain)
        .disabled(draft.isWorking)
        .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
        .toolbar { SheetSaveToolbar(isWorking: draft.isWorking, saveDisabled: !canSave, onSave: save) }
        .compatTask {
            if !draft.didInitialize {
                draft.didInitialize = true
                draft.text = mode == .nickname ? appState.me?.displayName ?? "" : appState.me?.email ?? ""
                draft.initialText = draft.text
            }
            if mode == .email { await loadConfig() }
        }
        .compatTask(id: cooldown) {
            guard cooldown > 0 else { return }
            do { try await compatSleep(seconds: 1); cooldown -= 1 } catch {}
        }
        .compatAlert(L("Account update failed"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button(L("OK"), role: .cancel) { error = nil }
        } message: { Text(error ?? "") }
    }

    private func loadConfig() async {
        isLoadingConfig = true
        defer { isLoadingConfig = false }
        do { config = try await appState.accountAuthConfig() }
        catch is CancellationError {}
        catch { self.error = error.localizedDescription }
    }
    private func save() {
        guard canSave, !draft.isWorking else { return }
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        draft.isWorking = true
        Task {
            await Task.yield()
            defer { draft.isWorking = false }
            do {
                if mode == .nickname { try await appState.updateAccountProfile(displayName: normalized) }
                else { try await appState.bindAccountEmail(email: normalized, code: verificationRequired ? draft.code : nil) }
                draft.initialText = draft.text; draft.code = ""; presentationMode.wrappedValue.dismiss()
            } catch { self.error = error.localizedDescription }
        }
    }
    private func sendCode() {
        guard !draft.isWorking, validEmail, cooldown == 0 else { return }
        draft.isWorking = true
        Task {
            defer { draft.isWorking = false }
            do {
                let response = try await appState.sendAccountEmailCode(email: normalized)
                cooldown = max(response.retryAfter, 1); codeSent = true
            } catch { self.error = error.localizedDescription }
        }
    }
}

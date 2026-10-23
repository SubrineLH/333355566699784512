import SwiftUI

struct AccountSettingsSheet: View {
    let appState: AppState
    @Environment(\.presentationMode) private var presentationMode
    @AppStorage(AppAppearance.storageKey) private var appearanceValue = AppAppearance.system.rawValue
    @AppStorage(ProjectSidebarPreferences.sessionListKey) private var showsSessionList = false
    @AppStorage(ProjectSidebarPreferences.compactSessionListKey) private var compactSessionList = false
    @AppStorage(ReplyPresentation.plainFadeKey) private var plainFade = false
    @State private var confirmsSignOut = false
    @State private var signOutError: String?
    @StateObject private var toasts = ChatToastStore()
    @State private var drafts = AccountSettingsDrafts()
    @State private var confirmsDiscard = false

    var body: some View {
        CompatPlainNavigationStack {
            List {
                if let me = appState.me {
                    Section {
                        HStack(spacing: 16) {
                            AccountAvatarView(displayName: me.accountLabel, source: appState.accountAvatarSource, size: 60)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(me.accountLabel).font(.title3.weight(.semibold))
                                if let email = me.email { Text(email).font(.subheadline).foregroundColor(.secondary) }
                                Text(me.role == .admin ? L("Administrator") : L("Member"))
                                    .font(.caption).foregroundColor(.secondary)
                            }
                            Spacer(minLength: 0)
                        }.padding(.vertical, 12)
                    }.compatListRowSeparator(.hidden)

                    Section(L("Account")) {
                        NavigationLink { AccountIdentitySettingsView(mode: .nickname, draft: $drafts.nickname) } label: {
                            SettingsRow(title: L("Nickname"), symbol: "person.text.rectangle", value: me.displayName)
                        }
                        NavigationLink { AccountIdentitySettingsView(mode: .email, draft: $drafts.email) } label: {
                            SettingsRow(title: L("Email"), symbol: "envelope", value: me.email)
                        }
                        NavigationLink { AvatarSettingsView(draft: $drafts.avatar) } label: {
                            SettingsRow(title: L("Profile photo"), symbol: "person.crop.circle")
                        }
                        NavigationLink { PasswordSettingsView(draft: $drafts.password) } label: {
                            SettingsRow(title: L("Password"), symbol: "key")
                        }
                    }
                }

                Section(L("App")) {
                    NavigationLink { AppearanceSettingsView() } label: {
                        SettingsRow(title: L("Appearance"), symbol: "circle.lefthalf.filled",
                            value: L((AppAppearance(rawValue: appearanceValue) ?? .system).title))
                    }
                    NavigationLink { SettingsLanguageView() } label: {
                        SettingsRow(title: L("Language"), symbol: "globe", value: SettingsLanguageView.currentLanguage)
                    }
                    Toggle(isOn: Binding(
                        get: { !showsSessionList },
                        set: { showsSessionList = !$0 }
                    )) {
                        Label(L("Project mode"), appSymbol: "folder")
                            .labelStyle(.titleAndIcon)
                    }.accentColor(.green)
                    Toggle(isOn: $compactSessionList) {
                        Label(L("Single-line sessions"), appSymbol: "sidebar.left")
                            .labelStyle(.titleAndIcon)
                    }
                    .accentColor(.green)
                    .disabled(!showsSessionList)
                }
                revealAnimationSection
                Section(L("Workspace")) {
                    NavigationLink { SettingsServerView() } label: {
                        SettingsRow(title: L("Server"), symbol: "server.rack", value: appState.serverURL?.host)
                    }
                }
                Section {
                    NavigationLink {
                        PrivacyPolicyContent().settingsPage(L("privacyPolicy.title"))
                    } label: {
                        SettingsRow(title: L("privacyPolicy.title"), symbol: "hand.raised")
                    }
                    NavigationLink { SettingsAboutView() } label: {
                        SettingsRow(title: L("About"), symbol: "info.circle")
                    }
                }
                Section {
                    Button(role: .destructive) { confirmsSignOut = true } label: {
                        SettingsRow(title: L("Sign out"), symbol: "rectangle.portrait.and.arrow.forward")
                            .foregroundColor(.red)
                    }.disabled(appState.isAccountWorking)
                } footer: {
                    Text("Agents Anywhere · \(SettingsAboutView.version)")
                        .font(.footnote).frame(maxWidth: .infinity).padding(.top, 16)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(L("Settings")).navigationBarTitleDisplayMode(.inline)
            .toolbar { SheetCloseToolbar(disabled: isWorking, action: close) }
            .compatRefreshable { _ = await appState.refreshAccount() }
            .compatAlert(L("Sign out?"), isPresented: $confirmsSignOut) {
                Button(L("Cancel"), role: .cancel) {}
                Button(L("Sign out"), role: .destructive, action: signOut)
            } message: {
                Text(L("Your saved credentials will be removed from this device. You will need to sign in again to reconnect."))
            }
            .compatAlert(L("Could not sign out"), isPresented: Binding(get: { signOutError != nil }, set: { if !$0 { signOutError = nil } })) {
                Button(L("OK"), role: .cancel) { signOutError = nil }
            } message: { Text(signOutError ?? "") }
        }
        .compatOverlay(alignment: .top) { ChatErrorToasts(store: toasts, isRetrying: false, onRetry: { _ in }) }
        .compatOnChange(of: appState.accountError) { _, error in
            guard let error else { return }
            toasts.update(source: "account", failure: .init(kind: .rejected, message: error))
            appState.dismissAccountError()
        }
        .environment(\.closeSettings, close)
        // Native sheet presentation can create a new hosting boundary on Mac.
        // Use the caller's store here and provide it to every settings subpage.
        .environmentObject(appState)
        .appSheetPresentation(.expanded)
        .compatInteractiveDismissDisabled(drafts.hasChanges || isWorking)
        .confirmDiscardChanges($confirmsDiscard) { presentationMode.wrappedValue.dismiss() }
    }

    private var isWorking: Bool { appState.isAccountWorking || drafts.isWorking }

    private var revealAnimationSection: some View {
        Section {
            Toggle(isOn: Binding(get: { !plainFade }, set: { plainFade = !$0 })) {
                Label(L("Reveal animation"), appSymbol: "sparkles").labelStyle(.titleAndIcon)
            }
            .accentColor(.green)
        } footer: {
            Text(L("Off: new text fades in without the blur and rise."))
        }
    }
    private func close() {
        guard !isWorking else { return }
        if drafts.hasChanges { confirmsDiscard = true } else { presentationMode.wrappedValue.dismiss() }
    }

    private func signOut() {
        do { try appState.signOutAndDeleteCredentials(); presentationMode.wrappedValue.dismiss() }
        catch { signOutError = error.localizedDescription }
    }
}

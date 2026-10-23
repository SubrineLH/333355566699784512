import SwiftUI

/// Available before sign-in without a server connection or account state.
struct PrivacyPolicySheet: View {
    @Environment(\.presentationMode) private var presentationMode

    var body: some View {
        CompatPlainNavigationStack {
            PrivacyPolicyContent()
                .navigationTitle(L("privacyPolicy.title"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { SheetCloseToolbar { presentationMode.wrappedValue.dismiss() } }
        }
        .appSheetPresentation(.expanded)
    }
}

/// Settings pushes the same content inside its existing navigation stack.
struct PrivacyPolicyContent: View {
    @Environment(\.compatOpenURL) private var openURL

    var body: some View {
        List {
            Section {
                paragraph("privacyPolicy.introduction")
            } header: {
                Text(verbatim: "Agents Anywhere")
            } footer: {
                Text(L("privacyPolicy.updated"))
            }

            Section(header: Text(L("privacyPolicy.server.title"))) {
                paragraph("privacyPolicy.server.body")
            }

            Section(header: Text(L("privacyPolicy.agents.title"))) {
                paragraph("privacyPolicy.agents.body")
                paragraph("privacyPolicy.externalContent.body")
            }

            Section(header: Text(L("privacyPolicy.localStorage.title"))) {
                paragraph("privacyPolicy.localStorage.body")
            }

            Section(header: Text(L("privacyPolicy.permissions.title"))) {
                paragraph("privacyPolicy.permissions.body")
            }

            Section(header: Text(L("privacyPolicy.retention.title"))) {
                paragraph("privacyPolicy.retention.body")
            }

            Section(header: Text(L("privacyPolicy.contact.title"))) {
                paragraph("privacyPolicy.contact.body")
                Button { openURL(URL(string: "https://github.com/anywhere-labs/Agents-Anywhere")!) } label: {
                    Label(L("privacyPolicy.projectSupport"), appSymbol: "arrow.up.right")
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func paragraph(_ text: CompatLocalizedString) -> some View {
        Text(text)
            .fixedSize(horizontal: false, vertical: true)
            .compatTextSelection()
    }
}

#Preview {
    PrivacyPolicySheet()
}

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
    var body: some View {
        List {
            Section {
                paragraph("privacyPolicy.introduction")
            } header: {
                Text(verbatim: "Agents Anywhere")
            } footer: {
                Text(L("privacyPolicy.updated"))
            }

            Section(L("privacyPolicy.server.title")) {
                paragraph("privacyPolicy.server.body")
            }

            Section(L("privacyPolicy.agents.title")) {
                paragraph("privacyPolicy.agents.body")
                paragraph("privacyPolicy.externalContent.body")
            }

            Section(L("privacyPolicy.localStorage.title")) {
                paragraph("privacyPolicy.localStorage.body")
            }

            Section(L("privacyPolicy.permissions.title")) {
                paragraph("privacyPolicy.permissions.body")
            }

            Section(L("privacyPolicy.retention.title")) {
                paragraph("privacyPolicy.retention.body")
            }

            Section(L("privacyPolicy.contact.title")) {
                paragraph("privacyPolicy.contact.body")
                Link(destination: URL(string: "https://github.com/anywhere-labs/Agents-Anywhere")!) {
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

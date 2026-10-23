import SwiftUI
import UIKit

struct ConnectorCredentialSheet: View {
    @Environment(\.presentationMode) private var presentationMode

    let connector: V2Connector
    let connectorToken: String
    let serverURL: URL

    @State private var copiedField: ConnectorCredentialField?

    var body: some View {
        CompatPlainNavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Label(L("Connector disconnected"), appSymbol: "key.horizontal")
                        .font(.title2.weight(.semibold))

                    Text(L("The previous credential no longer works. Update the desktop Connector with these values before reconnecting it."))
                        .foregroundColor(.secondary)

                    ConnectorCredentialValue(
                        title: "Server URL",
                        value: serverURL.absoluteString,
                        copied: copiedField == .serverURL,
                        onCopy: { copy(serverURL.absoluteString, field: .serverURL) }
                    )
                    ConnectorCredentialValue(
                        title: "Connector ID",
                        value: connector.id,
                        copied: copiedField == .connectorId,
                        onCopy: { copy(connector.id, field: .connectorId) }
                    )
                    ConnectorCredentialValue(
                        title: "Connector token",
                        value: connectorToken,
                        copied: copiedField == .connectorToken,
                        onCopy: { copy(connectorToken, field: .connectorToken) }
                    )

                    Label(
                        L("This token is shown only now. Store it in the Connector configuration and do not share it."),
                        appSymbol: "exclamationmark.shield"
                    )
                    .font(.footnote)
                    .foregroundColor(.secondary)
                }
                .padding(20)
            }
            .navigationTitle(L("New credential"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                SheetCloseToolbar { presentationMode.wrappedValue.dismiss() }
            }
        }
        .appSheetPresentation(.expanded)
    }

    private func copy(_ value: String, field: ConnectorCredentialField) {
        UIPasteboard.general.string = value
        copiedField = field
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

private enum ConnectorCredentialField: Hashable {
    case serverURL
    case connectorId
    case connectorToken
}

private struct ConnectorCredentialValue: View {
    let title: CompatLocalizedString
    let value: String
    let copied: Bool
    let onCopy: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)

            HStack(alignment: .top, spacing: 10) {
                Text(value)
                    .font(Font.system(.footnote, design: .monospaced))
                    .compatTextSelection()
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button(action: onCopy) {
                    AppSymbol(copied ? "checkmark" : "doc.on.doc")
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(CompatBorderedButtonStyle())
                .compatButtonBorderShape(.circle)
                .accessibilityLabel(copied ? L("Copied") : L("Copy \(L(title))"))
            }
        }
        .padding(14)
        .compatBackground(Color(UIColor.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
    }
}

import SwiftUI

private struct SettingsCloseKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}
extension EnvironmentValues {
    var closeSettings: () -> Void {
        get { self[SettingsCloseKey.self] }
        set { self[SettingsCloseKey.self] = newValue }
    }
}

struct SettingsRow: View {
    let title: String
    let symbol: String
    var value: String?
    var body: some View {
        if let value, !value.isEmpty {
            CompatLabeledContent {
                Text(value).foregroundColor(.secondary).lineLimit(1).truncationMode(.middle)
            } label: {
                Label(title, appSymbol: symbol)
            }
        } else {
            Label(title, appSymbol: symbol)
        }
    }
}

private struct SettingsPageChrome: ViewModifier {
    let title: String
    @Environment(\.closeSettings) private var close
    func body(content: Content) -> some View {
        content
            .listStyle(.insetGrouped)
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbar { SheetCloseToolbar(action: close) }
    }
}
extension View {
    func settingsPage(_ title: String) -> some View { modifier(SettingsPageChrome(title: title)) }
}

struct SettingsLanguageView: View {
    @Environment(\.openURL) private var openURL
    var body: some View {
        List {
            Section {
                CompatLabeledRow(L("Current language"), value: Self.currentLanguage)
                Button(L("Open iOS Settings")) {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            } footer: {
                Text(L("Choose English or Simplified Chinese in the app's iOS language settings. Without an override, the app follows your preferred system language."))
            }
        }.settingsPage(L("Language"))
    }
    static var currentLanguage: String {
        Bundle.main.preferredLocalizations.first?.hasPrefix("zh") == true ? "简体中文" : "English"
    }
}

struct SettingsServerView: View {
    @EnvironmentObject private var appState: AppState
    var body: some View {
        List {
            Section(header: Text(L("Connection"))) {
                CompatLabeledRow(L("Status"), value: appState.isServerConnected ? L("Connected") : L("Offline"))
                if let url = appState.serverURL {
                    Text(url.absoluteString).font(Font.system(.callout, design: .monospaced)).compatTextSelection()
                    Button(L("Copy server address"), appSymbol: "doc.on.doc") {
                        UIPasteboard.general.string = url.absoluteString
                    }
                }
            }
            if let error = appState.restoreConnectionError {
                Section { Text(error).foregroundColor(.secondary) }
            }
        }.settingsPage(L("Server"))
    }
}

struct SettingsAboutView: View {
    var body: some View {
        List {
            Section {
                CompatLabeledRow(L("Version"), value: Self.version)
                CompatLabeledRow(L("Build"), value: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—")
            }
            Section {
                NavigationLink {
                    ScrollView {
                        Text(license).font(Font.system(.footnote, design: .monospaced)).compatTextSelection().padding(22)
                    }.settingsPage(L("Open-source notices"))
                } label: { SettingsRow(title: L("Open-source notices"), symbol: "doc.text") }
            }
        }.settingsPage(L("About"))
    }
    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—" }
    private var license: String {
        Bundle.main.url(forResource: "Lucide", withExtension: "txt").flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? "Lucide · ISC"
    }
}

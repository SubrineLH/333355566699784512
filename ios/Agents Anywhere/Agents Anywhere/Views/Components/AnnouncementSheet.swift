import SwiftUI

extension View {
    /// Checks the public announcement when the route is entered and when the app
    /// returns to the foreground (at most once a minute), matching Web and Android.
    /// Failures are ignored: announcements must never block sign-in or normal use.
    func announcementGate(server: URL?, route: AppState.Route, blocked: Bool) -> some View {
        modifier(AnnouncementGate(server: server, route: route, blocked: blocked))
    }
}

private struct AnnouncementGate: ViewModifier {
    let server: URL?
    let route: AppState.Route
    let blocked: Bool
    @Environment(\.scenePhase) private var scenePhase
    @State private var pending: PublicAnnouncement?
    @State private var pendingServer: URL?
    @State private var lastCheck: Date?
    private let readStore = AnnouncementReadStore()

    private var target: URL? {
        guard route != .loading else { return nil }
        return server ?? URL(string: ManualLoginView.cloudServer)?.normalizedServerURL()
    }

    private var checkKey: String {
        "\(route)|\(target?.absoluteString ?? "")|\(scenePhase == .active)"
    }

    func body(content: Content) -> some View {
        content
            .compatTask(id: checkKey) { await check() }
            .sheet(isPresented: presented) {
                if let pending {
                    AnnouncementSheet(announcement: pending, onAcknowledge: acknowledge)
                }
            }
    }

    private var presented: Binding<Bool> {
        Binding(
            get: { pending != nil && !blocked && scenePhase == .active },
            set: { if !$0 { acknowledge() } }
        )
    }

    private func check() async {
        guard scenePhase == .active, let target else { return }
        if pendingServer != target { pending = nil; pendingServer = nil; lastCheck = nil }
        if let lastCheck, Date().timeIntervalSince(lastCheck) < 60 { return }
        lastCheck = .now
        do {
            let current = try await APIClient(serverURL: target).announcement()
            guard !Task.isCancelled else { lastCheck = nil; return }
            pending = current.flatMap { readStore.isUnread($0, server: target) ? $0 : nil }
            pendingServer = target
        } catch {
            if Task.isCancelled { lastCheck = nil }
        }
    }

    private func acknowledge() {
        if let pending, let pendingServer { readStore.markRead(pending, server: pendingServer) }
        pending = nil
    }
}

private struct AnnouncementSheet: View {
    let announcement: PublicAnnouncement
    let onAcknowledge: () -> Void

    var body: some View {
        CompatPlainNavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let date = announcement.publishedDate {
                        Text(L("Published \(compatFormatted(date, dateStyle: .medium, timeStyle: .short))"))
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    ChatMarkdownView(text: announcement.markdown)
                        .compatTextSelection()
                }
                .frame(maxWidth: 640, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .navigationTitle(L("Announcement"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { SheetCloseToolbar(action: onAcknowledge) }
            .compatSafeAreaInset(edge: .bottom) {
                AuthPrimaryButton(title: L("Got it"), systemImage: "checkmark", action: onAcknowledge)
                    .frame(maxWidth: 340)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
            }
        }
        .appSheetPresentation(.compact)
    }
}

import SwiftUI
import UIKit

/// Web shows six project cards and a "show all" toggle; a phone column fits four.
private let collapsedDirectoryCount = 4

struct DeviceProjectList: View {
    let projects: [V2Project]
    let canManage: Bool
    let canReadFiles: Bool
    let onCreate: () -> Void
    let onOpen: (V2Project) -> Void
    let onNewSession: (V2Project) -> Void
    let onFiles: (V2Project) -> Void
    let onEdit: (V2Project) -> Void
    let onPin: (V2Project) -> Void
    let onArchive: (V2Project) -> Void
    let onDelete: (V2Project) -> Void

    var body: some View {
        DeviceSection(L("Projects")) {
            DeviceHeaderIconButton(title: L("Create project"), symbol: "plus", action: onCreate)
                .disabled(!canManage)
        } content: {
            if projects.isEmpty {
                DeviceEmptyText(text: L("No projects yet"))
            } else {
                DeviceDirectoryGrid(items: projects) { project in
                    DeviceDirectoryCard(name: project.name, path: project.workspacePath, pinned: project.pinned,
                        openHint: L("Show project sessions"),
                        onOpen: { onOpen(project) }, onNewSession: { onNewSession(project) })
                    .contextMenu {
                        Button(L("New session"), systemImage: "square.and.pencil") { onNewSession(project) }
                        Button(L("Files"), systemImage: "folder") { onFiles(project) }.disabled(!canReadFiles)
                        Divider()
                        Button(L("Rename project"), systemImage: "pencil") { onEdit(project) }.disabled(!canManage)
                        Button(project.pinned ? L("Unpin") : L("Pin"), systemImage: "pin") { onPin(project) }.disabled(!canManage)
                        Button(L("Copy path"), systemImage: "doc.on.doc") { UIPasteboard.general.string = project.workspacePath }
                        Divider()
                        Button(L("Archive project sessions"), systemImage: "archivebox") { onArchive(project) }.disabled(!canManage)
                        Button(L("Delete project"), systemImage: "trash", role: .destructive) { onDelete(project) }
                            .disabled(!canManage || project.sidebarSessionCounts.active + project.sidebarSessionCounts.archived > 0)
                    }
                }
            }
        }
    }
}

struct DeviceWorkspaceList: View {
    let workspaces: [WorkspaceDirectoryChoice]
    let canReadFiles: Bool
    let onBrowse: () -> Void
    let onOpen: (WorkspaceDirectoryChoice) -> Void
    let onNewSession: (WorkspaceDirectoryChoice) -> Void

    var body: some View {
        DeviceSection(L("工作目录")) {
            DeviceHeaderIconButton(title: L("选择工作目录"), symbol: "plus", action: onBrowse)
                .disabled(!canReadFiles)
        } content: {
            if workspaces.isEmpty {
                DeviceEmptyText(text: L("No workspaces yet"))
            } else {
                DeviceDirectoryGrid(items: workspaces) { workspace in
                    DeviceDirectoryCard(name: workspace.name, path: workspace.path,
                        openHint: L("Files"), canOpen: canReadFiles,
                        onOpen: { onOpen(workspace) }, onNewSession: { onNewSession(workspace) })
                    .contextMenu {
                        Button(L("New session"), systemImage: "square.and.pencil") { onNewSession(workspace) }
                        Button(L("Files"), systemImage: "folder") { onOpen(workspace) }.disabled(!canReadFiles)
                        Button(L("Copy path"), systemImage: "doc.on.doc") { UIPasteboard.general.string = workspace.path }
                    }
                }
            }
        }
    }
}

struct DeviceHeaderIconButton: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            AppSymbol(symbol, size: 18).frame(width: 36, height: 36).contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityLabel(title)
    }
}

/// One column on phones, two on wider layouts, collapsed to a few cards.
private struct DeviceDirectoryGrid<Item: Identifiable, Card: View>: View {
    let items: [Item]
    @ViewBuilder let card: (Item) -> Card
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 8)], spacing: 8) {
                ForEach(expanded ? items : Array(items.prefix(collapsedDirectoryCount))) { card($0) }
            }
            if items.count > collapsedDirectoryCount {
                Button { withAnimation(.snappy) { expanded.toggle() } } label: {
                    HStack(spacing: 4) {
                        Text(expanded ? L("Show less") :
                            L("Show all \(items.count - collapsedDirectoryCount) more"))
                        AppSymbol("chevron.right", size: 12).rotationEffect(.degrees(expanded ? -90 : 0))
                    }
                    .font(.footnote.weight(.medium)).foregroundColor(.secondary)
                    .frame(minHeight: 36).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct DeviceDirectoryCard: View {
    let name: String
    let path: String
    var pinned = false
    let openHint: String
    var canOpen = true
    let onOpen: () -> Void
    let onNewSession: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 4) {
            Button(action: onOpen) {
                HStack(spacing: 12) {
                    AppSymbol("folder", size: 18).foregroundColor(.secondary)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 4) {
                            Text(name).font(.subheadline.weight(.semibold)).lineLimit(1)
                            if pinned { AppSymbol("pin", size: 11).foregroundColor(.secondary) }
                        }
                        Text(path).font(Font.system(.caption, design: .monospaced)).foregroundColor(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                    }
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain).disabled(!canOpen).accessibilityHint(openHint)
            Button(action: onNewSession) {
                AppSymbol("square.and.pencil", size: 18).frame(width: 40, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityLabel(L("New session"))
        }
        .padding(.leading, 14).padding(.trailing, 4).padding(.vertical, 6)
        .compatBackground(AppTheme.groupedFill(colorScheme), in: .rect(cornerRadius: 16, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct DeviceSessionList: View {
    @ObservedObject var model: DeviceManagementModel
    let projects: [V2Project]
    let showsProjectNames: Bool
    let canManage: Bool
    let isWorking: Bool
    let onNewSession: () -> Void
    let onOpen: (String) -> Void
    let onArchive: (V2SessionMeta) -> Void
    let onArchiveAll: () -> Void

    private var restores: Bool { model.sessionFilter == .archived }
    private var isEmpty: Bool { model.filteredSessions.isEmpty }

    var body: some View {
        DeviceSection(L("Sessions")) {
            HStack(spacing: 8) {
                DevicePillButton(title: model.isSelectingSessions ? L("Cancel") : L("Select sessions")) {
                    if model.isSelectingSessions { model.stopSelectingSessions() } else { model.startSelectingSessions() }
                }
                .disabled(!canManage || (isEmpty && !model.isSelectingSessions))
                if !model.isSelectingSessions {
                    DevicePillButton(title: restores ? L("Restore all in scope") : L("Archive all in scope"),
                        isLoading: isWorking, action: onArchiveAll)
                        .disabled(!canManage || isEmpty)
                    DeviceHeaderIconButton(title: L("New session"), symbol: "square.and.pencil", action: onNewSession)
                }
            }
        } content: {
            VStack(alignment: .leading, spacing: 8) { filters; scopeMenu }
            .padding(.bottom, 4)
            if model.isSelectingSessions {
                Button(L("Select up to 200 sessions"), action: model.toggleSelectAll)
                    .font(.footnote.weight(.medium)).buttonStyle(.plain).foregroundColor(.secondary)
                    .frame(minHeight: 32).disabled(!canManage)
            }
            if isEmpty {
                DeviceEmptyText(text: L("No sessions here"))
            } else {
                DeviceRows {
                    ForEach(model.filteredSessions) { session in row(session) }
                }
            }
        }
    }

    private var filters: some View {
        DeviceFilterTags(values: V2DeviceSessionFilter.allCases,
            selection: Binding(get: { model.sessionFilter }, set: model.setSessionFilter)) { L($0.title) }
    }

    private var scopeMenu: some View {
        Menu {
            Picker(showsProjectNames ? L("Project") : L("工作目录"),
                selection: Binding(get: { model.projectID }, set: model.selectProject)) {
                Text(allScopesTitle).tag(String?.none)
                ForEach(projects) {
                    Text(showsProjectNames ? $0.name : $0.workspacePath).tag(Optional($0.id))
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(scopeTitle).lineLimit(1)
                AppSymbol("chevron.down", size: 12)
            }
            .font(.subheadline).foregroundColor(.secondary)
            .frame(minHeight: 34).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(showsProjectNames ? L("Project") : L("工作目录"))
    }

    private func row(_ session: V2SessionMeta) -> some View {
        Button { onOpen(session.id) } label: {
            HStack(spacing: 12) {
                if model.isSelectingSessions {
                    AppSymbol(model.selectedSessionIds.contains(session.id) ? "checkmark.circle.fill" : "circle", size: 18)
                        .foregroundColor(model.selectedSessionIds.contains(session.id) ? .primary : .secondary)
                        .frame(width: 14)
                } else {
                    DeviceStatusDot(tone: tone(session.status))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(session.title.flatMap { $0.isEmpty ? nil : $0 } ?? L("Untitled session"))
                        .font(.body.weight(session.unread ? .semibold : .medium))
                        .foregroundColor(.primary).lineLimit(1)
                    HStack(spacing: 6) {
                        Text(session.runtime)
                        if let subtitle = scopeSubtitle(session) {
                            Text(verbatim: "·"); Text(subtitle).lineLimit(1)
                        }
                    }
                    .font(.caption).foregroundColor(.secondary).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let date = activityDate(session) {
                    Text(compatFormatted(date, dateStyle: .medium, timeStyle: .none))
                        .font(.caption.monospacedDigit()).foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 10).frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(session.status.displayName)
        .contextMenu {
            Button(L("Open"), systemImage: "arrow.up.right") { onOpen(session.id) }
            Button(session.archived ? L("Restore") : L("Archive"),
                systemImage: session.archived ? "tray.and.arrow.up" : "archivebox") { onArchive(session) }
                .disabled(!canManage || session.id.hasPrefix("local:"))
            Button(L("Copy session ID"), systemImage: "doc.on.doc") { UIPasteboard.general.string = session.id }
        }
    }

    /// Same colors as Web's device page session dots.
    private func tone(_ status: V2RuntimeStatus) -> DeviceStatusTone {
        switch status {
        case .running: .ok
        case .waitingApproval, .blocked: .warning
        case .error: .error
        case .waiting, .pending, .stopping: .progress
        default: .neutral
        }
    }
    private var allScopesTitle: String {
        showsProjectNames ? L("All projects") : L("All workspaces")
    }
    private var scopeTitle: String {
        guard let project = projects.first(where: { $0.id == model.projectID }) else { return allScopesTitle }
        return showsProjectNames ? project.name : ProjectWorkspacePath.name(project.workspacePath)
    }
    private func scopeSubtitle(_ session: V2SessionMeta) -> String? {
        let project = projects.first { $0.id == session.projectId }
        if showsProjectNames { return project?.name }
        return (session.cwd ?? project?.workspacePath).map(ProjectWorkspacePath.name)
    }
    private func activityDate(_ session: V2SessionMeta) -> Date? {
        V2Timestamp.date(session.sortAt ?? session.lastActivityAt ?? session.lastItemAt)
    }
}

struct DeviceSessionSelectionDock: View {
    let count: Int
    let restores: Bool
    let isWorking: Bool
    let disabled: Bool
    let onCancel: () -> Void
    let onSubmit: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            Text("\(count) selected").font(.subheadline).compatMonospacedDigit()
            Spacer(minLength: 0)
            Button(L("Cancel"), action: onCancel).disabled(isWorking)
            AppGlassButton(restores ? L("dashboard.device.unarchiveSelected") : L("dashboard.device.archiveSelected"), systemImage: restores ? "tray.and.arrow.up" : "archivebox",
                style: .prominent, isLoading: isWorking, disabled: disabled || count == 0, maxWidth: nil, action: onSubmit)
        }
        .padding(14).compatGlassEffect(.regular, in: .rect(cornerRadius: 24))
        .padding(.horizontal, 24).padding(.bottom, 12).frame(maxWidth: 760).frame(maxWidth: .infinity)
    }
}

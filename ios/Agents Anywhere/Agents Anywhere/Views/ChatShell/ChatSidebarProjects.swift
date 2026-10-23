import SwiftUI

struct ChatSidebarProjects: View {
    @ObservedObject var repository: V2DashboardRepository
    @Binding var showsSessionList: Bool
    let selectedSessionID: String?
    let onShowArchives: () -> Void
    let onNewSession: (String) -> Void
    let onOpenSession: (String) -> Void
    let onRenameSession: (String, String) -> Void
    let onPinSession: (String, Bool) -> Void
    let onArchiveSession: (String) -> Void
    let onCopySession: (String) -> Void
    @State private var filter = V2DeviceSessionFilter.active
    @State private var createsProject = false
    @State private var editing: V2Project?
    @State private var action: ProjectAction?
    @State private var busy: Set<String> = []
    @State private var error: String?
    @State private var expandedSessionLists: Set<String> = []
    /// Sessions shown per expanded project before "show more", matching Web.
    private static let sessionPreview = 8

    private struct ProjectAction: Identifiable {
        let project: V2Project
        let deletes: Bool
        var id: String { project.id }
    }
    var body: some View {
        let projects = ProjectSidebarPresentation.projects(repository.projects, filter: filter, sessions: repository.sessions)
        let unassigned = ProjectSidebarPresentation.unassignedSessions(repository.sessions, projects: repository.projects, filter: filter)
        // Capture the value in this body, then pass it through the lazy builders.
        // Pinning moves a row between sections before the request clears busy;
        // cached row content must receive that final state change explicitly.
        let busyProjects = busy
        LazyVStack(alignment: .leading, spacing: 4) {
            if projects.contains(where: \.pinned) {
                Text(L("置顶项目")).font(.subheadline.weight(.semibold)).foregroundColor(.secondary)
                    .padding(.horizontal, 10).padding(.top, 16).padding(.bottom, 6)
                projectList(projects.filter(\.pinned), busyProjects: busyProjects)
            }
            HStack {
                Button { repository.sidebarPreferences.projectsExpanded.toggle() } label: {
                    HStack(spacing: 6) {
                        Text(L("项目"))
                        AppSymbol("chevron.right", size: 12)
                            .rotationEffect(.degrees(repository.sidebarPreferences.projectsExpanded ? 90 : 0))
                    }.font(.subheadline.weight(.semibold)).foregroundColor(.secondary)
                        .frame(minHeight: 44).contentShape(Rectangle())
                }.buttonStyle(.plain)
                Spacer()
                ChatSidebarListMenu(showsSessionList: $showsSessionList, onShowArchives: onShowArchives) {
                    Picker(L("会话"), selection: $filter) {
                        ForEach(V2DeviceSessionFilter.allCases) { Text($0.title).tag($0) }
                    }
                }
                Button(L("创建项目"), appSymbol: "plus") { createsProject = true }
                    .modifier(ChatSidebarIconControlStyle())
                    .disabled(!repository.canWrite)
            }.padding(.horizontal, 10).padding(.top, 16)
            if repository.sidebarPreferences.projectsExpanded {
                projectList(projects.filter { !$0.pinned }, busyProjects: busyProjects)
                if repository.isLoading && repository.projects.isEmpty { ProgressView().padding(12) }
                if repository.hasLoaded && repository.projects.isEmpty {
                    Text(L("创建一个项目，开始新的任务。"))
                        .font(.footnote).foregroundColor(.secondary).padding(10)
                }
            }
            if !unassigned.isEmpty {
                Text(L("未分组会话")).font(.subheadline.weight(.semibold)).foregroundColor(.secondary)
                    .padding(.horizontal, 10).padding(.top, 16).padding(.bottom, 6)
                sessionRows(unassigned, inset: false)
            }
        }
        .sheet(isPresented: $createsProject) {
            ProjectEditorSheet(repository: repository) {
                repository.sidebarPreferences.expandedProjects.insert($0.id)
                repository.sidebarPreferences.projectsExpanded = true
            }
        }
        .sheet(item: $editing) { ProjectEditorSheet(repository: repository, project: $0) }
        .compatAlert(action?.deletes == true ? L("删除项目？") : L("归档这个项目的会话？"), isPresented: Binding(
            get: { action != nil }, set: { if !$0 { action = nil } })) {
            Button(L("取消"), role: .cancel) { action = nil }
            Button(action?.deletes == true ? L("删除") : L("归档"), role: .destructive) {
                guard let pending = action else { return }
                action = nil
                perform(pending.project.id) {
                    if pending.deletes { try await repository.deleteProject(pending.project.id) }
                    else { try await repository.archiveProject(pending.project.id, archived: true) }
                }
            }
        } message: {
            Text(action?.deletes == true ? L("只有没有会话的项目可以删除，设备上的文件会保留。") : L("Archive all sessions in \(action?.project.name ?? "")? The project will remain available for future sessions."))
        }
        .compatAlert(L("操作未完成"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button(L("好")) { error = nil }
        } message: { Text(error ?? "") }
    }

    private var expanded: Set<String> { repository.sidebarPreferences.expandedProjects }

    private func projectList(_ values: [V2Project], busyProjects: Set<String>) -> some View {
        ForEach(values) { project in
            projectRow(project, isBusy: busyProjects.contains(project.id))
            if expanded.contains(project.id) { projectSessions(project) }
        }
    }

    private func projectRow(_ project: V2Project, isBusy: Bool) -> some View {
        HStack(spacing: 0) {
            Button { toggleProject(project.id) } label: {
                HStack(spacing: 8) {
                    AppSymbol(expanded.contains(project.id) ? "folder.fill" : "folder", size: 18)
                    Text(project.name).font(.body).lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if isBusy { ProgressView().compatControlSize(.mini) }
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
            }
            .accessibilityHint(expanded.contains(project.id) ? L("收起项目") : L("展开项目"))
            Button { onNewSession(project.id) } label: {
                AppSymbol("square.and.pencil", size: 18).frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .accessibilityLabel(Text(L("在 \(project.name) 中新建会话")))
        }
        .foregroundColor(.primary)
        .padding(.leading, 10).buttonStyle(.plain)
        .contentShape(Rectangle())
        .contextMenu { projectMenu(project, isBusy: isBusy) }
    }

    @ViewBuilder
    private func projectMenu(_ project: V2Project, isBusy: Bool) -> some View {
        let deviceName = repository.connectors.first { $0.id == project.connectorId }?.name ?? L("设备不可用")
        Section(deviceName) {
            Button(L("新建会话"), systemImage: "square.and.pencil") { onNewSession(project.id) }
            Button(L("编辑项目"), systemImage: "pencil") { editing = project }
                .disabled(!repository.canWrite || isBusy)
            Button(project.pinned ? L("取消置顶") : L("置顶"), systemImage: "pin") {
                perform(project.id) { try await repository.updateProject(project.id, pinned: !project.pinned) }
            }.disabled(!repository.canWrite || isBusy)
        }
        Section {
            Button(L("归档项目会话"), systemImage: "archivebox", role: .destructive) { action = .init(project: project, deletes: false) }
                .disabled(!repository.canWrite || isBusy)
            Button(L("删除项目"), systemImage: "trash", role: .destructive) { action = .init(project: project, deletes: true) }
                .disabled(!repository.canWrite || isBusy)
        }
    }

    @ViewBuilder
    private func projectSessions(_ project: V2Project) -> some View {
        let sessions = ProjectSidebarPresentation.sessions(repository.sessions, projectID: project.id, filter: filter)
        let showsAll = expandedSessionLists.contains(project.id)
        // Keep the open session visible even when it sorts past the preview.
        let visible = showsAll || sessions.count <= Self.sessionPreview ? sessions
            : sessions.enumerated().filter { $0.offset < Self.sessionPreview || $0.element.id == selectedSessionID }.map(\.element)
        sessionRows(visible, inset: true)
        if sessions.count > Self.sessionPreview {
            Button {
                if showsAll { expandedSessionLists.remove(project.id) } else { expandedSessionLists.insert(project.id) }
            } label: {
                Text(showsAll ? L("收起") : L("显示更多（\(sessions.count - visible.count)）"))
                    .font(.footnote).foregroundColor(.secondary)
                    .padding(.leading, 19)
                    .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
    private func sessionRows(_ sessions: [V2SessionMeta], inset: Bool) -> some View {
        LazyVStack(alignment: .leading, spacing: 2) {
            ForEach(sessions) { session in
                ChatSidebarSessionRow(session: .init(session: session), isSelected: selectedSessionID == session.id,
                    inset: inset,
                    onOpen: { onOpenSession(session.id) }, onRename: { onRenameSession(session.id, $0) },
                    onTogglePinned: { onPinSession(session.id, !session.pinned) }, onArchive: { onArchiveSession(session.id) },
                    onCopyId: { onCopySession(session.id) })
            }
        }
    }
    private func toggleProject(_ id: String) {
        if expanded.contains(id) { repository.sidebarPreferences.expandedProjects.remove(id) }
        else { repository.sidebarPreferences.expandedProjects.insert(id) }
    }
    private func perform(_ id: String, operation: @escaping () async throws -> Void) {
        guard !busy.contains(id) else { return }
        busy.insert(id)
        Task {
            defer { busy.remove(id) }
            do { try await operation() } catch { self.error = error.localizedDescription }
        }
    }
}

struct ArchivedSessionsSheet: View {
    let repository: V2DashboardRepository
    let onOpen: (String) -> Void
    let onRestore: (String) async -> Bool
    @Environment(\.presentationMode) private var presentationMode
    @State private var busy: Set<String> = []
    @State private var restoreError = false
    var body: some View {
        CompatPlainNavigationStack {
            List {
                ForEach(ProjectSidebarPresentation.sessions(repository.sessions, projectID: nil, filter: .archived)) { session in
                    HStack {
                        Button { presentationMode.wrappedValue.dismiss(); onOpen(session.id) } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(session.title ?? L("未命名会话")).foregroundColor(.primary).lineLimit(2)
                                Text(repository.projects.first { $0.id == session.projectId }?.name ?? session.cwd ?? "")
                                    .font(.caption).foregroundColor(.secondary).lineLimit(1)
                            }
                        }.buttonStyle(.plain)
                        Spacer()
                        Button {
                            busy.insert(session.id)
                            Task { let restored = await onRestore(session.id); busy.remove(session.id); restoreError = !restored }
                        } label: {
                            if busy.contains(session.id) { ProgressView() }
                            else { AppSymbol("tray.and.arrow.up") }
                        }.buttonStyle(.borderless).disabled(busy.contains(session.id) || !repository.canWrite)
                            .accessibilityLabel(L("恢复会话"))
                    }
                }
            }
            .navigationTitle(L("归档会话")).navigationBarTitleDisplayMode(.inline)
            .toolbar { SheetCloseToolbar { presentationMode.wrappedValue.dismiss() } }
            .compatRefreshable { await repository.refresh() }
        }
        .appSheetPresentation(.compact)
        .compatAlert(L("无法恢复会话，请稍后重试。"), isPresented: $restoreError) { Button(L("好"), role: .cancel) {} }
    }
}

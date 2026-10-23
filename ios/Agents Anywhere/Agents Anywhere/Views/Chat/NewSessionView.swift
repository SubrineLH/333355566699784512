import SwiftUI
import UIKit

struct NewSessionView: View, Equatable {
    @ObservedObject var model: NewSessionModel
    let connectors: [V2Connector]
    let sessions: [V2SessionMeta]
    let repository: V2DashboardRepository
    var dashboardLoading = false
    var dashboardError: String?
    let onMenu: () -> Void
    let onOpenDevice: (V2ConnectorID) -> Void
    let onCreated: (V2SessionMeta) -> Void
    let onRefresh: () async -> [V2Connector]
    @State private var showsTarget = false
    @State private var showsWorkspace = false
    @State private var showsFiles = false
    @EnvironmentObject private var appState: AppState
    @State private var confirmsRetry = false
    @AppStorage(ProjectSidebarPreferences.sessionListKey) private var showsSessionList = false
    @ScaledMetric(relativeTo: .body) private var bodyLineHeight: CGFloat = 22

    private var controls: ChatControlMetrics { .init(bodyLineHeight: bodyLineHeight) }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.model === rhs.model && lhs.connectors == rhs.connectors && lhs.sessions == rhs.sessions
            && lhs.dashboardLoading == rhs.dashboardLoading
            && lhs.dashboardError == rhs.dashboardError
    }

    @State private var welcomeHeight: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            GeometryReader { viewport in
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        NewSessionWelcomeView(deviceName: model.connector?.name,
                            agentName: model.runtime?.sessionDisplayName,
                            onChooseTarget: chooseTarget)
                            .compatOnGeometryChange(of: { $0.size.height }) { height in
                                welcomeHeight = height
                            }
                        statusContent
                    }
                        .padding(.top, max(0, (max(0, viewport.size.height - 48) - welcomeHeight) / 2))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(24)
                        .frame(maxWidth: 760)
                        .frame(maxWidth: .infinity)
                        .compatBackground { ChatPageScrollEdge() }
                }
                .compatScrollDismissesKeyboard(.interactively)
                .compatScrollEdgeEffectStyle(.soft, for: .top)
                .compatRefreshable { await refresh() }
            }
            .compatSafeAreaInset(edge: .bottom, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    // Follows the composer's glass edge in both states, a few
                    // points inside it and slightly apart, to sit balanced.
                    workspaceButton
                        .padding(.horizontal, model.draft.isExpanded
                            ? ChatControlMetrics.expandedHorizontalInset : ChatControlMetrics.collapsedHorizontalInset)
                        .padding(.leading, 6)
                        .padding(.bottom, 6)
                ChatComposerDock(draft: model.draft, settings: model.settings,
                    maximumEditorHeight: min(160, max(72, geometry.size.height * 0.30)), controls: controls,
                    canSend: model.canCreate, canAttach: model.canAttach && model.prepared != nil,
                    canSelectModel: model.prepared?.capabilities.allows("catalog.model") == true,
                    canSelectPermission: model.prepared?.capabilities.allows("catalog.permission") == true,
                    isBusy: model.isCreating, isLoadingSettings: model.isPreparing,
                    onSend: { text in if let session = await model.create(text: text) { onCreated(session) } },
                    onApplySettings: { model.saveSelections(); return true },
                    onDraftChange: { model.scheduleDraftSave() })
                }
                .frame(maxWidth: ChatControlMetrics.maximumContentWidth).frame(maxWidth: .infinity)
            }
        }
        .modifier(ChatPageToolbar(title: "", onMenu: onMenu))
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showsFiles = true } label: { AppSymbol("folder") }
                    .disabled(!canBrowse)
                    .accessibilityLabel(L("浏览文件"))
                    .accessibilityIdentifier("chat.new.files")
            }
            ToolbarItem(placement: .navigationBarTrailing) { deviceMenu }
        }
        .sheet(isPresented: $showsTarget) {
            SessionTargetSheet(model: model)
        }
        .sheet(isPresented: $showsWorkspace) {
            ProjectSelectionSheet(model: model, repository: repository)
        }
        .sheet(isPresented: $showsFiles) {
            if let device = model.connector, let service = appState.workspaceFilesService {
                WorkspaceFilesSheet(connectorId: device.id, deviceName: device.name,
                    workspace: .init(path: model.workspace.isEmpty ? "~" : model.workspace,
                                     name: workspaceName, sessionCount: 0, lastActiveAt: nil),
                    service: service)
            }
        }
        .compatConfirmationDialog(L("创建结果仍未确认，再次创建可能产生重复会话。"), isPresented: $confirmsRetry, titleVisibility: .visible) {
            Button(L("保留草稿并允许重新创建")) { model.acknowledgeUncertainCreation() }
            Button(L("取消"), role: .cancel) {}
        }
    }

    private var statusContent: some View {
        VStack(alignment: .leading, spacing: 28) {
            connectionStatus
            if model.isCreating {
                Label(L("正在创建会话…"), appSymbol: "arrow.up.circle")
                    .font(.subheadline).foregroundColor(.secondary)
            }
            if let error = model.error {
                VStack(alignment: .leading, spacing: 12) {
                    Text(error).font(.subheadline).foregroundColor(.secondary)
                    if model.creationUncertain {
                        Button(L("查看会话列表"), action: onMenu)
                        Button(L("已检查，重新创建")) { confirmsRetry = true }
                    } else {
                        Button(L("重新连接")) { Task { await refresh() } }
                    }
                }
            }
        }
        .multilineTextAlignment(.leading)
    }

    private var workspaceButton: some View {
        Button { showsWorkspace = true } label: {
            HStack(spacing: 6) {
                AppSymbol("folder", size: 14).foregroundColor(.secondary)
                Text(workspaceName).font(.subheadline.weight(.medium)).foregroundColor(.primary)
                    .lineLimit(1).layoutPriority(1)
                if !model.workspace.isEmpty {
                    Text(model.workspace).font(.system(.footnote, design: .monospaced))
                        .foregroundColor(.secondary).lineLimit(1).truncationMode(.middle)
                }
                if model.loadingHomes.contains(model.connectorID), model.workspace.isEmpty {
                    ProgressView().compatControlSize(.mini)
                } else { AppSymbol("chevron.down", size: 12).foregroundColor(.secondary) }
            }
            .padding(.top, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(model.connector == nil || model.isCreating)
    }

    private var deviceMenu: some View {
        // Menu rows use SF Symbols like the rest of the system menu.
        Menu {
            Button(L("选择设备和 Agent"), systemImage: "sparkles") { chooseTarget() }
            Button(L("选择工作目录"), systemImage: "folder") { showsWorkspace = true }
                .disabled(model.connector == nil)
            if let device = model.connector {
                Divider()
                Button(L("设备详情"), systemImage: "info.circle") { onOpenDevice(device.id) }
                Button(L("Copy device ID"), systemImage: "doc.on.doc") { UIPasteboard.general.string = device.id }
            }
        } label: {
            if model.isPreparing { ProgressView().compatControlSize(.mini) } else { AppSymbol("ellipsis") }
        }
        .disabled(model.isCreating)
        .accessibilityLabel(L("Device actions"))
        .accessibilityIdentifier("chat.new.target")
    }

    private var canBrowse: Bool {
        model.connector?.status == .online && model.network.availability != .offline && model.isValid && !model.isCreating
            && appState.workspaceFilesService != nil
    }

    private func chooseTarget() {
        model.draft.isFocused = false
        showsTarget = true
    }

    @ViewBuilder private var connectionStatus: some View {
        if model.network.availability == .offline {
            status(L("手机网络已断开"), detail: L("草稿和运行目标已保留，网络恢复后会重新检查。"), icon: "wifi.slash")
        } else if dashboardLoading && connectors.isEmpty {
            ProgressView(L("正在查找设备…"))
        } else if connectors.isEmpty {
            status(L("还没有可用设备"), detail: dashboardError ?? L("从侧栏添加设备，连接后即可开始。"), icon: "desktopcomputer")
            Button(L("打开侧栏"), action: onMenu)
        } else if model.connector?.status != .online {
            status(L("目标设备离线"), detail: L("等待它重新连接，或选择其他在线设备。草稿会继续保留。"), icon: "bolt.horizontal.circle")
            Button(L("选择其他设备")) { showsTarget = true }
        } else if model.workspace.isEmpty, let error = model.homeErrors[model.connectorID] {
            status(L("无法解析设备家目录"), detail: error, icon: "folder")
            Button(L("选择工作目录")) { showsWorkspace = true }
        } else if !model.isPreparing && !model.loadingDevices.contains(model.connectorID)
                    && (model.inventories[model.connectorID] != nil || model.inventoryErrors[model.connectorID] != nil)
                    && model.runtime?.isReadyForSession != true {
            status(L("选择一个已就绪的 Agent"),
                detail: model.inventoryErrors[model.connectorID] ?? L("可在设备管理中配置或启动实例。"), icon: "sparkle")
            Button(L("选择 Agent")) { showsTarget = true }
        }
    }

    private var workspaceName: String {
        if !showsSessionList, let project = model.project { return project.name }
        if model.isHome || model.workspace.isEmpty { return L("Home 目录") }
        return ProjectWorkspacePath.name(model.workspace)
    }

    private func status(_ title: String, detail: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, appSymbol: icon).font(.subheadline.weight(.medium))
            Text(detail).font(.footnote).foregroundColor(.secondary)
        }
    }
    private func refresh() async {
        let current = await onRefresh()
        await model.refresh(connectors: current)
    }
}

